import * as THREE from "three";

// ---------------------------------------------------------------------------
// Physics model
//
// Everything here runs on a FIXED timestep accumulated across frames, not on
// the raw frame delta:
//
//   * the rope constraint is stable. Solving a pendulum once per *frame*
//     makes the correction size depend on refresh rate, so the same swing
//     behaves differently at 60fps and 144fps and jitters on a long frame.
//   * nothing tunnels. At 120Hz the player moves ~0.7m per step even at full
//     speed, far smaller than any building, so a cheap circle-vs-AABB
//     push-out is enough.
//   * a dropped frame can't launch you - the step count is capped.
//
// Drag is quadratic, applied semi-implicitly (v /= 1 + k|v|h), which is
// unconditionally stable and gives a real terminal velocity instead of a hard
// clamp: ~55 m/s in free fall, ~65 on a line, ~78 in a dive.
// ---------------------------------------------------------------------------

const FIXED_STEP = 1 / 120;
const MAX_STEPS_PER_FRAME = 8;

const GRAVITY = -34;
const AIR_DRAG = 0.011;
const SWING_DRAG = 0.008;
const DIVE_DRAG = 0.009; // a dive is a deliberately streamlined shape (~78 m/s terminal)

const RUN_ACCEL = 55;
const RUN_MAX_SPEED = 9;
const SPRINT_MAX_SPEED = 15;
const GROUND_FRICTION = 12;
const AIR_ACCEL = 16;
const AIR_MAX_SPEED = 22;
const JUMP_SPEED = 12;
const COYOTE_TIME = 0.12;
const JUMP_BUFFER = 0.12;
const LANDING_SNAP_TOLERANCE = 3;
const PLAYER_RADIUS = 0.4;
const PLAYER_EYE = 1.3;

const SWING_MIN_LEN = 12;
const SWING_MAX_LEN = 95;
const REEL_SPEED = 14;
const REEL_MOMENTUM_CAP = 0.35;
const SWING_LATERAL_ACCEL = 46; // steering authority - the arc should bend when you lean on it
const PUMP_ACCEL = 18;
const SWING_RELEASE_BOOST = 9;
const ATTACH_TANGENT_BOOST = 9;
const ATTACH_LAUNCH_BOOST = 15;
const ATTACH_LAUNCH_LIFT = 7;
const WEB_MAX_DISTANCE = 150;
const WEB_VIRTUAL_DISTANCE = 55;
const ANCHOR_PREFERRED_RISE = 52;
const ANCHOR_MIN_RISE = 24;
const ANCHOR_ROOF_CLEARANCE = 8;
const ANCHOR_ROOF_INSET = 6;
const AUTO_REEL_CLEARANCE = 7;
const AUTO_REEL_RATE = 1.2;
const SWING_GROUND_CLEARANCE = 6;
const ROPE_HAUL_RATE = 16;
const REEL_FLOOR_FRACTION = 0.6;
const CHAIN_WINDOW = 0.45;
const CHAIN_SPEED_KEEP = 1.04;

// Releasing at the right moment is the skill the whole swing is built around
// in Insomniac's games: let go at the flat, fast part of the arc and you keep
// everything and launch; let go while still falling and you just drop. A
// "perfect release" is a deliberate (jump-button) release while moving fast
// and close to horizontal.
const PERFECT_RELEASE_MIN_SPEED = 26;
const PERFECT_RELEASE_FLATNESS = 0.86; // horizontal share of the velocity
const PERFECT_RELEASE_GAIN = 1.14;
const PERFECT_RELEASE_LIFT = 5;

// Dive: hold back (S / stick down) in the air to tuck and drop, trading
// height for speed, then convert it into the next swing.
const DIVE_ACCEL = 22;
const DIVE_MIN_HEIGHT = 6; // no diving once you're about to hit the deck

// Wall crawling.
const WALL_REACH = 0.9; // how close to a facade you must be to stick
const WALL_CLIMB_SPEED = 6.5;
const WALL_STRAFE_SPEED = 5.5;
const WALL_JUMP_OUT = 11;
const WALL_JUMP_UP = 11;
const WALL_STICK_COOLDOWN = 0.35; // after leaving a wall, don't instantly re-stick
const WALL_STICK_SLOW_SPEED = 12; // below this, drifting into a facade always grabs it
const WALL_MANTLE_MARGIN = 0.6; // climbing within this of the roofline pulls you over

const PUNCH_DAMAGE = 1;
const PUNCH_DURATION = 0.3;

const PLAYER_MAX_HEALTH = 100;
const DAMAGE_INVULN = 0.9;
const HURT_ANIM_TIME = 0.45;

const DODGE_DURATION = 0.4;
const DODGE_SPEED = 17;
const DODGE_HOP = 3.2;
const DODGE_COOLDOWN = 0.55;
const DODGE_INVULN = 0.45;
const PERFECT_DODGE_INVULN = 0.8;
const PERFECT_DODGE_RADIUS = 7;

const ZIP_MAX_DISTANCE = 60;
const ZIP_DURATION = 0.32;
const ZIP_ARRIVE_OFFSET = 2.2;
const ZIP_MIN_DISTANCE = 3;
const ZIP_COOLDOWN = 0.15;
const ZIP_EXIT_SPEED = 18;

