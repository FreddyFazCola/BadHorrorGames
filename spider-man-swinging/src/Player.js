import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { loadModelArrayBuffer } from "./modelLoader.js";

// The source model ships with no animation clips, so every pose here is driven
// by rotating named rig bones each frame. The axis and sign each bone needs
// (which local axis swings a limb forward vs sideways, and which sign means
// which direction) was determined empirically per bone, by rotating it in
// isolation and comparing world-space positions before and after - the rig
// documents neither.
//
// The rig has full arm chains (clavicle -> upperarm -> lowerarm -> hand ->
// fingers) and a neck. Driving only the shoulder leaves the arm ruler-straight
// from shoulder to fingertip, which reads as a mannequin being posed however
// much the shoulder swings; the elbows carry most of the readability.
export const BONE_NAMES = {
  thighL: "thigh_l_054",
  thighR: "thigh_r_068",
  calfL: "calf_l_055",
  calfR: "calf_r_069",
  ballL: "ball_l_057",
  ballR: "ball_r_072",
  upperArmL: "upperarm_l_0126",
  upperArmR: "upperarm_r_0171",
  lowerArmL: "lowerarm_l_0127",
  lowerArmR: "lowerarm_r_0172",
  handL: "hand_l_0128",
  handR: "hand_r_0173",
  clavicleL: "clavicle_l_0125",
  clavicleR: "clavicle_r_0170",
  neck: "neck_01_0142",
  spine: "spine_03_0109",
  head: "head_0164",
};

// Bind pose is a T-pose; this brings each upper arm down to a relaxed rest.
export const ARM_REST_Y = 1.3;
// Elbows are never locked out on a real body, even at rest. On both arms,
// negative local Z on the lowerarm folds the forearm up and forward.
export const ELBOW_REST = -0.28;

const SPRINT_REF_SPEED = 9;
const PUNCH_ANIM_DURATION = 0.3;
const DODGE_ANIM_DURATION = 0.4;
const HURT_ANIM_DURATION = 0.45;
const IDLE_FIDGET_DELAY = 5.5;
const IDLE_FIDGET_BLEND = 0.7;

let sharedWebTexture = null;
function getWebTexture() {
  if (sharedWebTexture) return sharedWebTexture;
  const size = 128;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, size, size);
  ctx.strokeStyle = "rgba(0,0,0,0.35)";
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  for (let i = -size; i <= size * 2; i += 14) {
    ctx.moveTo(i, 0);
    ctx.lineTo(i - size, size);
    ctx.moveTo(i, 0);
    ctx.lineTo(i + size, size);
  }
  ctx.stroke();
  const tex = new THREE.CanvasTexture(canvas);
  tex.wrapS = THREE.RepeatWrapping;
  tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(6, 6);
  tex.colorSpace = THREE.SRGBColorSpace;
  sharedWebTexture = tex;
  return tex;
}

const CUBE_FACE_COLORS = ["#d61f1f", "#ff8c1a", "#f2f2f2", "#f5d914", "#1fa83c", "#1f52d6"];
function makeRubiksCube() {
  const materials = CUBE_FACE_COLORS.map((color) => {
    const size = 64;
    const canvas = document.createElement("canvas");
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#0a0a0a";
    ctx.fillRect(0, 0, size, size);
    const pad = size * 0.06;
    const cell = (size - pad * 4) / 3;
    ctx.fillStyle = color;
    for (let row = 0; row < 3; row++) {
      for (let col = 0; col < 3; col++) {
        ctx.fillRect(pad + col * (cell + pad), pad + row * (cell + pad), cell, cell);
      }
    }
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    return new THREE.MeshStandardMaterial({ map: tex, roughness: 0.45, metalness: 0.02 });
  });
  const cube = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), materials);
  cube.frustumCulled = false;
  return cube;
}

export class Player {
  constructor(scene) {
    this.root = new THREE.Object3D();
    scene.add(this.root);
    this.pivot = new THREE.Object3D();
    this.root.add(this.pivot);

    this.model = null;
    this.bones = {};
    this.cube = null;
    this._restFeetY = 0;
    this._tmpVec = new THREE.Vector3();
    this._reachLocal = new THREE.Vector3();
    this._runPhase = 0;
    this._idlePhase = 0;
    this._climbPhase = 0;
    this._punchPhase = 1;
    this._dodgePhase = 1;
    this._hurtPhase = 1;
    this._idleStillTime = 0;
    this._fidgetAmount = 0;
    this._cubeSolvePhase = 0;
    this._currentTilt = new THREE.Quaternion();

    const loader = new GLTFLoader();
    loadModelArrayBuffer()
      .then((buf) =>
        loader.parse(
          buf,
          "",
          (gltf) => this._onModelReady(gltf.scene),
          (err) => console.error("Failed to parse player model", err)
        )
      )
      .catch((err) => console.error("Failed to fetch player model", err));
  }

