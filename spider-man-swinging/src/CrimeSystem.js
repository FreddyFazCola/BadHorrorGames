import * as THREE from "three";
import { Enemy } from "./Enemy.js";

const MAX_ACTIVE = 3;
const SPAWN_INTERVAL_MIN = 9;
const SPAWN_INTERVAL_MAX = 18;
const FIRST_SPAWN_DELAY = 3.5;
const SPAWN_MIN_DIST = 35;
const SPAWN_MAX_DIST = 150;
const PUNCH_RANGE = 2.6;
const BEAM_HEIGHT = 14;

function buildMarker() {
  const group = new THREE.Group();

  const beamGeo = new THREE.CylinderGeometry(0.25, 0.05, BEAM_HEIGHT, 10, 1, true);
  beamGeo.translate(0, BEAM_HEIGHT / 2, 0);
  const beam = new THREE.Mesh(
    beamGeo,
    new THREE.MeshBasicMaterial({
      color: 0xff2a2a,
      transparent: true,
      opacity: 0.55,
      side: THREE.DoubleSide,
      depthWrite: false,
    })
  );
  group.add(beam);

  const ringGeo = new THREE.RingGeometry(1.6, 2.2, 24);
  ringGeo.rotateX(-Math.PI / 2);
  const ring = new THREE.Mesh(
    ringGeo,
    new THREE.MeshBasicMaterial({
      color: 0xff2a2a,
      transparent: true,
      opacity: 0.7,
      side: THREE.DoubleSide,
      depthWrite: false,
    })
  );
  ring.position.y = 0.05;
  group.add(ring);

  const light = new THREE.PointLight(0xff2222, 3, 30, 2);
  light.position.y = 2;
  group.add(light);

  return { group, beam, ring, light };
}

// Spawns "crimes" - a red beacon plus a thug (Enemy.js) standing under it.
// The beacon is how you spot one while swinging; the thug is what you fight.
// Thugs fight back, so update() also sums the damage they land each frame and
// surfaces the nearest telegraphing attack as "spidey sense".
export class CrimeSystem {
  constructor(scene, city) {
    this.scene = scene;
    this.city = city;
    this.crimes = [];
    this.stoppedCount = 0;
    this._nextSpawnIn = FIRST_SPAWN_DELAY;
    this.onCrimeStopped = null;
    this.onPunchLanded = null;
  }

  update(dt, playerPos) {
    this._nextSpawnIn -= dt;
    if (this._nextSpawnIn <= 0 && this.crimes.length < MAX_ACTIVE) this._spawn(playerPos);

    let nearest = null;
    let nearestDist = Infinity;
    let playerDamage = 0;
    let spideySense = null;

    for (const crime of this.crimes) {
      crime.time += dt;
      crime.ring.rotation.z += dt * 0.6;
      crime.ring.scale.setScalar(1 + Math.sin(crime.time * 3) * 0.08);
      crime.beam.material.opacity = 0.4 + Math.sin(crime.time * 5) * 0.2;
      crime.light.intensity = 2.2 + Math.sin(crime.time * 7) * 1.4;
      playerDamage += crime.enemy.update(dt, playerPos);

      const d = crime.group.position.distanceTo(playerPos);
      if (d < nearestDist) {
        nearestDist = d;
        nearest = crime;
      }
      if (crime.enemy.telegraphing) {
        const enemyDist = crime.enemy.position.distanceTo(playerPos);
        if (!spideySense || enemyDist < spideySense.dist) {
          spideySense = {
            dist: enemyDist,
            dirYaw: Math.atan2(crime.enemy.position.x - playerPos.x, crime.enemy.position.z - playerPos.z),
          };
        }
      }
      if (crime.enemy.defeated) this._stop(crime);
    }

    return {
      nearestDist: nearest ? nearestDist : null,
      engaged: nearest ? nearestDist < PUNCH_RANGE + 3 : false,
      enemyHealth: nearest ? nearest.enemy.health : 0,
      enemyMaxHealth: nearest ? nearest.enemyMaxHealth : 0,
      activeCount: this.crimes.length,
      stoppedCount: this.stoppedCount,
      playerDamage,
      spideySense,
    };
  }

  tryPunch(playerPosition, damage = 1) {
    let best = null;
    let bestDist = PUNCH_RANGE;
    for (const crime of this.crimes) {
      if (crime.enemy.state === "defeated") continue;
      const d = crime.enemy.position.distanceTo(playerPosition);
      if (d <= bestDist) {
        bestDist = d;
        best = crime;
      }
    }
    if (!best) return { hit: false, defeated: false };
    const defeated = best.enemy.takeHit(damage);
    this.onPunchLanded?.({ defeated });
    return { hit: true, defeated };
  }

  // Is any thug mid-wind-up within `radius`? Drives the perfect dodge.
  isDangerNear(position, radius) {
    return this.crimes.some((c) => c.enemy.telegraphing && c.enemy.position.distanceTo(position) <= radius);
  }

  // Soft lock-on for aim/web-zip: the nearest live thug within a forgiving
  // ~10 degree cone, rather than a literal raycast against their mesh.
  findAimTarget(origin, dir, maxDist) {
    let best = null;
    let bestDot = 0.985;
    for (const crime of this.crimes) {
      if (crime.enemy.state === "defeated" || !crime.enemy.model) continue;
      const toEnemy = crime.enemy.position.clone().sub(origin);
      const dist = toEnemy.length();
      if (dist > maxDist || dist < 0.5) continue;
      const dot = toEnemy.normalize().dot(dir);
      if (dot > bestDot) {
        bestDot = dot;
        best = crime.enemy;
      }
    }
    return best;
  }

  _spawn(playerPos) {
    const spot = this.city.randomSpawnPoint(playerPos.x, playerPos.z, SPAWN_MIN_DIST, SPAWN_MAX_DIST);
    this._nextSpawnIn = THREE.MathUtils.randFloat(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX);
    if (!spot) return;

    const { group, beam, ring, light } = buildMarker();
    group.position.set(spot.x, spot.y, spot.z);
    this.scene.add(group);
    const enemy = new Enemy(this.scene, group.position);
    this.crimes.push({ group, beam, ring, light, enemy, enemyMaxHealth: enemy.health, time: Math.random() * 10 });
  }

  reset() {
    for (const crime of this.crimes) this._disposeCrime(crime);
    this.crimes = [];
    this.stoppedCount = 0;
    this._nextSpawnIn = FIRST_SPAWN_DELAY;
  }

  _disposeCrime(crime) {
    this.scene.remove(crime.group);
    crime.beam.geometry.dispose();
    crime.beam.material.dispose();
    crime.ring.geometry.dispose();
    crime.ring.material.dispose();
    crime.enemy.dispose();
  }

  _stop(crime) {
    this._disposeCrime(crime);
    this.crimes = this.crimes.filter((c) => c !== crime);
    this.stoppedCount++;
    this.onCrimeStopped?.(crime);
  }
}
