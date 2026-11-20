import * as THREE from "three";

// Procedural city, streamed around the player in fixed cells so it can run
// forever in any direction without ever building the whole world. Every
// cell's contents are derived from a hash of its grid coordinates, so a cell
// rebuilt after you wander away and come back is identical - no popping into
// a different skyline than the one you left.

const CELL = 84; // metres per grid cell (one building + its share of street)
const VIEW_CELLS = 6; // cells kept loaded in each direction from the player
// Street width decides whether the city is swingable at all. At a 42m grid
// with 9m margins the avenues were ~18m across - narrower than a single swing
// arc, so every web attach ended in a facade regardless of how good the rope
// physics was. ~40m canyons give a 30m rope somewhere to go.
const BUILDING_MARGIN = 22;
const MIN_HEIGHT = 18;
const MAX_HEIGHT = 135;

function hash2(ix, iz, salt = 0) {
  let h = ix * 374761393 + iz * 668265263 + salt * 1442695040888963407;
  h = (h ^ (h >>> 13)) >>> 0;
  h = Math.imul(h, 1274126177) >>> 0;
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

// Tiled facade: rows of small windows, most dark, some lit warm. One canvas
// shared by every building, with per-building UV repeat making them differ.
function makeFacadeTexture() {
  const size = 128;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "#0b0d18";
  ctx.fillRect(0, 0, size, size);

  const cols = 8;
  const rows = 10;
  const cw = size / cols;
  const ch = size / rows;
  const lit = ["#ffd9a0", "#ffe9c4", "#cfe0ff", "#fff3d0"];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const on = hash2(c + 1, r + 1, 7) > 0.62;
      ctx.fillStyle = on ? lit[Math.floor(hash2(c, r, 13) * lit.length)] : "#141826";
      ctx.fillRect(c * cw + 3, r * ch + 3, cw - 6, ch - 6.6);
    }
  }
  const tex = new THREE.CanvasTexture(canvas);
  tex.wrapS = THREE.RepeatWrapping;
  tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function makeSkyTexture() {
  const canvas = document.createElement("canvas");
  canvas.width = 8;
  canvas.height = 256;
  const ctx = canvas.getContext("2d");
  const grad = ctx.createLinearGradient(0, 0, 0, 256);
  grad.addColorStop(0.0, "#05060f");
  grad.addColorStop(0.45, "#160a18");
  grad.addColorStop(0.72, "#5b1a12");
  grad.addColorStop(0.88, "#c8481a");
  grad.addColorStop(1.0, "#e86a22");
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, 8, 256);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.mapping = THREE.EquirectangularReflectionMapping;
  return tex;
}

