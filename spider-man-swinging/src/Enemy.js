import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { loadModelArrayBuffer } from "./modelLoader.js";
import { BONE_NAMES, ARM_REST_Y, ELBOW_REST } from "./Player.js";

const HIT_POINTS = 3;
const FLINCH_DURATION = 0.35;
const DEFEAT_DURATION = 1.1;

// A thug notices the player from AGGRO_RANGE, closes in (never wandering more
// than LEASH_RANGE from where it spawned - it's guarding a crime scene, not
// chasing across the map), winds up a visible haymaker (TELEGRAPH_DURATION,
// which CrimeSystem surfaces as "spidey sense" so there's a fair window to
// dodge or punch first), then swings. The hit is checked once, partway
// through the swing, against whoever is still in range at that instant.
const AGGRO_RANGE = 16;
const ATTACK_RANGE = 2.6;
const LEASH_RANGE = 11;
const MOVE_SPEED = 3.4;
const TELEGRAPH_DURATION = 0.55;
const ATTACK_DURATION = 0.35;
const ATTACK_HIT_T = 0.55;
const RECOVER_MIN = 0.5;
const RECOVER_MAX = 1.1;
const ATTACK_DAMAGE = 12;

export class Enemy {
  constructor(scene, position) {
    this.scene = scene;
    this.root = new THREE.Object3D();
    this.root.position.copy(position);
    scene.add(this.root);
    this._spawnPos = position.clone();

    this.model = null;
    this.bones = {};
    this._restFeetY = 0;
    this._tmpVec = new THREE.Vector3();
    this._idlePhase = Math.random() * 10;
    this._facing = Math.random() * Math.PI * 2;

    this.health = HIT_POINTS;
    this.state = "idle"; // idle | approach | telegraph | attack | recover | flinch | defeated
    this._stateTime = 0;
    this._recoverFor = RECOVER_MIN;
    this._attackDidHit = false;
    this.telegraphing = false;
    this.defeated = false;

    const loader = new GLTFLoader();
    loadModelArrayBuffer()
      .then((buf) =>
        loader.parse(
          buf,
          "",
          (gltf) => this._onModelReady(gltf.scene),
          (err) => console.error("Failed to parse enemy model", err)
        )
      )
      .catch((err) => console.error("Failed to fetch enemy model", err));
  }

  _onModelReady(model) {
    model.traverse((child) => {
      if (!child.isMesh) return;
      child.castShadow = false;
      child.receiveShadow = false;
      child.frustumCulled = false;
      if (!child.material) return;
      const name = child.material.name;
      const mat = new THREE.MeshStandardMaterial({ roughness: 0.7, metalness: 0.05 });
      if (name === "MI_HerbalFist_Mask") mat.color.set(0x1a1a1a);
      else if (name === "MI_HerbalFist_Body") mat.color.set(0x2b2b30);
      else {
        mat.color.set(0xff3b3b);
        mat.emissive.set(0xff0000);
        mat.emissiveIntensity = 0.3;
      }
      child.material = mat;
    });
    model.rotation.set(0, Math.PI, 0);
    model.position.set(0, 0, 0);
    this.root.add(model);
    this.model = model;

    for (const [key, name] of Object.entries(BONE_NAMES)) this.bones[key] = model.getObjectByName(name);
    this.bones.upperArmL?.rotation.set(0, ARM_REST_Y, 0);
    this.bones.upperArmR?.rotation.set(0, ARM_REST_Y, 0);
    // Same soft-elbow rest as the player - a thug with ruler-straight arms
    // reads as a shop mannequin too.
    this.bones.lowerArmL?.rotation.set(0, 0, ELBOW_REST);
    this.bones.lowerArmR?.rotation.set(0, 0, ELBOW_REST);

    this.root.updateMatrixWorld(true);
    this._restFeetY = this._lowestFootWorldY() - this.root.position.y;
  }

  _lowestFootWorldY() {
    if (!this.bones.ballL || !this.bones.ballR) return this.root.position.y;
    this.bones.ballL.getWorldPosition(this._tmpVec);
    const leftY = this._tmpVec.y;
    this.bones.ballR.getWorldPosition(this._tmpVec);
    return Math.min(leftY, this._tmpVec.y);
  }

  get position() {
    return this.root.position;
  }

  // Returns true if this hit finished them off. Interrupts whatever they were
  // doing - mid-telegraph or mid-swing - like a real counter-punch.
  takeHit(damage = 1) {
    if (this.state === "defeated") return false;
    this.health -= damage;
    this._stateTime = 0;
    this.telegraphing = false;
    this.state = this.health <= 0 ? "defeated" : "flinch";
    return this.state === "defeated";
  }

  _distTo(p) {
    return Math.hypot(p.x - this.root.position.x, p.z - this.root.position.z);
  }

  _turnToward(p, dt, rate) {
    const target = Math.atan2(p.x - this.root.position.x, p.z - this.root.position.z);
    let delta = target - this._facing;
    delta = Math.atan2(Math.sin(delta), Math.cos(delta));
    this._facing += delta * Math.min(1, dt * rate);
    this.root.rotation.y = this._facing;
  }

