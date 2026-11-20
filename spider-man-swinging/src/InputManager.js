import { DualSenseHID } from "./DualSenseHID.js";

const GAMEPAD_DEADZONE = 0.15;
const GAMEPAD_LOOK_SPEED = 2.6;
const TRIGGER_PRESS = 0.25;

// Standard Gamepad API mapping, as Chrome/Edge expose a DualSense: axes 0/1 =
// left stick, 2/3 = right stick; buttons 0 = Cross, 1 = Circle (dodge),
// 2 = Square, 4 = L1, 5 = R1, 6 = L2 (analog, aim), 7 = R2 (analog),
// 9 = Options, 10 = L3. Shared by every standard-profile gamepad. The
// adaptive triggers aren't reachable through this API at all - that's what
// DualSenseHID.js is for.
const BTN_CROSS = 0;
const BTN_CIRCLE = 1;
const BTN_SQUARE = 2;
const BTN_L1 = 4;
const BTN_R1 = 5;
const BTN_L2 = 6;
const BTN_R2 = 7;
const BTN_OPTIONS = 9;
const BTN_L3 = 10;

export class InputManager {
  constructor(domElement) {
    this.dom = domElement;
    this.keys = new Set();
    this.yaw = 0;
    this.pitch = 0.15;
    this.locked = false;

    this._rawMouseDown = false;
    this._rawAimDown = false;
    this._justPressedJump = false;
    this._justPressedPause = false;
    this._justPressedPunch = false;
    this._justPressedZip = false;
    this._justPressedDodge = false;

    this.dualSenseHid = new DualSenseHID();

    this.gamepadConnected = false;
    this.gamepadIsDualSense = false;
    this._gpIndex = null;
    this._gpMoveX = 0;
    this._gpMoveY = 0;
    this._gpWebValue = 0;
    this._gpAimValue = 0;
    this._gpSprintDown = false;
    this._gpJumpWasDown = false;
    this._gpPauseWasDown = false;
    this._gpPunchWasDown = false;
    this._gpZipWasDown = false;
    this._gpDodgeWasDown = false;
    this._gpActuator = null;
    this._gpEffects = null;
    this._triggerRumbleCooldown = 0;

    window.addEventListener("keydown", (e) => {
      this.keys.add(e.code);
      if (e.code === "Space") this._justPressedJump = true;
      if (e.code === "KeyE") this._justPressedPunch = true;
      if (e.code === "KeyQ") this._justPressedZip = true;
      if (e.code === "KeyC") this._justPressedDodge = true;
    });
    window.addEventListener("keyup", (e) => this.keys.delete(e.code));

    // Pointer lock is nice-to-have (hides the cursor, lets you spin forever)
    // but some embedding contexts refuse it, so nothing below is gated on it.
    domElement.addEventListener("mousedown", (e) => {
      if (e.button === 0) this._rawMouseDown = true;
      if (e.button === 2) this._rawAimDown = true;
    });
    window.addEventListener("mouseup", (e) => {
      if (e.button === 0) this._rawMouseDown = false;
      if (e.button === 2) this._rawAimDown = false;
    });
    domElement.addEventListener("contextmenu", (e) => e.preventDefault());
    // Losing focus mid-hold would otherwise leave a button latched forever.
    window.addEventListener("blur", () => {
      this._rawMouseDown = false;
      this._rawAimDown = false;
      this.keys.clear();
    });

    document.addEventListener("pointerlockchange", () => {
      this.locked = document.pointerLockElement === domElement;
    });
    document.addEventListener("pointerlockerror", () => {
      this.locked = false;
    });

    window.addEventListener("mousemove", (e) => {
      const sensitivity = 0.0022;
      this.yaw -= e.movementX * sensitivity;
      this.pitch -= e.movementY * sensitivity;
      const limit = Math.PI / 2 - 0.05;
      this.pitch = Math.max(-limit, Math.min(limit, this.pitch));
    });

    window.addEventListener("gamepadconnected", (e) => {
      if (!e.gamepad) return;
      this._gpIndex = e.gamepad.index;
      this.gamepadConnected = true;
      this.gamepadIsDualSense = /dualsense|054c/i.test(e.gamepad.id);
    });
    window.addEventListener("gamepaddisconnected", (e) => {
      if (!e.gamepad || e.gamepad.index !== this._gpIndex) return;
      this.gamepadConnected = false;
      this.gamepadIsDualSense = false;
      this._gpIndex = null;
      this._gpActuator = null;
      this._gpEffects = null;
      this._gpWebValue = 0;
      this._gpAimValue = 0;
      this._gpMoveX = 0;
      this._gpMoveY = 0;
      this._gpSprintDown = false;
      this._gpZipWasDown = false;
      this._gpDodgeWasDown = false;
    });
  }

  isDown(code) {
    return this.keys.has(code);
  }

  // Web-shoot held: left mouse OR R2.
  //
  // A getter deliberately. This used to be a plain field that only
  // pollGamepad() ever assigned - and pollGamepad() returns immediately when
  // no gamepad is connected, so on mouse and keyboard it sat at `false`
  // forever and the web never fired at all. Deriving it on read means the
  // mouse path can't depend on gamepad code having run.
  get mouseDown() {
    return this._rawMouseDown || this._gpWebValue > TRIGGER_PRESS;
  }

  isAimDown() {
    return this._rawAimDown || this._gpAimValue > 0.35;
  }

