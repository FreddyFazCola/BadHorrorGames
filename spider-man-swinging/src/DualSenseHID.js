// Real DualSense rumble + adaptive-trigger resistance via WebHID, over both a
// USB cable and an OS-level Bluetooth pairing.
//
// The Gamepad API can only ever buzz the trigger motor - the web platform
// doesn't expose the adaptive trigger's spring tension through it. WebHID lets
// a page write the controller's raw HID output report, the same channel Sony's
// own SDK uses, which does include real resistance effects.
//
// Raw navigator.bluetooth (Web Bluetooth GATT) is a dead end for this: the
// Bluetooth HID-over-GATT service (UUID 0x1812) is on the official Web
// Bluetooth blocklist, a deliberate restriction against pages snooping or
// spoofing keyboard and mouse input. WebHID is the way to reach a wireless
// controller - once a DualSense is paired to the OS, Chrome/Edge expose it to
// navigator.hid exactly like a wired one. The wire *format* differs by
// transport (USB report id 0x02 vs Bluetooth 0x31 with extra framing and a
// trailing CRC32), so connect() detects which and _send() matches it.
//
// Sources: the Bluetooth framing/CRC32 comes from the Linux kernel's own
// DualSense driver (drivers/hid/hid-playstation.c). The common report body
// and effect encodings come from community reverse-engineering
// (github.com/nondebug/dualsense, github.com/flok/pydualsense).
//
// Two encoding families exist: classic modes (Rigid 0x01 / Pulse 0x02) taking
// plain [start, end, force] bytes, and extended variants (0x21/0x25) taking
// packed per-zone bitmask/force fields. The extended ones are fragile - they
// depend on a 10-zone, 3-bits-per-zone packing being exactly right, and
// firmware that doesn't recognise a mode silently ignores the report. The
// classic modes are what virtually every working DualSense tool uses, so
// they're the default; since none of this could be tested against hardware,
// setEffectStyle() switches encodings at runtime and the Controls screen
// exposes a sweep test plus a cycler.

const VENDOR_SONY = 0x054c;
const PRODUCT_DUALSENSE = 0x0ce6;
const PRODUCT_DUALSENSE_EDGE = 0x0df2;

const USB_REPORT_ID = 0x02;
const COMMON_LENGTH = 47;

const BT_REPORT_ID = 0x31;
const BT_TAG = 0x10;
const BT_RESERVED_LENGTH = 24;
const BT_CRC_SEED = 0xa2;

const TRIGGER_OFFSET_RIGHT = 10;
const TRIGGER_OFFSET_LEFT = 21;

const MODE_OFF = 0x00;
const MODE_RIGID = 0x01;
const MODE_PULSE = 0x02;
const MODE_RIGID_EXT = 0x21;
const MODE_WEAPON_EXT = 0x25;

export const EFFECT_STYLES = ["pulse", "rigid", "weapon-ext", "rigid-ext"];

let crcTable = null;
function getCrcTable() {
  if (crcTable) return crcTable;
  crcTable = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crcTable[n] = c >>> 0;
  }
  return crcTable;
}

