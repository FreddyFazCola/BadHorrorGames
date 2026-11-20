// Shared by Player.js and Enemy.js - both use the same source model, so the
// fetch/decode is centralized here. Each caller still runs its own
// GLTFLoader.parse() on the result, giving it an independent scene graph and
// skeleton: characters can't share a skinned mesh's bones and pose separately.
const MODELS_DIR = new URL("../assets/models/", import.meta.url).href;
const MANIFEST_URL = new URL("spiderman.glb.manifest.json", MODELS_DIR).href;

function base64ToArrayBuffer(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

let cachedManifestFetch = null;

// Returns a fresh copy of the model's bytes each call. The manifest and part
// fetches are cached and shared, so a dozen thugs cost one download.
export async function loadModelArrayBuffer() {
  if (!cachedManifestFetch) {
    cachedManifestFetch = fetch(MANIFEST_URL)
      .then((res) => res.json())
      .then((manifest) =>
        Promise.all(manifest.parts.map((n) => fetch(new URL(n, MODELS_DIR).href).then((r) => r.text())))
      )
      .then((parts) => parts.join(""));
  }
  return base64ToArrayBuffer(await cachedManifestFetch);
}