  movementVector() {
    let x = 0;
    let z = 0;
    if (this.isDown("KeyW")) z += 1;
    if (this.isDown("KeyS")) z -= 1;
    if (this.isDown("KeyD")) x += 1;
    if (this.isDown("KeyA")) x -= 1;
    x += this._gpMoveX;
    z -= this._gpMoveY; // stick Y is positive downward; forward is -Y
    const len = Math.hypot(x, z);
    if (len > 1) {
      x /= len;
      z /= len;
    }
    return { x, z };
  }

  isSprintDown() {
    return this.isDown("ShiftLeft") || this.isDown("ShiftRight") || this._gpSprintDown;
  }

  consumeJumpPress() {
    const v = this._justPressedJump;
    this._justPressedJump = false;
    return v;
  }

  consumePausePress() {
    const v = this._justPressedPause;
    this._justPressedPause = false;
    return v;
  }

  consumePunchPress() {
    const v = this._justPressedPunch;
    this._justPressedPunch = false;
    return v;
  }

  consumeZipPress() {
    const v = this._justPressedZip;
    this._justPressedZip = false;
    return v;
  }

  consumeDodgePress() {
    const v = this._justPressedDodge;
    this._justPressedDodge = false;
    return v;
  }

  pollGamepad(dt) {
    if (this._gpIndex === null) return;
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    const gp = pads[this._gpIndex];
    if (!gp) return;

    const dz = (v) => (Math.abs(v) < GAMEPAD_DEADZONE ? 0 : v);
    this._gpMoveX = dz(gp.axes[0] ?? 0);
    this._gpMoveY = dz(gp.axes[1] ?? 0);
    const lookX = dz(gp.axes[2] ?? 0);
    const lookY = dz(gp.axes[3] ?? 0);
    if (lookX !== 0 || lookY !== 0) {
      this.yaw -= lookX * GAMEPAD_LOOK_SPEED * dt;
      this.pitch -= lookY * GAMEPAD_LOOK_SPEED * dt;
      const limit = Math.PI / 2 - 0.05;
      this.pitch = Math.max(-limit, Math.min(limit, this.pitch));
    }

    this._gpWebValue = gp.buttons[BTN_R2]?.value ?? 0;
    this._gpAimValue = gp.buttons[BTN_L2]?.value ?? 0;
    this._gpSprintDown = !!gp.buttons[BTN_L1]?.pressed || !!gp.buttons[BTN_L3]?.pressed;

    const edge = (index, wasKey) => {
      const down = !!gp.buttons[index]?.pressed;
      const fired = down && !this[wasKey];
      this[wasKey] = down;
      return fired;
    };
    if (edge(BTN_CROSS, "_gpJumpWasDown")) this._justPressedJump = true;
    if (edge(BTN_SQUARE, "_gpPunchWasDown")) this._justPressedPunch = true;
    if (edge(BTN_R1, "_gpZipWasDown")) this._justPressedZip = true;
    if (edge(BTN_CIRCLE, "_gpDodgeWasDown")) this._justPressedDodge = true;
    if (edge(BTN_OPTIONS, "_gpPauseWasDown")) this._justPressedPause = true;

    this._gpActuator = gp.vibrationActuator || null;
    this._gpEffects = this._gpActuator?.effects || null;
    if (this._triggerRumbleCooldown > 0) this._triggerRumbleCooldown -= dt;
  }

  async connectDualSenseHID() {
    return this.dualSenseHid.connect();
  }

  get dualSenseHidConnected() {
    return this.dualSenseHid.connected;
  }

  get dualSenseHidStatus() {
    return this.dualSenseHid.status;
  }

  testTriggerResistance() {
    return this.dualSenseHid.testSweep();
  }

  cycleTriggerEffectStyle() {
    return this.dualSenseHid.cycleEffectStyle();
  }

  rumble({ duration = 120, weak = 0.3, strong = 0.5 } = {}) {
    if (this.dualSenseHid.connected) {
      this.dualSenseHid.rumble(weak, strong);
      return;
    }
    if (!this._gpActuator || typeof this._gpActuator.playEffect !== "function") return;
    try {
      this._gpActuator.playEffect("dual-rumble", { duration, weakMagnitude: weak, strongMagnitude: strong });
    } catch {
      // Unsupported params/hardware - cosmetic only, so just skip it.
    }
  }

  setTriggerRumble(rightTrigger) {
    if (this.dualSenseHid.connected) {
      this.dualSenseHid.setTriggerResistance("right", rightTrigger);
      return;
    }
    if (!this.gamepadIsDualSense) return;
    if (!this._gpActuator || typeof this._gpActuator.playEffect !== "function") return;
    if (this._gpEffects && !this._gpEffects.includes("trigger-rumble")) return;
    if (rightTrigger <= 0.02) return;
    if (this._triggerRumbleCooldown > 0) return;
    const duration = 120;
    this._triggerRumbleCooldown = duration / 1000 / 2;
    try {
      this._gpActuator.playEffect("trigger-rumble", { duration, leftTrigger: 0, rightTrigger });
    } catch {
      // Unsupported browser/controller combo.
    }
  }

  requestLock() {
    try {
      const result = this.dom.requestPointerLock();
      if (result && typeof result.catch === "function") result.catch(() => (this.locked = false));
    } catch {
      this.locked = false;
    }
  }

  exitLock() {
    if (this.locked) document.exitPointerLock();
  }
}
