import { Game } from "./Game.js";

const canvas = document.getElementById("viewport");
const game = new Game(canvas);

const menuScreen = document.getElementById("menu-screen");
const controlsScreen = document.getElementById("controls-screen");
const pauseScreen = document.getElementById("pause-screen");
const gameoverScreen = document.getElementById("gameover-screen");
const hud = document.getElementById("hud");
const tip = document.getElementById("tip");

const statHeight = document.getElementById("stat-height");
const statSpeed = document.getElementById("stat-speed");
const crosshair = document.getElementById("crosshair");
const playerHealthFill = document.getElementById("player-health-fill");
const dangerVignette = document.getElementById("danger-vignette");
const spideyArrow = document.getElementById("spidey-arrow");
const prompt = document.getElementById("prompt");

const crimeStopped = document.getElementById("crime-stopped");
const crimeStatus = document.getElementById("crime-status");
const crimeProgressTrack = document.getElementById("crime-progress-track");
const crimeProgressFill = document.getElementById("crime-progress-fill");
const crimeToast = document.getElementById("crime-toast");
const dodgeToast = document.getElementById("dodge-toast");
const gameoverCrimes = document.getElementById("gameover-crimes");

const btnPlay = document.getElementById("btn-play");
const btnControls = document.getElementById("btn-controls");
const btnControlsBack = document.getElementById("btn-controls-back");
const btnResume = document.getElementById("btn-resume");
const btnQuit = document.getElementById("btn-quit");
const btnRetry = document.getElementById("btn-retry");
const btnGameoverQuit = document.getElementById("btn-gameover-quit");
const btnConnectDualSense = document.getElementById("btn-connect-dualsense");
const dualSenseHidStatus = document.getElementById("dualsense-hid-status");
const btnTestTrigger = document.getElementById("btn-test-trigger");
const btnCycleEffect = document.getElementById("btn-cycle-effect");
const triggerTestStatus = document.getElementById("trigger-test-status");

let lastStoppedCount = 0;
let toastTimer = null;
let dodgeTimer = null;
let tipTimer = null;

const show = (el) => el.classList.remove("hidden");
const hide = (el) => el.classList.add("hidden");

function goToGame() {
  hide(menuScreen);
  hide(controlsScreen);
  hide(pauseScreen);
  hide(gameoverScreen);
  show(hud);
  game.start();
  game.input.requestLock();
}

function backToMenu() {
  hide(pauseScreen);
  hide(gameoverScreen);
  hide(hud);
  hide(crimeToast);
  hide(crimeStatus);
  crimeStopped.textContent = "0";
  lastStoppedCount = 0;
  show(menuScreen);
  game.quitToMenu();
  game.input.exitLock();
}

btnPlay.addEventListener("click", goToGame);
btnControls.addEventListener("click", () => {
  hide(menuScreen);
  show(controlsScreen);
});
btnControlsBack.addEventListener("click", () => {
  hide(controlsScreen);
  show(menuScreen);
});
btnResume.addEventListener("click", () => {
  hide(pauseScreen);
  game.resume();
  game.input.requestLock();
});
btnQuit.addEventListener("click", backToMenu);
btnGameoverQuit.addEventListener("click", backToMenu);
btnRetry.addEventListener("click", () => {
  hide(gameoverScreen);
  hide(dodgeToast);
  crimeStopped.textContent = "0";
  lastStoppedCount = 0;
  game.restart();
  game.input.requestLock();
});

if (!navigator.hid) {
  btnConnectDualSense.disabled = true;
  dualSenseHidStatus.textContent = "WebHID isn't available in this browser (needs Chrome or Edge on desktop).";
} else {
  btnConnectDualSense.addEventListener("click", async () => {
    dualSenseHidStatus.textContent = "Waiting for device selection…";
    const ok = await game.input.connectDualSenseHID();
    const status = game.input.dualSenseHidStatus;
    if (ok) {
      dualSenseHidStatus.textContent =
        `Connected over ${status.transport === "bt" ? "Bluetooth" : "USB"} - you should have felt a quick rumble. ` +
        `Resistance is on R2 while swinging (effect encoding: ${status.effectStyle}).`;
      btnTestTrigger.disabled = false;
      btnCycleEffect.disabled = false;
      triggerTestStatus.textContent =
        "If the trigger doesn't stiffen, use “Try a different effect encoding” and test again - " +
        "controllers and firmware vary in which encoding they honour.";
    } else {
      dualSenseHidStatus.textContent = status.lastError
        ? `Not connected: ${status.lastError}`
        : "No DualSense selected, or the connection was refused.";
    }
  });

  btnTestTrigger.addEventListener("click", async () => {
    triggerTestStatus.textContent = "Hold R2 now - ramping resistance up and back down…";
    await game.input.testTriggerResistance();
    const status = game.input.dualSenseHidStatus;
    triggerTestStatus.textContent = status.connected
      ? `Sweep finished (encoding: ${status.effectStyle}, ${status.sendCount} reports sent). ` +
        "Felt nothing? Try a different encoding."
      : `Connection dropped: ${status.lastError ?? "unknown error"}`;
  });

  btnCycleEffect.addEventListener("click", () => {
    const style = game.input.cycleTriggerEffectStyle();
    triggerTestStatus.textContent = `Effect encoding is now “${style}” - run the test again.`;
  });
}