const CAM_DISTANCE = 8.5;
const CAM_DISTANCE_SPEED_BOOST = 3.5;
const CAM_HEIGHT = 1.5;
const BASE_FOV = 62;
const MAX_FOV_BOOST = 22;
const FOV_SPEED_REF = 45;
const AIM_FOV_ADJUST = -16;
const AIM_MOVE_SCALE = 0.6;
const MAX_CAM_ROLL = 0.42;
const CAM_LEAD = 0.1; // how far the camera looks toward where you're going
const CAM_SHAKE = 0.1;
const SPEED_REF = 85;
const UP = new THREE.Vector3(0, 1, 0);

export class PlayerController {
  constructor(scene, player, city, input, crimes = null) {
    this.scene = scene;
    this.player = player;
    this.city = city;
    this.input = input;
    this.crimes = crimes;

    this.position = new THREE.Vector3(0, 1, 18);
    this.velocity = new THREE.Vector3();
    this.state = "air"; // ground | air | swing | zip | wall

    this.swingAnchor = new THREE.Vector3();
    this.swingLength = 0;
    this.ropeTension = 0;
    this.swingHand = "right";
    this._swingAttachElapsed = 0;
    this._timeSinceRelease = Infinity;
    this._webLatched = false;

    this.wallNormal = new THREE.Vector3(0, 0, 1);
    this.onWall = false;
    this._wallCooldown = 0;

    this.diving = false;

    this._accumulator = 0;
    this._coyote = 0;
    this._jumpBuffer = 0;

    this._punchTimeLeft = 0;
    this._hurtTimeLeft = 0;
    this._invulnTime = 0;
    this._dodgeTimeLeft = 0;
    this._dodgeCooldown = 0;
    this._zipElapsed = 0;
    this._zipCooldown = 0;
    this._zipStart = new THREE.Vector3();
    this._zipTarget = new THREE.Vector3();

    this.health = PLAYER_MAX_HEALTH;
    this.maxHealth = PLAYER_MAX_HEALTH;
    this.dead = false;
    this.onDeath = null;
    this.onPerfectDodge = null;
    this.onPerfectRelease = null;

    this.aiming = false;
    this.aimTarget = null;

    this.raycaster = new THREE.Raycaster();
    this._camRoll = 0;
    this._camShake = 0;
    this._tmpA = new THREE.Vector3();
    this._tmpB = new THREE.Vector3();
    this._webAnchorPoint = new THREE.Vector3();

    const webMat = new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.85 });
    const webGeo = new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(), new THREE.Vector3()]);
    this.webLine = new THREE.Line(webGeo, webMat);
    this.webLine.visible = false;
    this.webLine.frustumCulled = false;
    scene.add(this.webLine);

    const anchorMat = new THREE.MeshBasicMaterial({ color: 0xffffff });
    this.anchorMarker = new THREE.Mesh(new THREE.SphereGeometry(0.4, 10, 8), anchorMat);
    this.anchorMarker.visible = false;
    scene.add(this.anchorMarker);
  }

  get lookDir() {
    return new THREE.Vector3(0, 0, -1)
      .applyAxisAngle(new THREE.Vector3(1, 0, 0), this.input.pitch)
      .applyAxisAngle(UP, this.input.yaw);
  }

  _flatAxes() {
    return {
      forward: new THREE.Vector3(0, 0, -1).applyAxisAngle(UP, this.input.yaw),
      right: new THREE.Vector3(1, 0, 0).applyAxisAngle(UP, this.input.yaw),
    };
  }

  reset(position) {
    this.position.copy(position);
    this.velocity.set(0, 0, 0);
    this.state = "air";
    this.webLine.visible = false;
    this.anchorMarker.visible = false;
    this.health = this.maxHealth;
    this.dead = false;
    this.ropeTension = 0;
    this.onWall = false;
    this.diving = false;
    this._accumulator = 0;
    this._invulnTime = 0;
    this._hurtTimeLeft = 0;
    this._punchTimeLeft = 0;
    this._dodgeTimeLeft = 0;
    this._dodgeCooldown = 0;
    this._zipCooldown = 0;
    this._wallCooldown = 0;
    this._coyote = 0;
    this._jumpBuffer = 0;
    this._timeSinceRelease = Infinity;
    this._webLatched = false;
    this.aiming = false;
    this.aimTarget = null;
  }

  // -------------------------------------------------------------------------
  // Per-frame: input, state transitions, presentation.
  // -------------------------------------------------------------------------
  update(dt, camera) {
    dt = Math.min(dt, 0.1);
    this.input.pollGamepad(dt);

    const tick = (v) => Math.max(0, v - dt);
    this._punchTimeLeft = tick(this._punchTimeLeft);
    this._hurtTimeLeft = tick(this._hurtTimeLeft);
    this._invulnTime = tick(this._invulnTime);
    this._dodgeTimeLeft = tick(this._dodgeTimeLeft);
    this._dodgeCooldown = tick(this._dodgeCooldown);
    this._zipCooldown = tick(this._zipCooldown);
    this._wallCooldown = tick(this._wallCooldown);
    this._coyote = tick(this._coyote);
    this._jumpBuffer = tick(this._jumpBuffer);
    this._timeSinceRelease += dt;

    if (this.dead) {
      this._updateDead(dt);
      return;
    }

    if (this.input.consumeJumpPress()) this._jumpBuffer = JUMP_BUFFER;
    if (this.input.consumeDodgePress()) this._tryDodge();
    if (this.input.consumeZipPress()) this._tryWebZip(camera);
    if (this.input.consumePunchPress()) this._tryPunch();

    this.aiming = this.input.isAimDown() && this.state !== "swing" && this.state !== "zip";
    this.aimTarget = this.aiming ? this._findAimTarget(camera) : null;

    const wantWeb = this.input.mouseDown;
    if (!wantWeb) this._webLatched = false;
    if (this.state !== "zip") {
      if (wantWeb && !this._webLatched && this.state !== "swing") this._tryShootWeb(camera);
      else if (!wantWeb && this.state === "swing") this._release(false);
    }
    // Jumping off a line releases it with a boost. The latch matters: the web
    // button is normally still held at that moment, and without it the next
    // frame re-attaches a fresh line whose constraint eats the boost you just
    // launched with.
    if (this.state === "swing" && this._jumpBuffer > 0) {
      this._jumpBuffer = 0;
      this._release(true);
      this._webLatched = true;
    }

    // Diving: hold back in the air to tuck and trade height for speed.
    this.diving =
      this.state === "air" &&
      this.input.movementVector().z < -0.5 &&
      this.position.y - this.city.groundHeightAt(this.position.x, this.position.z) > DIVE_MIN_HEIGHT;

    this._accumulator += dt;
    let steps = 0;
    while (this._accumulator >= FIXED_STEP && steps < MAX_STEPS_PER_FRAME) {
      this._step(FIXED_STEP);
      this._accumulator -= FIXED_STEP;
      steps++;
    }
    if (steps >= MAX_STEPS_PER_FRAME) this._accumulator = 0;

    this.onWall = this.state === "wall";

    if (this.state !== "swing") {
      this.ropeTension = 0;
      // Release the adaptive trigger when you're off the line, or the last
      // tension value written mid-swing stays latched and R2 feels stuck.
      this.input.setTriggerRumble(0);
    } else {
      this.input.setTriggerRumble(this.ropeTension);
    }

    if (this.state === "ground") this._coyote = COYOTE_TIME;

    this.player.setTransform(this.position, this._modelYaw());
    this.player.updateTilt(dt, this.state, this.velocity, this.input.yaw);
    this.player.updateAnimation(dt, {
      state: this.state,
      groundSpeed: Math.hypot(this.velocity.x, this.velocity.z),
      verticalVelocity: this.velocity.y,
      speed: this.velocity.length(),
      punching: this._punchTimeLeft > 0,
      dodging: this._dodgeTimeLeft > 0,
      hurt: this._hurtTimeLeft > 0,
      diving: this.diving,
      climbing: this.state === "wall" ? Math.hypot(this.velocity.x, this.velocity.y, this.velocity.z) : 0,
      // The reaching arm tracks the live anchor, which is most of what makes
      // a swing read as hanging from a line rather than floating beneath one.
      reachTarget: this.state === "swing" ? this.swingAnchor : null,
      reachHand: this.swingHand,
    });

    // After the animation, so the line leaves the hand where it actually is
    // this frame. Built before it, the hand position is a frame stale and the
    // web visibly hangs off a point beside the glove.
    if (this.state === "swing" || this.state === "zip") this._updateWebLine();
  }

  // On a wall the model faces into the facade instead of along the camera.
  _modelYaw() {
    if (this.state !== "wall") return this.input.yaw;
    return Math.atan2(-this.wallNormal.x, -this.wallNormal.z);
  }

  // The line is drawn from the actual hand bone, not the chest. It is a small
  // thing that does a lot of work: a rope emerging from the middle of the
  // torso reads as a tether, one leaving the hand reads as a web-shooter.
  _updateWebLine() {
    const hand = this.player.getHandWorldPosition(this.swingHand, this._tmpA);
    const from = hand ?? this._tmpA.copy(this.position).addScaledVector(UP, PLAYER_EYE);
    const to = this.state === "zip" ? this._webAnchorPoint : this.swingAnchor;
    this.webLine.geometry.setFromPoints([from, to]);
  }

  _updateDead(dt) {
    this.input.consumeJumpPress();
    this.input.consumePunchPress();
    this.input.consumeZipPress();
    this.input.consumeDodgePress();
    this.input.setTriggerRumble(0);
    this.velocity.x *= Math.max(0, 1 - dt * 4);
    this.velocity.z *= Math.max(0, 1 - dt * 4);
    this.velocity.y += GRAVITY * dt;
    this.position.addScaledVector(this.velocity, dt);
    const floor = this.city.groundHeightAt(this.position.x, this.position.z);
    if (this.position.y <= floor) {
      this.position.y = floor;
      this.velocity.set(0, 0, 0);
    }
    this.player.setTransform(this.position, this.input.yaw);
    this.player.updateAnimation(dt, {
      state: "air",
      groundSpeed: 0,
      verticalVelocity: this.velocity.y,
      speed: 0,
      hurt: true,
    });
  }

  // -------------------------------------------------------------------------
  // One fixed physics step.
  // -------------------------------------------------------------------------
  _step(h) {
    if (this.state === "zip") this._stepZip(h);
    else if (this.state === "swing") this._stepSwing(h);
    else if (this.state === "wall") this._stepWall(h);
    else this._stepGroundAir(h);

    const floorY = this.city.groundHeightAt(this.position.x, this.position.z);
    if (this.position.y < floorY) {
      this.position.y = floorY;
      if (this.velocity.y < 0) this.velocity.y = 0;
      if (this.state === "swing") this._release(false);
      if (this.state !== "zip") this.state = "ground";
    }
  }

  _applyDrag(h, k) {
    const speed = this.velocity.length();
    if (speed < 1e-4) return;
    this.velocity.multiplyScalar(1 / (1 + k * speed * h));
  }

  // Applies the city's push-out and removes the part of the velocity driving
  // into the wall. Without that second half the mover is repositioned every
  // step but keeps its full inward speed, grinding along the facade at 50 m/s
  // while making no progress at all.
  _collideHorizontal(refY, bounce = 1) {
    const push = this.city.resolveHorizontalCollision(this.position, PLAYER_RADIUS, refY);
    if (!push) return false;
    const len = Math.hypot(push.x, push.z);
    if (len < 1e-6) return false;
    const nx = push.x / len;
    const nz = push.z / len;
    const into = this.velocity.x * nx + this.velocity.z * nz;
    if (into < 0) {
      this.velocity.x -= nx * into;
      this.velocity.z -= nz * into;
      this.velocity.x *= bounce;
      this.velocity.z *= bounce;
    }
    return true;
  }

  _stepSwing(h) {
    this._swingAttachElapsed += h;
    const { x: strafe, z: pump } = this.input.movementVector();
    const oldLen = this.swingLength;
    const groundY = this.city.groundHeightAt(this.position.x, this.position.z);

    // A pendulum's lowest point is one rope-length below its anchor, so a rope
    // longer than the anchor is high puts the bottom of the arc underground -
    // all such a "swing" can do is scrape the pavement. The usable range is
    // bounded at both ends: arcCeiling is the longest rope whose arc clears
    // the deck, reelFloor stops you winding in until you're whipping a tight
    // circle around the anchor instead of swinging.
    const arcCeiling = Math.max(SWING_MIN_LEN, this.swingAnchor.y - groundY - SWING_GROUND_CLEARANCE);
    const reelFloor = Math.max(SWING_MIN_LEN, arcCeiling * REEL_FLOOR_FRACTION);

    let newLen = THREE.MathUtils.clamp(oldLen - pump * REEL_SPEED * h, reelFloor, SWING_MAX_LEN);
    if (newLen > arcCeiling) newLen = Math.max(arcCeiling, newLen - ROPE_HAUL_RATE * h);
    const clearance = this.position.y - groundY;
    if (this._swingAttachElapsed > 0.35 && clearance < AUTO_REEL_CLEARANCE) {
      newLen = Math.max(reelFloor, newLen - (AUTO_REEL_CLEARANCE - clearance) * AUTO_REEL_RATE * h);
    }
    this.swingLength = newLen;

    // Shortening the line conserves angular momentum, so tangential speed
    // rises as the radius drops - reeling in at the bottom of an arc is a
    // real speed technique. Capped, or it explodes.
    if (newLen < oldLen - 1e-6) {
      const toPlayer = this._tmpA.copy(this.position).sub(this.swingAnchor);
      const r = toPlayer.length();
      if (r > 1e-4) {
        const n = toPlayer.divideScalar(r);
        const radial = this.velocity.dot(n);
        const tangential = this._tmpB.copy(this.velocity).addScaledVector(n, -radial);
        const gain = Math.min(oldLen / newLen, 1 + REEL_MOMENTUM_CAP * h);
        this.velocity.copy(tangential.multiplyScalar(gain)).addScaledVector(n, radial);
      }
    }

    this.velocity.y += GRAVITY * h;

    const { forward, right } = this._flatAxes();
    if (strafe !== 0) this.velocity.addScaledVector(right, strafe * SWING_LATERAL_ACCEL * h);

    // Pumping pushes along the direction you're *facing*, projected onto the
    // plane the taut rope allows. Pushing along current velocity instead -
    // the obvious reading of "pump the swing" - feeds a conical orbit: energy
    // in tangentially, drag out, equilibrium a fast circle around the anchor.
    // Measured, that was 56 m/s of speed and 3 m/s of progress across the
    // city. Directional thrust spends the same energy on getting somewhere.
    if (pump > 0) {
      const toPlayerN = this._tmpA.copy(this.position).sub(this.swingAnchor);
      const len = toPlayerN.length();
      if (len > 1e-4) {
        toPlayerN.divideScalar(len);
        const thrust = this._tmpB.copy(forward).addScaledVector(toPlayerN, -forward.dot(toPlayerN));
        if (thrust.lengthSq() > 1e-6) this.velocity.addScaledVector(thrust.normalize(), pump * PUMP_ACCEL * h);
      }
    }

    this._applyDrag(h, SWING_DRAG);
    this.position.addScaledVector(this.velocity, h);

    const toPlayer = this._tmpA.copy(this.position).sub(this.swingAnchor);
    const dist = toPlayer.length();
    this.ropeTension = THREE.MathUtils.clamp(dist / this.swingLength, 0, 1);
    if (dist > this.swingLength && dist > 1e-4) {
      const n = toPlayer.divideScalar(dist); // unit, anchor -> player
      this.position.copy(this.swingAnchor).addScaledVector(n, this.swingLength);
      // Cancel only the component pulling *away* from the anchor: a rope can
      // pull, never push, so inward motion is untouched. This is the correct
      // inelastic response, and it's what makes the arc come out clean
      // instead of buzzing the way a position-only clamp does.
      const radial = this.velocity.dot(n);
      if (radial > 0) this.velocity.addScaledVector(n, -radial);
    }

    if (this.position.y < groundY) {
      this.position.y = groundY;
      if (this.velocity.y < 0) this.velocity.y = 0;
    }
    this._collideHorizontal(this.position.y, 0.94);
  }

  _stepGroundAir(h) {
    const { forward, right } = this._flatAxes();
    const { x, z } = this.input.movementVector();
    const wantDir = this._tmpA.set(0, 0, 0).addScaledVector(forward, z).addScaledVector(right, x);
    const grounded = this.state === "ground";

    if (grounded) {
      const maxSpeed =
        (this.input.isSprintDown() ? SPRINT_MAX_SPEED : RUN_MAX_SPEED) * (this.aiming ? AIM_MOVE_SCALE : 1);
      if (wantDir.lengthSq() > 0) {
        wantDir.normalize();
        this.velocity.x += wantDir.x * RUN_ACCEL * h;
        this.velocity.z += wantDir.z * RUN_ACCEL * h;
      } else {
        const speed = Math.hypot(this.velocity.x, this.velocity.z);
        if (speed > 1e-4) {
          const scale = Math.max(0, speed - GROUND_FRICTION * h) / speed;
          this.velocity.x *= scale;
          this.velocity.z *= scale;
        }
      }
      const flat = Math.hypot(this.velocity.x, this.velocity.z);
      if (flat > maxSpeed) {
        this.velocity.x *= maxSpeed / flat;
        this.velocity.z *= maxSpeed / flat;
      }
      this.velocity.y = 0;
    } else {
      if (this.diving) {
        // Tuck and drop: accelerate downward and along your aim, and cut drag.
        this.velocity.y -= DIVE_ACCEL * h;
        this.velocity.addScaledVector(forward, DIVE_ACCEL * 0.45 * h);
      } else if (wantDir.lengthSq() > 0) {
        // Air control that can only ever *add* speed in the direction you're
        // pushing, never scrub what you already have. The obvious version -
        // accelerate, then clamp horizontal speed to a maximum - silently
        // destroys the whole traversal game: launching out of a swing at
        // 52 m/s and holding forward clamped you straight back to 22, so a
        // perfectly timed release ended slower than a lazy one. Projecting
        // current velocity onto the wish direction and only topping it up to
        // the cap keeps momentum intact while still letting you steer.
        wantDir.normalize();
        const along = this.velocity.x * wantDir.x + this.velocity.z * wantDir.z;
        const add = Math.min(AIR_ACCEL * h, Math.max(0, AIR_MAX_SPEED - along));
        this.velocity.x += wantDir.x * add;
        this.velocity.z += wantDir.z * add;
      }
      this.velocity.y += GRAVITY * h;
      this._applyDrag(h, this.diving ? DIVE_DRAG : AIR_DRAG);
    }

    // Coyote time and jump buffering: pressing just after leaving a ledge or
    // just before landing both still work, which is most of what separates a
    // platformer that feels responsive from one that feels like it's ignoring
    // you.
    if (this._jumpBuffer > 0 && (grounded || this._coyote > 0)) {
      this._jumpBuffer = 0;
      this._coyote = 0;
      this.velocity.y = JUMP_SPEED;
      this.state = "air";
    }

    const preMoveY = this.position.y;
    this.position.addScaledVector(this.velocity, h);
    this._collideHorizontal(preMoveY);

    // Only treat a rooftop as landable if it was already within a normal
    // landing's reach before this step - otherwise flying past a building's
    // edge from below snaps you onto its roof. If a roof is too far above,
    // street level is the floor instead, so a player at the foot of a tower
    // doesn't free-fall forever.
    const roofY = this.city.groundHeightAt(this.position.x, this.position.z);
    const landingY = roofY - preMoveY <= LANDING_SNAP_TOLERANCE ? roofY : 0;
    if (this.position.y <= landingY) {
      if (this.state !== "ground" && this.velocity.y < -8) {
        const fallSpeed = -this.velocity.y;
        this.input.rumble({ duration: 110, weak: Math.min(1, fallSpeed / 45), strong: Math.min(1, fallSpeed / 28) });
        const scrub = THREE.MathUtils.clamp(1 - (fallSpeed - 8) / 60, 0.45, 1);
        this.velocity.x *= scrub;
        this.velocity.z *= scrub;
      }
      this.position.y = landingY;
      this.velocity.y = 0;
      this.state = "ground";
      this._coyote = COYOTE_TIME;
    } else {
      this.state = "air";
      if (this._wallCooldown <= 0) this._tryWallStick();
    }
  }

  // -------------------------------------------------------------------------
  // Wall crawling
  // -------------------------------------------------------------------------
  _tryWallStick() {
    const probe = this.city.wallProbe(this.position.x, this.position.y, this.position.z, WALL_REACH + PLAYER_RADIUS);
    if (!probe) return false;

    // Stick on a deliberate approach, not on any graze. Catching every facade
    // you stream past at 40 m/s would interrupt traversal constantly, so a
    // fast shallow pass slides by (ordinary collision handles it) while
    // flying *at* a wall, or drifting into one slowly, grabs it.
    const into = this.velocity.x * probe.normal.x + this.velocity.z * probe.normal.z;
    const approach = -into; // positive means heading into the face
    const speed = this.velocity.length();
    const directness = speed > 1e-3 ? approach / speed : 1;
    if (!(speed < WALL_STICK_SLOW_SPEED || (approach > 2 && directness > 0.3))) return false;

    this.wallNormal.set(probe.normal.x, 0, probe.normal.z);
    this.position.x = probe.point.x + probe.normal.x * (PLAYER_RADIUS + 0.05);
    this.position.z = probe.point.z + probe.normal.z * (PLAYER_RADIUS + 0.05);
    this.velocity.set(0, 0, 0);
    this.state = "wall";
    this.wallTop = probe.top;
    this.input.rumble({ duration: 60, weak: 0.25, strong: 0.2 });
    return true;
  }

  _stepWall(h) {
    const probe = this.city.wallProbe(this.position.x, this.position.y, this.position.z, WALL_REACH + PLAYER_RADIUS + 0.4);
    if (!probe) {
      // Crawled off the edge of the face.
      this.state = "air";
      this._wallCooldown = WALL_STICK_COOLDOWN;
      return;
    }
    this.wallNormal.set(probe.normal.x, 0, probe.normal.z);
    this.wallTop = probe.top;

    // Jump off: away from the wall and up.
    if (this._jumpBuffer > 0) {
      this._jumpBuffer = 0;
      this.state = "air";
      this._wallCooldown = WALL_STICK_COOLDOWN;
      this.velocity.set(this.wallNormal.x * WALL_JUMP_OUT, WALL_JUMP_UP, this.wallNormal.z * WALL_JUMP_OUT);
      this.input.rumble({ duration: 90, weak: 0.3, strong: 0.45 });
      return;
    }

    // Movement maps onto the wall plane: forward/back climbs, left/right
    // crawls sideways along the face.
    const { x: strafe, z: climb } = this.input.movementVector();
    const tangent = this._tmpA.set(-this.wallNormal.z, 0, this.wallNormal.x); // along the face
    this.velocity.set(0, climb * WALL_CLIMB_SPEED, 0).addScaledVector(tangent, strafe * WALL_STRAFE_SPEED);
    this.position.addScaledVector(this.velocity, h);

    // Hold against the face, so rounding a corner or drifting doesn't peel off.
    this.position.x = probe.point.x + this.wallNormal.x * (PLAYER_RADIUS + 0.05);
    this.position.z = probe.point.z + this.wallNormal.z * (PLAYER_RADIUS + 0.05);

    // Reaching the roofline pulls you over the top rather than leaving you
    // stuck at the lip, which is what any climb in any game does.
    if (this.position.y >= probe.top - WALL_MANTLE_MARGIN) {
      this.position.y = probe.top;
      this.position.x -= this.wallNormal.x * (PLAYER_RADIUS + 0.9);
      this.position.z -= this.wallNormal.z * (PLAYER_RADIUS + 0.9);
      this.velocity.set(0, 0, 0);
      this.state = "ground";
      this._wallCooldown = WALL_STICK_COOLDOWN;
      return;
    }
    if (this.position.y <= this.city.groundHeightAt(this.position.x, this.position.z) + 0.05) {
      this.state = "ground";
      this._wallCooldown = WALL_STICK_COOLDOWN;
    }
  }

  _stepZip(h) {
    this._zipElapsed += h;
    const t = Math.min(1, this._zipElapsed / ZIP_DURATION);
    const eased = 1 - Math.pow(1 - t, 3);
    this.position.lerpVectors(this._zipStart, this._zipTarget, eased);
    this._collideHorizontal(this.position.y);
    if (t >= 1) {
      const dir = this._tmpA.copy(this._zipTarget).sub(this._zipStart);
      this.velocity.copy(dir.lengthSq() > 1e-6 ? dir.normalize().multiplyScalar(ZIP_EXIT_SPEED) : new THREE.Vector3());
      this.state = "air";
      this.webLine.visible = false;
      this._zipCooldown = ZIP_COOLDOWN;
    }
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------
  _tryShootWeb(camera) {
    this.raycaster.set(camera.position, this.lookDir);
    this.raycaster.far = WEB_MAX_DISTANCE;
    const hits = this.raycaster.intersectObjects(this.city.colliders, false);

    // Anchor placement decides whether a swing travels or parks you against a
    // wall. A web stuck to the *face* of a building ahead puts that building
    // inside your own arc, so the swing drives you into it and stops you
    // dead. Real swinging happens in the open air of the street canyon,
    // hanging from points above the rooftops - so that's where the line goes.
    let anchor = null;
    if (hits.length > 0) {
      const hit = hits[0];
      const buildingTop =
        hit.object?.position && hit.object?.scale ? hit.object.position.y + hit.object.scale.y / 2 : hit.point.y;
      const toPlayer = this.position.clone().sub(hit.point).setY(0);
      const inset = toPlayer.lengthSq() > 1e-6 ? toPlayer.normalize().multiplyScalar(ANCHOR_ROOF_INSET) : toPlayer;
      anchor = new THREE.Vector3(
        hit.point.x + inset.x,
        Math.max(buildingTop + ANCHOR_ROOF_CLEARANCE, this.position.y + ANCHOR_MIN_RISE),
        hit.point.z + inset.z
      );
    }
    if (!anchor || anchor.y - this.position.y < ANCHOR_MIN_RISE) {
      const origin = this.position.clone().addScaledVector(UP, PLAYER_EYE);
      const flatAim = this.lookDir.clone().setY(0);
      const aim = flatAim.lengthSq() > 1e-4 ? flatAim.normalize() : this._flatAxes().forward;
      anchor = origin.addScaledVector(aim, WEB_VIRTUAL_DISTANCE);
      anchor.y = Math.max(
        this.position.y + ANCHOR_PREFERRED_RISE,
        this.city.groundHeightAt(anchor.x, anchor.z) + ANCHOR_ROOF_CLEARANCE
      );
    }

    const dist = anchor.distanceTo(this.position);
    if (dist < SWING_MIN_LEN) return;

    this.swingAnchor.copy(anchor);
    this._swingAttachElapsed = 0;
    // Hands alternate, the way they do when you actually swing - two webs in
    // a row from the same hand reads as a machine, not a person.
    this.swingHand = this.swingHand === "right" ? "left" : "right";
    // Rope starts at exactly the current distance; any shorter and the first
    // constraint solve yanks you closer, which reads as a teleport.
    this.swingLength = THREE.MathUtils.clamp(dist, SWING_MIN_LEN, SWING_MAX_LEN);
    this.state = "swing";
    this.webLine.visible = true;
    this.anchorMarker.visible = true;
    this.anchorMarker.position.copy(anchor);

    // Attach impulse: project existing velocity onto the plane perpendicular
    // to the rope (the only direction a taut line allows) and push along it,
    // so a swing snaps into its arc instead of sagging into the pendulum.
    // A pendulum started from rest at the bottom of its arc has no height to
    // convert into speed, so a standing attach gets a real leg-driven launch
    // while a running or falling one keeps its own momentum.
    const n = anchor.clone().sub(this.position).normalize();
    const radial = this.velocity.dot(n);
    this.velocity.addScaledVector(n, -Math.min(0, radial));
    let tangent = this.velocity.clone().addScaledVector(n, -this.velocity.dot(n));
    if (tangent.lengthSq() < 1) {
      const { forward } = this._flatAxes();
      tangent = forward.addScaledVector(n, -forward.dot(n));
    }
    const startingSlow = this.velocity.length() < 8;
    if (tangent.lengthSq() > 1e-6) {
      this.velocity.addScaledVector(tangent.normalize(), startingSlow ? ATTACH_LAUNCH_BOOST : ATTACH_TANGENT_BOOST);
    }
    if (startingSlow) this.velocity.y += ATTACH_LAUNCH_LIFT;

    if (this._timeSinceRelease < CHAIN_WINDOW) this.velocity.multiplyScalar(CHAIN_SPEED_KEEP);
    this.input.rumble({ duration: 70, weak: 0.2, strong: 0.12 });
  }

  _release(boost) {
    if (this.state !== "swing") return;
    this.state = "air";
    this.webLine.visible = false;
    this.anchorMarker.visible = false;
    this.ropeTension = 0;
    this._timeSinceRelease = 0;

    if (!boost) return;

    // Timing reward. Let go at the flat, fast part of the arc and you keep
    // everything and launch; let go while still falling and you just drop.
    const speed = this.velocity.length();
    const flatness = speed > 1 ? Math.hypot(this.velocity.x, this.velocity.z) / speed : 0;
    const perfect = speed > PERFECT_RELEASE_MIN_SPEED && flatness > PERFECT_RELEASE_FLATNESS && this.velocity.y > -3;
    if (perfect) {
      this.velocity.multiplyScalar(PERFECT_RELEASE_GAIN);
      this.velocity.y += SWING_RELEASE_BOOST + PERFECT_RELEASE_LIFT;
      this.input.rumble({ duration: 180, weak: 0.5, strong: 0.7 });
      this.onPerfectRelease?.();
    } else {
      this.velocity.y += SWING_RELEASE_BOOST;
    }
  }

  _findAimTarget(camera) {
    this.raycaster.set(camera.position, this.lookDir);
    this.raycaster.far = ZIP_MAX_DISTANCE;
    const hits = this.raycaster.intersectObjects(this.city.colliders, false);
    let point = hits.length > 0 ? hits[0].point.clone() : null;
    let locked = false;
    const enemy = this.crimes?.findAimTarget(camera.position, this.lookDir, ZIP_MAX_DISTANCE);
    if (enemy) {
      point = enemy.position.clone();
      locked = true;
    }
    return point ? { point, locked } : null;
  }

  _tryWebZip(camera) {
    if (this.state === "swing" || this.state === "zip" || this._zipCooldown > 0) return;
    let target = this.aimTarget?.point ?? this._findAimTarget(camera)?.point ?? null;
    if (!target) return;

    const toTarget = target.clone().sub(this.position);
    const dist = toTarget.length();
    if (dist < ZIP_MIN_DISTANCE) return;

    const arriveDist = Math.max(1.5, Math.min(dist, ZIP_MAX_DISTANCE) - ZIP_ARRIVE_OFFSET);
    this._zipStart.copy(this.position);
    this._zipTarget.copy(this.position).addScaledVector(toTarget.normalize(), arriveDist);
    this._webAnchorPoint.copy(target);
    this._zipElapsed = 0;
    this.state = "zip";
    this.webLine.visible = true;
    this.anchorMarker.visible = false;
    this.input.rumble({ duration: 90, weak: 0.3, strong: 0.5 });
  }

  _tryPunch() {
    if (!this.crimes || this.state === "swing" || this.state === "zip") return;
    this._punchTimeLeft = PUNCH_DURATION;
    const { hit, defeated } = this.crimes.tryPunch(this.position, PUNCH_DAMAGE);
    if (defeated) this.input.rumble({ duration: 200, weak: 0.6, strong: 1 });
    else if (hit) this.input.rumble({ duration: 90, weak: 0.35, strong: 0.55 });
  }

  _tryDodge() {
    if (this.dead || this._dodgeCooldown > 0 || this.state === "swing" || this.state === "zip") return;
    const { forward, right } = this._flatAxes();
    const { x, z } = this.input.movementVector();
    const dir = new THREE.Vector3().addScaledVector(forward, z).addScaledVector(right, x);
    if (dir.lengthSq() < 0.01) dir.copy(forward).multiplyScalar(-1);
    dir.normalize();

    const perfect = !!this.crimes?.isDangerNear(this.position, PERFECT_DODGE_RADIUS);
    this._dodgeTimeLeft = DODGE_DURATION;
    this._dodgeCooldown = DODGE_COOLDOWN;
    this._invulnTime = Math.max(this._invulnTime, perfect ? PERFECT_DODGE_INVULN : DODGE_INVULN);

    this.velocity.x = dir.x * DODGE_SPEED;
    this.velocity.z = dir.z * DODGE_SPEED;
    if (this.state === "ground" || this.state === "wall") {
      this.velocity.y = DODGE_HOP;
      this.state = "air";
      this._wallCooldown = WALL_STICK_COOLDOWN;
    }

    if (perfect) {
      this.input.rumble({ duration: 220, weak: 0.7, strong: 0.9 });
      this.onPerfectDodge?.();
    } else {
      this.input.rumble({ duration: 90, weak: 0.25, strong: 0.35 });
    }
  }

  takeDamage(amount) {
    if (!amount || amount <= 0 || this._invulnTime > 0 || this.state === "zip" || this.dead) return;
    this.health = Math.max(0, this.health - amount);
    this._invulnTime = DAMAGE_INVULN;
    this._hurtTimeLeft = HURT_ANIM_TIME;
    this.input.rumble({ duration: 160, weak: 0.5, strong: 0.85 });
    if (this.health <= 0) {
      this.dead = true;
      this.state = "air";
      this.webLine.visible = false;
      this.anchorMarker.visible = false;
      this.input.rumble({ duration: 500, weak: 1, strong: 1 });
      this.onDeath?.();
    }
  }

  // -------------------------------------------------------------------------
  // Chase camera
  // -------------------------------------------------------------------------
  updateCamera(camera, dt) {
    const speed = this.velocity.length();
    const speedRatio = THREE.MathUtils.clamp(speed / SPEED_REF, 0, 1);

    const target = this.position.clone().addScaledVector(UP, CAM_HEIGHT);
    const dir = this.lookDir;
    const camDistance = CAM_DISTANCE + speedRatio * CAM_DISTANCE_SPEED_BOOST;
    const desired = target.clone().addScaledVector(dir, -camDistance);
    desired.y = Math.max(desired.y, this.city.groundHeightAt(desired.x, desired.z) + 1.2);

    const toDesired = desired.clone().sub(target);
    const distToDesired = toDesired.length();
    if (distToDesired > 0.001) {
      this.raycaster.set(target, toDesired.clone().normalize());
      this.raycaster.far = distToDesired;
      const hits = this.raycaster.intersectObjects(this.city.colliders, false);
      if (hits.length > 0) {
        desired.copy(target).addScaledVector(toDesired.normalize(), Math.max(1.5, hits[0].distance - 0.5));
      }
    }

    // A little camera shake at speed. Small enough to read as wind rather
    // than a rattle, and gated on speed so standing still is rock steady.
    this._camShake = THREE.MathUtils.lerp(this._camShake, speedRatio * CAM_SHAKE, 1 - Math.exp(-6 * dt));
    if (this._camShake > 0.002) {
      desired.x += (Math.random() - 0.5) * this._camShake;
      desired.y += (Math.random() - 0.5) * this._camShake;
    }

    if (!camera.userData.initialized) {
      camera.position.copy(desired);
      camera.userData.initialized = true;
    } else {
      // Exponential smoothing written frame-rate independently, so the camera
      // lags by the same amount of *time* at any refresh rate.
      camera.position.lerp(desired, 1 - Math.exp(-10 * dt));
    }

    const right = new THREE.Vector3(dir.z, 0, -dir.x);
    const lateralSpeed = this.velocity.dot(right);
    const rollTarget =
      this.state === "swing" ? THREE.MathUtils.clamp(-lateralSpeed / SPEED_REF, -1, 1) * MAX_CAM_ROLL : 0;
    this._camRoll = THREE.MathUtils.lerp(this._camRoll, rollTarget, 1 - Math.exp(-5 * dt));
    camera.up.copy(UP.clone().applyAxisAngle(dir, this._camRoll));

    // Lead the shot slightly toward where you're actually travelling, not
    // just where you're aiming - at speed those diverge, and leading them
    // sells the sense of being carried by the arc.
    const lookAt = target.clone().addScaledVector(dir, 4);
    if (speed > 1) lookAt.addScaledVector(this.velocity, (CAM_LEAD * speedRatio) / Math.max(1, speed / 20));
    camera.lookAt(lookAt);

    const speedFactor = THREE.MathUtils.clamp(speed / FOV_SPEED_REF, 0, 1);
    const targetFov = BASE_FOV + speedFactor * MAX_FOV_BOOST + (this.aiming ? AIM_FOV_ADJUST : 0);
    camera.fov = THREE.MathUtils.lerp(camera.fov, targetFov, 1 - Math.exp(-4 * dt));
    camera.updateProjectionMatrix();
  }
}
