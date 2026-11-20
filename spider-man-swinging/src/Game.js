import * as THREE from "three";
import { createCity } from "./City.js";
import { Player } from "./Player.js";
import { PlayerController } from "./PlayerController.js";
import { InputManager } from "./InputManager.js";
import { CrimeSystem } from "./CrimeSystem.js";

const SPAWN_POSITION = new THREE.Vector3(0, 1, 18);

export class Game {
  constructor(canvas) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(62, window.innerWidth / window.innerHeight, 0.1, 1200);
    this.camera.position.set(0, 30, 60);
    this.camera.lookAt(0, 10, 0);

    this.city = createCity(this.scene);
    this.player = new Player(this.scene);
    this.input = new InputManager(canvas);
    this.crimes = new CrimeSystem(this.scene, this.city);
    this.crimes.onCrimeStopped = () => this.input.rumble({ duration: 220, weak: 0.7, strong: 0.9 });

    this.controller = new PlayerController(this.scene, this.player, this.city, this.input, this.crimes);
    this.controller.onDeath = () => {
      this.mode = "dead";
      this.input.exitLock();
      this.onGameOver?.({ crimesStopped: this.crimes.stoppedCount });
    };
    this.controller.onPerfectDodge = () => this.onPerfectDodge?.();
    this.controller.onPerfectRelease = () => this.onPerfectRelease?.();
    this.controller.reset(SPAWN_POSITION);

    this.mode = "menu"; // menu | playing | paused | dead
    this.clock = new THREE.Clock();
    this._menuAngle = 0;
    this._spideySenseWasActive = false;

    this.onStatsUpdate = null;
    this.onCrimeUpdate = null;
    this.onPauseRequested = null;
    this.onGameOver = null;
    this.onPerfectDodge = null;
    this.onPerfectRelease = null;

    window.addEventListener("resize", () => this._onResize());
    this._onResize();

    this._animate = this._animate.bind(this);
    requestAnimationFrame(this._animate);
  }

  _onResize() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    this.renderer.setSize(w, h);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  start() {
    this.mode = "playing";
  }

  pause() {
    if (this.mode === "playing") this.mode = "paused";
  }

  resume() {
    if (this.mode === "paused") this.mode = "playing";
  }

  quitToMenu() {
    this.mode = "menu";
    this.controller.reset(SPAWN_POSITION);
    this.crimes.reset();
    this._spideySenseWasActive = false;
  }

  // Straight back into a fresh run: full health at the spawn point, crimes
  // cleared (otherwise you'd rematerialize next to whoever floored you).
  restart() {
    this.controller.reset(SPAWN_POSITION);
    this.crimes.reset();
    this._spideySenseWasActive = false;
    this.mode = "playing";
  }

  _animate() {
    requestAnimationFrame(this._animate);
    // The controller runs a fixed-step accumulator internally, so a long
    // frame is clamped there; this only stops it seeing an absurd delta
    // after a backgrounded tab.
    const dt = Math.min(this.clock.getDelta(), 0.25);

    if (this.mode === "dead") {
      this.controller.update(dt, this.camera);
      this.controller.updateCamera(this.camera, dt);
      this.renderer.render(this.scene, this.camera);
      return;
    }

    if (this.mode === "playing") {
      this.city.update(this.controller.position.x, this.controller.position.z);
      this.controller.update(dt, this.camera);
      this.controller.updateCamera(this.camera, dt);

      if (this.input.consumePausePress() && this.onPauseRequested) this.onPauseRequested();

      const crimeInfo = this.crimes.update(dt, this.controller.position);
      if (crimeInfo.playerDamage > 0) this.controller.takeDamage(crimeInfo.playerDamage);

      // A warning pulse the instant a thug starts winding up - the haptic
      // half of spidey sense. Edge-triggered, so it's one tap per telegraph
      // rather than a buzz for the whole wind-up.
      const senseActive = !!crimeInfo.spideySense;
      if (senseActive && !this._spideySenseWasActive) {
        this.input.rumble({ duration: 70, weak: 0.25, strong: 0.15 });
      }
      this._spideySenseWasActive = senseActive;

      if (this.onStatsUpdate) {
        let spideySense = null;
        if (crimeInfo.spideySense) {
          let rel = crimeInfo.spideySense.dirYaw - this.input.yaw;
          rel = Math.atan2(Math.sin(rel), Math.cos(rel));
          spideySense = { relativeYaw: rel, dist: crimeInfo.spideySense.dist };
        }
        this.onStatsUpdate({
          height: Math.max(0, this.controller.position.y),
          speed: this.controller.velocity.length(),
          state: this.controller.state,
          health: this.controller.health,
          maxHealth: this.controller.maxHealth,
          aiming: this.controller.aiming,
          aimLocked: !!this.controller.aimTarget?.locked,
          onWall: this.controller.onWall,
          diving: this.controller.diving,
          spideySense,
        });
      }

      this.onCrimeUpdate?.(crimeInfo);
    } else if (this.mode === "menu") {
      this._menuAngle += dt * 0.06;
      const radius = 130;
      this.camera.position.set(Math.sin(this._menuAngle) * radius, 46, Math.cos(this._menuAngle) * radius);
      this.camera.lookAt(0, 20, 0);
    }
    // "paused": render the last frame as-is, no updates.

    this.renderer.render(this.scene, this.camera);
  }
}