document.addEventListener("pointerlockchange", () => {
  const locked = document.pointerLockElement === canvas;
  if (!locked && game.mode === "playing") {
    game.pause();
    show(pauseScreen);
  }
});

game.onPauseRequested = () => {
  game.pause();
  game.input.exitLock();
  show(pauseScreen);
};

game.onGameOver = (info) => {
  gameoverCrimes.textContent = info.crimesStopped;
  hide(dodgeToast);
  show(gameoverScreen);
};

function flashToast(text, cls) {
  dodgeToast.textContent = text;
  dodgeToast.classList.toggle("release", cls === "release");
  show(dodgeToast);
  dodgeToast.style.animation = "none";
  void dodgeToast.offsetWidth; // restart the CSS animation on repeat triggers
  dodgeToast.style.animation = "";
  if (dodgeTimer) clearTimeout(dodgeTimer);
  dodgeTimer = setTimeout(() => hide(dodgeToast), 900);
}

game.onPerfectDodge = () => flashToast("PERFECT DODGE", "dodge");
game.onPerfectRelease = () => flashToast("PERFECT RELEASE", "release");

// Clicking Play/Resume already requests pointer lock, but a request can
// silently fail to grant. Clicking the canvas while playing but unlocked
// retries it, so there's always a way back into free-look.
canvas.addEventListener("click", () => {
  if (game.mode === "playing" && !game.input.locked) game.input.requestLock();
});

game.onStatsUpdate = (stats) => {
  statHeight.textContent = stats.height.toFixed(1);
  statSpeed.textContent = stats.speed.toFixed(1);

  const healthPct = Math.max(0, Math.min(100, (stats.health / stats.maxHealth) * 100));
  playerHealthFill.style.width = `${healthPct}%`;
  playerHealthFill.classList.toggle("low", healthPct > 0 && healthPct <= 30);

  crosshair.classList.toggle("aiming", stats.aiming);
  crosshair.classList.toggle("locked", stats.aiming && stats.aimLocked);

  dangerVignette.classList.toggle("active", !!stats.spideySense);
  if (stats.spideySense) {
    spideyArrow.classList.add("active");
    spideyArrow.style.transform = `rotate(${stats.spideySense.relativeYaw}rad)`;
  } else {
    spideyArrow.classList.remove("active");
  }

  // Contextual prompt, so the moves you can only use *right now* are
  // discoverable without opening the controls screen.
  if (stats.onWall) prompt.textContent = "W/S climb · A/D crawl · Space to jump off";
  else if (stats.diving) prompt.textContent = "Diving — hold Left Click to swing out of it";
  else if (stats.state === "swing") prompt.textContent = "Space at the bottom of the arc = perfect release";
  else prompt.textContent = "";

  if (stats.state === "swing" && !tip.dataset.swung) {
    tip.dataset.swung = "1";
    tip.textContent = "Nice! W pumps the swing, Space launches you out of it, S in the air dives.";
    if (tipTimer) clearTimeout(tipTimer);
    tipTimer = setTimeout(() => (tip.style.opacity = "0"), 6000);
  }
};

game.onCrimeUpdate = (info) => {
  crimeStopped.textContent = info.stoppedCount;

  if (info.engaged && info.enemyMaxHealth > 0) {
    show(crimeProgressTrack);
    crimeProgressFill.style.width = `${(info.enemyHealth / info.enemyMaxHealth) * 100}%`;
    show(crimeStatus);
    crimeStatus.textContent = "Press E / Square to punch";
  } else {
    hide(crimeProgressTrack);
    if (info.nearestDist != null && info.nearestDist < 400) {
      show(crimeStatus);
      crimeStatus.textContent = `Crime in progress – ${info.nearestDist.toFixed(0)}m away`;
    } else {
      hide(crimeStatus);
    }
  }

  if (info.stoppedCount > lastStoppedCount) {
    lastStoppedCount = info.stoppedCount;
    crimeToast.classList.remove("hidden");
    crimeToast.style.animation = "none";
    void crimeToast.offsetWidth;
    crimeToast.style.animation = "";
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => hide(crimeToast), 1800);
  }
};