export function createCity(scene) {
  const facade = makeFacadeTexture();
  scene.background = makeSkyTexture();
  scene.fog = new THREE.Fog(0x3b1a26, 140, 900);

  scene.add(new THREE.HemisphereLight(0x8a77b8, 0x241a2c, 1.15));
  const key = new THREE.DirectionalLight(0xffc08a, 1.15);
  key.position.set(-120, 90, -60);
  scene.add(key);
  const rim = new THREE.DirectionalLight(0x7f9dff, 0.5);
  rim.position.set(90, 60, 110);
  scene.add(rim);

  const groundMat = new THREE.MeshStandardMaterial({ color: 0x4a4256, roughness: 0.95, metalness: 0 });
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(2400, 2400), groundMat);
  ground.rotation.x = -Math.PI / 2;
  scene.add(ground);

  const buildingGeo = new THREE.BoxGeometry(1, 1, 1);
  const cells = new Map(); // "ix,iz" -> { mesh, box }
  const colliders = []; // raycast targets for web-shooting and the camera

  const cellKey = (ix, iz) => `${ix},${iz}`;

  function buildCell(ix, iz) {
    if (ix === 0 && iz === 0) return null; // plaza at spawn
    if (hash2(ix, iz, 3) < 0.12) return null; // occasional open lot

    const height = MIN_HEIGHT + Math.pow(hash2(ix, iz, 1), 2.2) * (MAX_HEIGHT - MIN_HEIGHT);
    const footprint = CELL - BUILDING_MARGIN * 2;
    const sizeX = footprint * (0.7 + hash2(ix, iz, 4) * 0.3);
    const sizeZ = footprint * (0.7 + hash2(ix, iz, 5) * 0.3);
    const cx = ix * CELL + (hash2(ix, iz, 6) - 0.5) * 3;
    const cz = iz * CELL + (hash2(ix, iz, 8) - 0.5) * 3;

    // The same texture drives diffuse and emissive. Windows are the only
    // bright pixels in it, so as an emissive map they glow on their own -
    // which is the whole look of a night skyline. Lit purely by lamps, every
    // building reads as a black silhouette.
    const tex = facade.clone();
    tex.needsUpdate = true;
    tex.repeat.set(Math.max(1, Math.round(sizeX / 7)), Math.max(2, Math.round(height / 7)));
    const tint = 0.8 + hash2(ix, iz, 9) * 0.5;
    const mat = new THREE.MeshStandardMaterial({
      color: new THREE.Color(0x3d4a6b).multiplyScalar(tint),
      roughness: 0.85,
      metalness: 0.05,
      map: tex,
      emissive: new THREE.Color(0xffffff),
      emissiveMap: tex,
      emissiveIntensity: 0.85,
    });

    const mesh = new THREE.Mesh(buildingGeo, mat);
    mesh.scale.set(sizeX, height, sizeZ);
    mesh.position.set(cx, height / 2, cz);
    scene.add(mesh);
    colliders.push(mesh);

    return {
      mesh,
      box: {
        minX: cx - sizeX / 2,
        maxX: cx + sizeX / 2,
        minZ: cz - sizeZ / 2,
        maxZ: cz + sizeZ / 2,
        height,
      },
    };
  }

  function removeCell(k) {
    const cell = cells.get(k);
    if (!cell?.mesh) return;
    scene.remove(cell.mesh);
    cell.mesh.material.map?.dispose();
    cell.mesh.material.dispose();
    const i = colliders.indexOf(cell.mesh);
    if (i !== -1) colliders.splice(i, 1);
    cells.delete(k);
  }

  // Iterates the boxes in the 3x3 cell neighbourhood of a point.
  function* nearbyBoxes(x, z) {
    const ix = Math.round(x / CELL);
    const iz = Math.round(z / CELL);
    for (let dx = -1; dx <= 1; dx++) {
      for (let dz = -1; dz <= 1; dz++) {
        const box = cells.get(cellKey(ix + dx, iz + dz))?.box;
        if (box) yield box;
      }
    }
  }

  const city = {
    colliders,
    cellSize: CELL,

    update(px, pz) {
      const cx = Math.round(px / CELL);
      const cz = Math.round(pz / CELL);
      ground.position.set(cx * CELL, 0, cz * CELL);

      for (let ix = cx - VIEW_CELLS; ix <= cx + VIEW_CELLS; ix++) {
        for (let iz = cz - VIEW_CELLS; iz <= cz + VIEW_CELLS; iz++) {
          const k = cellKey(ix, iz);
          if (cells.has(k)) continue;
          // Empty cells are remembered too, so a plaza isn't re-rolled and
          // re-tested every frame you stand next to it.
          cells.set(k, buildCell(ix, iz) ?? { mesh: null, box: null });
        }
      }
      for (const k of [...cells.keys()]) {
        const [ix, iz] = k.split(",").map(Number);
        if (Math.abs(ix - cx) > VIEW_CELLS + 1 || Math.abs(iz - cz) > VIEW_CELLS + 1) {
          if (cells.get(k)?.mesh) removeCell(k);
          else cells.delete(k);
        }
      }
    },

    groundHeightAt(x, z) {
      const box = cells.get(cellKey(Math.round(x / CELL), Math.round(z / CELL)))?.box;
      if (!box) return 0;
      return x >= box.minX && x <= box.maxX && z >= box.minZ && z <= box.maxZ ? box.height : 0;
    },

    // Nearest climbable wall surface within `reach` of a point, or null.
    // Returns the outward face normal, the point on the face, and the
    // building's roof height so the climber knows where the wall ends.
    //
    // Only the four vertical faces count: the top is a roof you walk on, and
    // a point above the roofline has no wall beside it at all.
    wallProbe(x, y, z, reach) {
      let best = null;
      for (const box of nearbyBoxes(x, z)) {
        if (y > box.height - 0.2 || y < 0) continue;
        // Closest point on the footprint rectangle, and which face it is on.
        const faces = [
          { d: Math.abs(x - box.minX), nx: -1, nz: 0, px: box.minX, pz: z, inSpan: z >= box.minZ && z <= box.maxZ },
          { d: Math.abs(x - box.maxX), nx: 1, nz: 0, px: box.maxX, pz: z, inSpan: z >= box.minZ && z <= box.maxZ },
          { d: Math.abs(z - box.minZ), nx: 0, nz: -1, px: x, pz: box.minZ, inSpan: x >= box.minX && x <= box.maxX },
          { d: Math.abs(z - box.maxZ), nx: 0, nz: 1, px: x, pz: box.maxZ, inSpan: x >= box.minX && x <= box.maxX },
        ].filter((f) => f.inSpan);
        if (!faces.length) continue;
        const face = faces.sort((a, b) => a.d - b.d)[0];
        if (face.d > reach) continue;
        if (!best || face.d < best.distance) {
          best = {
            distance: face.d,
            normal: { x: face.nx, z: face.nz },
            point: { x: face.px, y, z: face.pz },
            top: box.height,
          };
        }
      }
      return best;
    },

    // Push a point back out of any building footprint it has ended up inside.
    // `refY` is the height the mover was at *before* this step: buildings
    // shorter than that are roofs underfoot, not walls in front, and must not
    // shove the player sideways off their own rooftop.
    //
    // Returns the displacement applied, or null. The caller needs it to cancel
    // the velocity heading into the wall - repositioning alone leaves the
    // mover grinding along the facade at full speed, still "moving" as far as
    // the physics is concerned while going nowhere.
    resolveHorizontalCollision(position, radius, refY) {
      let pushX = 0;
      let pushZ = 0;
      for (const box of nearbyBoxes(position.x, position.z)) {
        if (box.height <= refY + 0.05) continue;
        const minX = box.minX - radius;
        const maxX = box.maxX + radius;
        const minZ = box.minZ - radius;
        const maxZ = box.maxZ + radius;
        if (position.x < minX || position.x > maxX || position.z < minZ || position.z > maxZ) continue;

        const out = [
          { d: position.x - minX, axis: "x", to: minX },
          { d: maxX - position.x, axis: "x", to: maxX },
          { d: position.z - minZ, axis: "z", to: minZ },
          { d: maxZ - position.z, axis: "z", to: maxZ },
        ].sort((a, b) => a.d - b.d)[0];
        const before = position[out.axis];
        position[out.axis] = out.to;
        if (out.axis === "x") pushX += position.x - before;
        else pushZ += position.z - before;
      }
      return pushX !== 0 || pushZ !== 0 ? { x: pushX, z: pushZ } : null;
    },

    randomSpawnPoint(px, pz, minDist, maxDist) {
      for (let attempt = 0; attempt < 24; attempt++) {
        const angle = Math.random() * Math.PI * 2;
        const dist = minDist + Math.random() * (maxDist - minDist);
        const x = px + Math.cos(angle) * dist;
        const z = pz + Math.sin(angle) * dist;
        const box = cells.get(cellKey(Math.round(x / CELL), Math.round(z / CELL)))?.box;
        if (box && attempt < 18) {
          return { x: (box.minX + box.maxX) / 2, y: box.height, z: (box.minZ + box.maxZ) / 2 };
        }
        if (!box) return { x, y: 0, z };
      }
      return null;
    },
  };

  city.update(0, 0);
  return city;
}