  _onModelReady(model) {
    model.traverse((child) => {
      if (child.isMesh) {
        child.castShadow = false;
        child.receiveShadow = false;
        child.frustumCulled = false;
      }
    });
    this._colorMaterials(model);

    model.rotation.set(0, Math.PI, 0); // rig faces +Z; the camera rig treats -Z as forward
    model.position.set(0, 0, 0);
    this.pivot.add(model);
    this.model = model;

    for (const [key, name] of Object.entries(BONE_NAMES)) this.bones[key] = model.getObjectByName(name);
    this.bones.upperArmL?.rotation.set(0, ARM_REST_Y, 0);
    this.bones.upperArmR?.rotation.set(0, ARM_REST_Y, 0);
    this.bones.lowerArmL?.rotation.set(0, 0, ELBOW_REST);
    this.bones.lowerArmR?.rotation.set(0, 0, ELBOW_REST);

    const hand = this.bones.handL;
    if (hand) {
      this.cube = makeRubiksCube();
      const handScale = hand.getWorldScale(new THREE.Vector3());
      this.cube.scale.setScalar(0.062 / Math.max(handScale.x, 1e-6));
      this.cube.position.set(0, 0.06 / Math.max(handScale.y, 1e-6), 0);
      this.cube.visible = false;
      hand.add(this.cube);
    }

    // The load is async, so gameplay may already have moved `root`. Measure
    // the rest height with root neutralised so the calibration isn't
    // contaminated by wherever the player happens to be.
    const rootPos = this.root.position.clone();
    const rootRot = this.root.rotation.clone();
    this.root.position.set(0, 0, 0);
    this.root.rotation.set(0, 0, 0);
    this.root.updateMatrixWorld(true);
    this._restFeetY = this._lowestFootWorldY();
    this.root.position.copy(rootPos);
    this.root.rotation.copy(rootRot);
    this.root.updateMatrixWorld(true);
  }

  _colorMaterials(model) {
    const webTex = getWebTexture();
    model.traverse((child) => {
      if (!child.isMesh || !child.material) return;
      const name = child.material.name;
      const mat = new THREE.MeshStandardMaterial({ roughness: 0.55, metalness: 0.05 });
      if (name === "MI_HerbalFist_Mask") {
        mat.color.set(0xb01423);
        mat.map = webTex;
      } else if (name === "MI_HerbalFist_Body") {
        mat.color.set(0x1c3f9c);
        mat.map = webTex;
      } else {
        mat.color.set(0xf2f2f2);
        mat.emissive.set(0xffffff);
        mat.emissiveIntensity = 0.15;
        mat.roughness = 0.3;
      }
      child.material = mat;
    });
  }

  _lowestFootWorldY() {
    if (!this.bones.ballL || !this.bones.ballR) return 0;
    this.bones.ballL.getWorldPosition(this._tmpVec);
    const leftY = this._tmpVec.y;
    this.bones.ballR.getWorldPosition(this._tmpVec);
    return Math.min(leftY, this._tmpVec.y);
  }

  // World position of a hand bone, so the web line can leave the hand rather
  // than the middle of the chest. Returns null before the model has loaded.
  getHandWorldPosition(side, out = new THREE.Vector3()) {
    const bone = side === "left" ? this.bones.handL : this.bones.handR;
    if (!bone) return null;
    return bone.getWorldPosition(out);
  }