  // Returns how much damage this update dealt to the player (0 most frames).
  update(dt, playerPos) {
    if (!this.model) return 0;
    this._stateTime += dt;
    const b = this.bones;

    if (this.state === "defeated") {
      const t = Math.min(1, this._stateTime / DEFEAT_DURATION);
      this.root.rotation.x = -t * (Math.PI / 2);
      this.model.position.y = -this._restFeetY - t * 0.6;
      if (t >= 1) this.defeated = true;
      return 0;
    }

    if (this.state === "flinch") {
      const t = Math.min(1, this._stateTime / FLINCH_DURATION);
      const snap = Math.sin(t * Math.PI);
      if (b.spine) b.spine.rotation.x = -0.3 * snap;
      if (b.upperArmL) b.upperArmL.rotation.set(0, ARM_REST_Y, -0.6 * snap);
      if (b.upperArmR) b.upperArmR.rotation.set(0, ARM_REST_Y, 0.6 * snap);
      if (b.lowerArmL) b.lowerArmL.rotation.z = ELBOW_REST - 1.1 * snap;
      if (b.lowerArmR) b.lowerArmR.rotation.z = ELBOW_REST - 1.1 * snap;
      if (t >= 1) this.state = playerPos && this._distTo(playerPos) < AGGRO_RANGE ? "approach" : "idle";
      this.telegraphing = false;
      this._finishPose();
      return 0;
    }

    let damageDealt = 0;
    const dist = playerPos ? this._distTo(playerPos) : Infinity;
    const fromSpawn = this.root.position.distanceTo(this._spawnPos);

    if (this.state === "idle") {
      this._idlePhase += dt * 1.4;
      const sway = Math.sin(this._idlePhase);
      if (b.upperArmL) b.upperArmL.rotation.set(0, ARM_REST_Y, sway * 0.05);
      if (b.upperArmR) b.upperArmR.rotation.set(0, ARM_REST_Y, -sway * 0.05);
      if (b.lowerArmL) b.lowerArmL.rotation.z = ELBOW_REST + sway * 0.06;
      if (b.lowerArmR) b.lowerArmR.rotation.z = ELBOW_REST - sway * 0.06;
      if (b.spine) b.spine.rotation.x = Math.sin(this._idlePhase * 0.5) * 0.02;
      if (dist < 400) this._turnToward(playerPos, dt, 2);
      if (dist < AGGRO_RANGE) this.state = "approach";
    } else if (this.state === "approach") {
      this._turnToward(playerPos, dt, 3.5);
      if (dist > ATTACK_RANGE && fromSpawn < LEASH_RANGE) {
        this.root.position.x += Math.sin(this._facing) * MOVE_SPEED * dt;
        this.root.position.z += Math.cos(this._facing) * MOVE_SPEED * dt;
        this._idlePhase += dt * 8;
        const stride = Math.sin(this._idlePhase);
        if (b.upperArmL) b.upperArmL.rotation.set(-0.15, ARM_REST_Y, stride * 0.3);
        if (b.upperArmR) b.upperArmR.rotation.set(-0.15, ARM_REST_Y, -stride * 0.3);
        if (b.lowerArmL) b.lowerArmL.rotation.z = -0.75 + stride * 0.25;
        if (b.lowerArmR) b.lowerArmR.rotation.z = -0.75 - stride * 0.25;
      }
      if (dist <= ATTACK_RANGE) {
        this.state = "telegraph";
        this._stateTime = 0;
        this._attackDidHit = false;
      } else if (dist > AGGRO_RANGE * 1.4) {
        this.state = "idle";
      }
    } else if (this.state === "telegraph") {
      this._turnToward(playerPos, dt, 5);
      const t = Math.min(1, this._stateTime / TELEGRAPH_DURATION);
      if (b.upperArmR) b.upperArmR.rotation.set(0, ARM_REST_Y * 0.4, -1.6 * t);
      if (b.lowerArmR) b.lowerArmR.rotation.z = -0.4 - 1.5 * t;
      if (b.lowerArmL) b.lowerArmL.rotation.z = -1.4 * t;
      if (b.spine) b.spine.rotation.x = -0.15 * t;
      if (t >= 1) {
        this.state = "attack";
        this._stateTime = 0;
      }
    } else if (this.state === "attack") {
      this._turnToward(playerPos, dt, 5);
      const t = Math.min(1, this._stateTime / ATTACK_DURATION);
      const through = Math.min(1, t / 0.6);
      if (b.upperArmR) b.upperArmR.rotation.set(0, ARM_REST_Y * 0.2, -1.6 + 2.2 * through);
      if (b.lowerArmR) b.lowerArmR.rotation.z = -1.9 + 1.8 * through;
      if (b.spine) b.spine.rotation.x = -0.15 + 0.35 * through;
      if (!this._attackDidHit && t >= ATTACK_HIT_T) {
        this._attackDidHit = true;
        if (dist <= ATTACK_RANGE + 0.6) damageDealt = ATTACK_DAMAGE;
      }
      if (t >= 1) {
        this.state = "recover";
        this._stateTime = 0;
        this._recoverFor = THREE.MathUtils.randFloat(RECOVER_MIN, RECOVER_MAX);
      }
    } else if (this.state === "recover") {
      this._turnToward(playerPos, dt, 3);
      if (b.upperArmR) b.upperArmR.rotation.set(0, ARM_REST_Y, 0);
      if (b.lowerArmR) b.lowerArmR.rotation.z = ELBOW_REST;
      if (b.lowerArmL) b.lowerArmL.rotation.z = ELBOW_REST;
      if (b.spine) b.spine.rotation.x = 0;
      if (this._stateTime >= this._recoverFor) {
        this.state = dist <= ATTACK_RANGE ? "telegraph" : "approach";
        this._stateTime = 0;
      }
    }

    this.telegraphing = this.state === "telegraph";
    this._finishPose();
    return damageDealt;
  }

  _finishPose() {
    this.model.position.y = -this._restFeetY;
    this.root.updateMatrixWorld(true);
    const dip = this._lowestFootWorldY() - this.root.position.y;
    if (dip < 0) {
      this.model.position.y -= dip;
      this.root.updateMatrixWorld(true);
    }
  }

  dispose() {
    this.scene.remove(this.root);
  }
}