function crc32(bytes, seed) {
  const table = getCrcTable();
  let crc = seed;
  for (let i = 0; i < bytes.length; i++) crc = table[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  return crc >>> 0;
}

export class DualSenseHID {
  constructor() {
    this.device = null;
    this.connected = false;
    this.transport = "usb";
    this.effectStyle = "pulse";
    this.lastError = null;
    this.sendCount = 0;
    this.availableOutputReports = [];

    // Persistent report body. Rumble and trigger effects share one output
    // report, so they're kept here and re-sent together - rebuilding from
    // zero on every rumble() call wipes whatever trigger effect is active,
    // which is how a web-attach rumble silently cancelled the swing's
    // resistance a frame later.
    this._common = new Uint8Array(COMMON_LENGTH);
    this._common[0] = 0xff; // valid_flag0: both trigger effects + vibration
    this._common[1] = 0xf7; // valid_flag1: rumble/lightbar/player LEDs
    this._btSeq = 0;
    this._lastTension = -1;
  }

  static get supported() {
    return typeof navigator !== "undefined" && !!navigator.hid;
  }

  async connect() {
    if (!DualSenseHID.supported) {
      this.lastError = "WebHID unavailable";
      return false;
    }
    try {
      // Vendor/product only. Pinning usagePage/usage to the Generic Desktop
      // "Game Pad" collection risks an empty picker when a controller
      // enumerates differently (notably over Bluetooth) - and an empty picker
      // looks exactly like "resistance doesn't work".
      const devices = await navigator.hid.requestDevice({
        filters: [
          { vendorId: VENDOR_SONY, productId: PRODUCT_DUALSENSE },
          { vendorId: VENDOR_SONY, productId: PRODUCT_DUALSENSE_EDGE },
          { vendorId: VENDOR_SONY },
        ],
      });
      if (!devices.length) {
        this.lastError = "no device selected";
        return false;
      }
      this.device = devices[0];
      if (!this.device.opened) await this.device.open();

      const outputIds = new Set();
      for (const collection of this.device.collections ?? []) {
        for (const report of collection.outputReports ?? []) outputIds.add(report.reportId);
      }
      this.availableOutputReports = [...outputIds];
      this.transport = outputIds.has(BT_REPORT_ID) && !outputIds.has(USB_REPORT_ID) ? "bt" : "usb";

      this.connected = true;
      this.lastError = null;
      this.device.addEventListener("inputreport", () => {});

      // Prove the link immediately: light resistance plus a short rumble, so
      // "connected" is something you can feel, not just status text.
      this.setTriggerResistance("right", 0.35);
      this.rumble(0.35, 0.5);
      setTimeout(() => this.rumble(0, 0), 180);
      return true;
    } catch (err) {
      this.lastError = String(err?.message ?? err);
      this.connected = false;
      return false;
    }
  }

  disconnect() {
    if (this.device?.opened) {
      this.clearTriggerEffects();
      this.device.close().catch(() => {});
    }
    this.device = null;
    this.connected = false;
  }

  get status() {
    return {
      connected: this.connected,
      transport: this.transport,
      effectStyle: this.effectStyle,
      sendCount: this.sendCount,
      lastError: this.lastError,
      outputReports: this.availableOutputReports,
    };
  }

  setEffectStyle(style) {
    if (EFFECT_STYLES.includes(style)) this.effectStyle = style;
    this._lastTension = -1;
    return this.effectStyle;
  }

  cycleEffectStyle() {
    const i = EFFECT_STYLES.indexOf(this.effectStyle);
    return this.setEffectStyle(EFFECT_STYLES[(i + 1) % EFFECT_STYLES.length]);
  }

  _send() {
    if (!this.connected || !this.device) return;
    try {
      if (this.transport === "bt") {
        // seq_tag, tag, the 47-byte common body, 24 reserved bytes, then a
        // little-endian CRC32 over everything from the report id through the
        // reserved bytes, seeded with 0xA2 - mirrors the kernel's
        // dualsense_send_output_report(). WebHID supplies the report id
        // itself, so this array starts at seq_tag.
        const seqTag = (this._btSeq << 4) & 0xff;
        this._btSeq = (this._btSeq + 1) & 0x0f;

        const frame = new Uint8Array(2 + COMMON_LENGTH + BT_RESERVED_LENGTH + 4);
        frame[0] = seqTag;
        frame[1] = BT_TAG;
        frame.set(this._common, 2);

        const crcInput = new Uint8Array(1 + frame.length - 4);
        crcInput[0] = BT_REPORT_ID;
        crcInput.set(frame.subarray(0, frame.length - 4), 1);
        let crc = crc32(new Uint8Array([BT_CRC_SEED]), 0xffffffff);
        crc = ~crc32(crcInput, crc) >>> 0;
        const at = frame.length - 4;
        frame[at] = crc & 0xff;
        frame[at + 1] = (crc >>> 8) & 0xff;
        frame[at + 2] = (crc >>> 16) & 0xff;
        frame[at + 3] = (crc >>> 24) & 0xff;

        this.device.sendReport(BT_REPORT_ID, frame);
      } else {
        this.device.sendReport(USB_REPORT_ID, this._common);
      }
      this.sendCount++;
    } catch (err) {
      this.lastError = String(err?.message ?? err);
      this.connected = false;
    }
  }

  rumble(weak, strong) {
    if (!this.connected) return;
    const r = this._common;
    r[0] = 0xff;
    r[1] = 0xf7;
    r[2] = Math.round(Math.max(0, Math.min(1, strong)) * 255);
    r[3] = Math.round(Math.max(0, Math.min(1, weak)) * 255);
    this._send();
  }

  _writeTriggerBlock(offset, tension) {
    const r = this._common;
    const t = Math.max(0, Math.min(1, tension));
    // Zero the whole block first, so leftover parameters from another style
    // can't be misread as part of the new effect.
    for (let i = 0; i < 11; i++) r[offset + i] = 0;
    if (t < 0.02) {
      r[offset] = MODE_OFF;
      return;
    }

    const start = Math.round(2 + t * 4);
    const end = Math.min(9, start + 2);
    const force = Math.round(t * 255);
    const small = Math.max(1, Math.round(t * 8));

    switch (this.effectStyle) {
      case "rigid":
        r[offset] = MODE_RIGID;
        r[offset + 1] = start;
        r[offset + 2] = force;
        break;
      case "weapon-ext": {
        r[offset] = MODE_WEAPON_EXT;
        const zones = (1 << start) | (1 << end);
        r[offset + 1] = zones & 0xff;
        r[offset + 2] = (zones >> 8) & 0xff;
        r[offset + 3] = Math.max(0, Math.min(7, small - 1));
        break;
      }
      case "rigid-ext": {
        r[offset] = MODE_RIGID_EXT;
        let zones = 0;
        let packed = 0;
        for (let z = start; z <= 9; z++) {
          zones |= 1 << z;
          packed |= (Math.min(7, small) & 0x7) << (z * 3);
        }
        r[offset + 1] = zones & 0xff;
        r[offset + 2] = (zones >> 8) & 0xff;
        r[offset + 3] = packed & 0xff;
        r[offset + 4] = (packed >>> 8) & 0xff;
        r[offset + 5] = (packed >>> 16) & 0xff;
        r[offset + 6] = (packed >>> 24) & 0xff;
        break;
      }
      case "pulse":
      default:
        // A resistance wall between two positions - the closest match to a
        // PS5 game's "resistance at the end of the pull".
        r[offset] = MODE_PULSE;
        r[offset + 1] = start;
        r[offset + 2] = end;
        r[offset + 3] = force;
        break;
    }
  }

  setTriggerResistance(side, tension) {
    if (!this.connected) return;
    const t = Math.max(0, Math.min(1, tension));
    // Quantize before resending: this is called every frame while swinging,
    // and flooding a Bluetooth link with ~60 near-identical reports a second
    // is a good way to get the ones that matter dropped.
    const q = Math.round(t * 20) / 20;
    if (side === "right") {
      if (q === this._lastTension) return;
      this._lastTension = q;
    }
    this._writeTriggerBlock(side === "left" ? TRIGGER_OFFSET_LEFT : TRIGGER_OFFSET_RIGHT, q);
    this._send();
  }

  clearTriggerEffects() {
    if (!this.connected) return;
    this._writeTriggerBlock(TRIGGER_OFFSET_RIGHT, 0);
    this._writeTriggerBlock(TRIGGER_OFFSET_LEFT, 0);
    this._lastTension = -1;
    this._send();
  }

  async testSweep(durationMs = 2400) {
    if (!this.connected) return false;
    const steps = 24;
    for (let i = 0; i <= steps; i++) {
      const t = i <= steps / 2 ? i / (steps / 2) : 2 - i / (steps / 2);
      this._lastTension = -1; // bypass the change filter for the sweep
      this.setTriggerResistance("right", t);
      await new Promise((r) => setTimeout(r, durationMs / steps));
    }
    this.clearTriggerEffects();
    return true;
  }
}