  updateAnimation(
    dt,
    {
      state,
      groundSpeed,
      verticalVelocity,
      speed = 0,
      punching = false,
      dodging = false,
      hurt = false,
      diving = false,
      climbing = 0,
      reachTarget = null,
      reachHand = "right",
    }
  ) {
    if (!this.model) return;
    const b = this.bones;
    let bob = 0;

    if (punching && this._punchPhase >= 1) this._punchPhase = 0;
    if (this._punchPhase < 1) this._punchPhase += dt / PUNCH_ANIM_DURATION;
    if (dodging && this._dodgePhase >= 1) this._dodgePhase = 0;
    if (this._dodgePhase < 1) this._dodgePhase += dt / DODGE_ANIM_DURATION;
    if (hurt && this._hurtPhase >= 1) this._hurtPhase = 0;
    if (this._hurtPhase < 1) this._hurtPhase += dt / HURT_ANIM_DURATION;

    const settled =
      state === "ground" && groundSpeed <= 0.4 && this._punchPhase >= 1 && this._dodgePhase >= 1 && this._hurtPhase >= 1;
    this._idleStillTime = settled ? this._idleStillTime + dt : 0;
    const fidgetTarget = this._idleStillTime > IDLE_FIDGET_DELAY ? 1 : 0;
    const step = dt / IDLE_FIDGET_BLEND;
    this._fidgetAmount = THREE.MathUtils.clamp(
      this._fidgetAmount + (fidgetTarget > this._fidgetAmount ? step : -step * 2),
      0,
      1
    );

    if (state === "wall") {
      // Wall crawl: limbs splayed wide and flattened against the facade, with
      // a slow diagonal crawl cycle when moving. A standing pose stuck to a
      // wall reads as a decal; the spread is what sells the stick.
      this._climbPhase += dt * (1.5 + Math.min(climbing, 8) * 0.7);
      const crawl = Math.sin(this._climbPhase) * Math.min(1, climbing / 3);
      this._lerpBone(b.upperArmR, "y", 0.35, dt, 10);
      this._lerpBone(b.upperArmR, "x", -1.15 + crawl * 0.45, dt, 10);
      this._lerpBone(b.upperArmL, "y", 0.35, dt, 10);
      this._lerpBone(b.upperArmL, "x", -1.15 - crawl * 0.45, dt, 10);
      this._lerpBone(b.lowerArmR, "z", -0.9, dt, 10);
      this._lerpBone(b.lowerArmL, "z", -0.9, dt, 10);
      this._lerpBone(b.thighR, "x", -0.5 - crawl * 0.35, dt, 10);
      this._lerpBone(b.thighL, "x", -0.5 + crawl * 0.35, dt, 10);
      this._lerpBone(b.calfR, "z", 0.95, dt, 10);
      this._lerpBone(b.calfL, "z", 0.95, dt, 10);
      this._lerpBone(b.spine, "x", -0.25, dt, 8);
      this._lerpBone(b.neck, "x", -0.35, dt, 8); // head up, looking where he's going
      this._lerpBone(b.head, "x", -0.2, dt, 8);
    } else if (state === "ground" && groundSpeed > 0.4) {
      const speedFactor = Math.min(groundSpeed / SPRINT_REF_SPEED, 1.6);
      this._runPhase += dt * (6.5 + speedFactor * 6);
      const swing = Math.sin(this._runPhase);
      if (b.thighR) b.thighR.rotation.x = -swing * 0.5;
      if (b.thighL) b.thighL.rotation.x = swing * 0.5;
      // Lerped rather than hard-set to the thigh angle: an instantaneous 1:1
      // knee/thigh coupling reads as robotic, a frame or two of lag reads as
      // a joint with some give.
      this._lerpBone(b.calfR, "z", Math.max(0, -(b.thighR?.rotation.x ?? 0)) * 1.05, dt, 20);
      this._lerpBone(b.calfL, "z", Math.max(0, -(b.thighL?.rotation.x ?? 0)) * 1.05, dt, 20);
      if (b.upperArmR) b.upperArmR.rotation.set(-0.25, ARM_REST_Y, swing * 0.5);
      if (b.upperArmL) b.upperArmL.rotation.set(-0.25, ARM_REST_Y, -swing * 0.5);
      const elbowBase = THREE.MathUtils.lerp(-0.7, -1.15, Math.min(1, speedFactor));
      this._lerpBone(b.lowerArmR, "z", elbowBase + swing * 0.35, dt, 18);
      this._lerpBone(b.lowerArmL, "z", elbowBase - swing * 0.35, dt, 18);
      this._lerpBone(b.spine, "x", 0.1 + speedFactor * 0.08, dt, 8);
      this._lerpBone(b.clavicleR, "z", swing * 0.06, dt, 12);
      this._lerpBone(b.clavicleL, "z", -swing * 0.06, dt, 12);
      if (b.head) b.head.rotation.set(0, 0, 0);
      if (b.neck) b.neck.rotation.x = -0.08;
      bob = Math.abs(swing) * 0.045;
    } else if (state === "ground") {
      this._idlePhase += dt * 1.6;
      const sway = Math.sin(this._idlePhase);
      this._lerpBone(b.thighR, "x", 0, dt);
      this._lerpBone(b.thighL, "x", 0, dt);
      this._lerpBone(b.calfR, "z", 0, dt);
      this._lerpBone(b.calfL, "z", 0, dt);
      if (b.upperArmR) b.upperArmR.rotation.set(0, ARM_REST_Y, sway * 0.05);
      if (b.upperArmL) b.upperArmL.rotation.set(0, ARM_REST_Y, -sway * 0.05);
      this._lerpBone(b.lowerArmR, "z", ELBOW_REST + sway * 0.05, dt, 6);
      this._lerpBone(b.lowerArmL, "z", ELBOW_REST - sway * 0.05, dt, 6);
      this._lerpBone(b.spine, "x", Math.sin(this._idlePhase * 0.5) * 0.02, dt, 8);
      if (b.head) b.head.rotation.y = Math.sin(this._idlePhase * 0.31) * 0.1;
      if (b.neck) b.neck.rotation.x = 0;
      bob = Math.sin(this._idlePhase) * 0.012;
    } else if (state === "swing") {
      // Blends from a relaxed "just grabbed the line" hang into a streamlined
      // tuck as speed builds, so a fast swing reads as cutting through the air
      // rather than holding the shape it had when it attached.
      const t = THREE.MathUtils.clamp(speed / 55, 0, 1);
      this._lerpBone(b.thighR, "x", THREE.MathUtils.lerp(-0.15, -0.6, t), dt, 6);
      this._lerpBone(b.thighL, "x", THREE.MathUtils.lerp(-0.15, -0.45, t), dt, 6);
      this._lerpBone(b.calfR, "z", THREE.MathUtils.lerp(0.5, 0.15, t), dt, 6);
      this._lerpBone(b.calfL, "z", THREE.MathUtils.lerp(0.5, 0.55, t), dt, 6);
      this._lerpBone(b.spine, "x", THREE.MathUtils.lerp(-0.1, -0.35, t), dt, 6);
      this._lerpBone(b.neck, "x", THREE.MathUtils.lerp(0, -0.2, t), dt, 6);

      // The free arm trails; the swinging arm is overwritten by the reach
      // overlay below so it actually points at the line.
      const freeArm = reachHand === "right" ? "L" : "R";
      this._lerpBone(b[`upperArm${freeArm}`], "y", THREE.MathUtils.lerp(0.9, 0.45, t), dt, 6);
      this._lerpBone(b[`upperArm${freeArm}`], "x", THREE.MathUtils.lerp(0.3, 0.75, t), dt, 6);
      this._lerpBone(b[`lowerArm${freeArm}`], "z", THREE.MathUtils.lerp(-0.6, -0.3, t), dt, 6);
    } else {
      // Airborne. A dive is its own shape: head-down, arms swept back, legs
      // straight - the streamlined tuck that earns the extra speed.
      const rising = verticalVelocity > 1;
      const fallT = THREE.MathUtils.clamp(-verticalVelocity / 40, 0, 1);
      if (diving) {
        this._lerpBone(b.thighR, "x", -0.25, dt, 7);
        this._lerpBone(b.thighL, "x", -0.25, dt, 7);
        this._lerpBone(b.calfR, "z", 0.05, dt, 7);
        this._lerpBone(b.calfL, "z", 0.05, dt, 7);
        this._lerpBone(b.upperArmR, "y", 0.2, dt, 7);
        this._lerpBone(b.upperArmR, "x", 1.25, dt, 7);
        this._lerpBone(b.upperArmL, "y", 0.2, dt, 7);
        this._lerpBone(b.upperArmL, "x", 1.25, dt, 7);
        this._lerpBone(b.lowerArmR, "z", -0.2, dt, 7);
        this._lerpBone(b.lowerArmL, "z", -0.2, dt, 7);
        this._lerpBone(b.spine, "x", -0.3, dt, 7);
        this._lerpBone(b.neck, "x", -0.3, dt, 7);
      } else {
        this._lerpBone(b.thighR, "x", rising ? 0.35 : THREE.MathUtils.lerp(-0.1, -0.3, fallT), dt, 5);
        this._lerpBone(b.thighL, "x", rising ? 0.35 : THREE.MathUtils.lerp(-0.1, -0.3, fallT), dt, 5);
        this._lerpBone(b.calfR, "z", rising ? 0.9 : THREE.MathUtils.lerp(0.15, 0.05, fallT), dt, 5);
        this._lerpBone(b.calfL, "z", rising ? 0.9 : THREE.MathUtils.lerp(0.15, 0.05, fallT), dt, 5);
        this._lerpBone(b.upperArmR, "y", ARM_REST_Y * 0.5, dt, 5);
        this._lerpBone(b.upperArmR, "x", -0.3, dt, 5);
        this._lerpBone(b.upperArmL, "y", ARM_REST_Y * 0.5, dt, 5);
        this._lerpBone(b.upperArmL, "x", -0.3, dt, 5);
        this._lerpBone(b.lowerArmR, "z", THREE.MathUtils.lerp(-0.55, -1.0, fallT), dt, 5);
        this._lerpBone(b.lowerArmL, "z", THREE.MathUtils.lerp(-0.55, -1.0, fallT), dt, 5);
        this._lerpBone(b.spine, "x", rising ? -0.05 : THREE.MathUtils.lerp(0.1, 0.25, fallT), dt, 5);
        this._lerpBone(b.neck, "x", 0, dt, 5);
      }
    }

    // Reach overlay: the swinging arm points at the live anchor. Not real IK -
    // the anchor direction is converted into the model's own frame and mapped
    // onto the shoulder's two useful axes, which is enough for the arm to
    // track the line as the arc carries you under and past it.
    if (reachTarget) {
      const side = reachHand === "right" ? "R" : "L";
      const upper = this.bones[`upperArm${side}`];
      const lower = this.bones[`lowerArm${side}`];
      if (upper) {
        this._reachLocal.copy(reachTarget);
        this.root.worldToLocal(this._reachLocal);
        const horiz = Math.max(0.001, Math.hypot(this._reachLocal.x, this._reachLocal.z));
        const elevation = Math.atan2(this._reachLocal.y, horiz); // + is above
        // A high anchor sweeps the arm overhead (upperarm x negative raises
        // it forward/up); sideways offset swings it out.
        const raise = THREE.MathUtils.clamp(-0.35 - elevation * 1.15, -1.9, 0.2);
        const outward = THREE.MathUtils.clamp(this._reachLocal.x / horiz, -1, 1) * (side === "R" ? -1 : 1);
        upper.rotation.x = raise;
        upper.rotation.y = THREE.MathUtils.clamp(0.55 + outward * 0.5, 0, 1.4);
        upper.rotation.z = 0;
        if (lower) lower.rotation.z = -0.35; // nearly straight, taking the load
      }
    }

    if (this._punchPhase < 1 && b.upperArmR) {
      const amt = Math.sin(THREE.MathUtils.clamp(this._punchPhase, 0, 1) * Math.PI);
      this._blendBone(b.upperArmR, "x", -1.4, amt);
      this._blendBone(b.upperArmR, "y", ARM_REST_Y * 0.3, amt);
      // The elbow drives the punch: cocked at the start, snapping through to
      // almost straight at full extension, which sells an impact far more
      // than rotating the shoulder does.
      if (b.lowerArmR) {
        this._blendBone(b.lowerArmR, "z", THREE.MathUtils.lerp(-1.7, -0.1, Math.min(1, this._punchPhase * 1.6)), amt);
      }
      this._blendBone(b.lowerArmL, "z", -1.6, amt * 0.8);
      if (b.spine) b.spine.rotation.y = -0.25 * amt;
    }

    if (this._dodgePhase < 1) {
      const d = Math.sin(THREE.MathUtils.clamp(this._dodgePhase, 0, 1) * Math.PI);
      if (b.spine) {
        b.spine.rotation.x += 0.5 * d;
        b.spine.rotation.y += 0.4 * d;
      }
      this._blendBone(b.thighR, "x", 0.7, d);
      this._blendBone(b.thighL, "x", 0.35, d);
      this._blendBone(b.calfR, "z", 1.0, d);
      this._blendBone(b.calfL, "z", 0.7, d);
      this._blendBone(b.lowerArmR, "z", -1.9, d);
      this._blendBone(b.lowerArmL, "z", -1.9, d);
      this._blendBone(b.upperArmR, "x", -0.5, d);
      this._blendBone(b.upperArmL, "x", -0.5, d);
      bob -= 0.25 * d;
    }

    if (this._hurtPhase < 1) {
      const hAmt = Math.sin(THREE.MathUtils.clamp(this._hurtPhase, 0, 1) * Math.PI);
      if (b.spine) b.spine.rotation.x -= 0.45 * hAmt;
      this._blendBone(b.head, "x", 0.4, hAmt);
      this._blendBone(b.upperArmR, "z", 0.5, hAmt);
      this._blendBone(b.upperArmL, "z", -0.5, hAmt);
      this._blendBone(b.lowerArmR, "z", -1.3, hAmt);
      this._blendBone(b.lowerArmL, "z", -1.3, hAmt);
    }

    if (this.cube) {
      const f = this._fidgetAmount;
      this.cube.visible = f > 0.02;
      if (f > 0.02) {
        this._cubeSolvePhase += dt * 2.2;
        this._blendBone(b.upperArmR, "x", -0.55, f);
        this._blendBone(b.upperArmR, "y", 1.28, f);
        this._blendBone(b.upperArmR, "z", 0.1, f);
        this._blendBone(b.upperArmL, "x", -0.55, f);
        this._blendBone(b.upperArmL, "y", 1.28, f);
        this._blendBone(b.upperArmL, "z", -0.1, f);
        this._blendBone(b.lowerArmR, "z", -1.95, f);
        this._blendBone(b.lowerArmL, "z", -1.95, f);
        this._blendBone(b.neck, "x", -0.18, f);
        this._blendBone(b.head, "x", -0.32, f);
        const twist = Math.sin(this._cubeSolvePhase);
        this._blendBone(b.handR, "z", twist * 0.7, f);
        this._blendBone(b.handL, "z", -twist * 0.15, f);
        const quarters = Math.floor(this._cubeSolvePhase / Math.PI);
        this.cube.rotation.set(quarters * (Math.PI / 4), quarters * (Math.PI / 2), twist * 0.25);
      }
    }

    // Keep the animated feet out of the ground whatever pose just ran -
    // measured live from the two ball-of-foot bones rather than a precomputed
    // curve, so it stays correct for any future pose tweak. Skipped on a wall,
    // where "down" for the body isn't world down at all.
    this.model.position.y = -this._restFeetY + bob;
    this.root.updateMatrixWorld(true);
    if (state !== "wall") {
      const dip = this._lowestFootWorldY() - this.root.position.y;
      if (dip < 0) {
        this.model.position.y -= dip;
        this.root.updateMatrixWorld(true);
      }
    }
  }

  _lerpBone(bone, axis, target, dt, speed = 8) {
    if (!bone) return;
    bone.rotation[axis] += (target - bone.rotation[axis]) * Math.min(1, dt * speed);
  }

  // Overlay blend, as opposed to _lerpBone's time-based ease: mixes a target
  // over whatever the state pose already wrote this frame, by an explicit
  // 0..1 amount driven by the overlay's own phase curve.
  _blendBone(bone, axis, target, amount) {
    if (!bone) return;
    bone.rotation[axis] = THREE.MathUtils.lerp(bone.rotation[axis], target, amount);
  }

  setTransform(position, yaw) {
    this.root.position.copy(position);
    this.root.rotation.y = yaw;
  }

  updateTilt(dt, state, velocity, forwardYaw) {
    let pitch = 0;
    let roll = 0;
    const speed = velocity.length();
    if (state === "wall") {
      // Lean the body into the facade so he lies against it rather than
      // standing in front of it.
      pitch = -1.15;
    } else if (state === "swing" || state === "air" || state === "zip") {
      const localForward = new THREE.Vector3(Math.sin(forwardYaw), 0, Math.cos(forwardYaw));
      const rightAxis = new THREE.Vector3(localForward.z, 0, -localForward.x);
      const vNorm = speed > 0.01 ? velocity.clone().multiplyScalar(1 / speed) : new THREE.Vector3();
      pitch = THREE.MathUtils.clamp(-vNorm.y * 0.9, -0.9, 0.9);
      roll = THREE.MathUtils.clamp(-vNorm.dot(rightAxis) * 0.6, -0.7, 0.7);
    }
    const targetQuat = new THREE.Quaternion().setFromEuler(new THREE.Euler(pitch, 0, roll));
    this._currentTilt.slerp(targetQuat, Math.min(1, dt * (state === "wall" ? 10 : 6)));
    this.pivot.quaternion.copy(this._currentTilt);
  }
}
