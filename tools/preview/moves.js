// Player-move showreel (preview video only). Loads build/preview/anim_moves.json
// (tools/lune/export_moves.luau): an R15 block dummy whose part CFrames were
// computed frame by frame with the game's MoveMath + MoveRig, plus the props
// (raw ore chunks, the blaster, the beam). Every frame is a pure function of
// time t (window.renderFrame(t)), so tools/preview/render_anim.mjs can step it.
import * as THREE from "three";

const params = new URLSearchParams(location.search);
const W = Number(params.get("w") || 1280);
const H = Number(params.get("h") || 720);
// clean=1: no captions (the contact sheet adds its own)
if (params.get("clean") === "1") document.body.classList.add("clean");

const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const easeOutBack = (x) => {
  const c1 = 1.7, c3 = c1 + 1;
  return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2);
};
function hexColor(hex) {
  const c = new THREE.Color();
  c.setRGB(parseInt(hex.slice(0, 2), 16) / 255, parseInt(hex.slice(2, 4), 16) / 255, parseInt(hex.slice(4, 6), 16) / 255, THREE.SRGBColorSpace);
  return c;
}

const SHAPE_BLOCK = 0, SHAPE_BALL = 1, SHAPE_CYLINDER = 2, SHAPE_WEDGE = 3;
function wedgeGeometry() {
  const B0 = [-0.5, -0.5, -0.5], B1 = [0.5, -0.5, -0.5], B2 = [0.5, -0.5, 0.5], B3 = [-0.5, -0.5, 0.5];
  const T2 = [0.5, 0.5, 0.5], T3 = [-0.5, 0.5, 0.5];
  const tris = [[B0, B1, B2], [B0, B2, B3], [B3, B2, T2], [B3, T2, T3], [B0, T3, T2], [B0, T2, B1], [B0, B3, T3], [B1, T2, B2]];
  const pos = [];
  for (const t of tris) for (const v of t) pos.push(...v);
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  return g;
}
const geometries = {
  [SHAPE_BLOCK]: new THREE.BoxGeometry(1, 1, 1),
  [SHAPE_BALL]: new THREE.SphereGeometry(0.5, 20, 14),
  [SHAPE_CYLINDER]: new THREE.CylinderGeometry(0.5, 0.5, 1, 24).rotateZ(-Math.PI / 2),
  [SHAPE_WEDGE]: wedgeGeometry(),
};
const matCache = new Map();
function material(hex, mat, transparency) {
  const key = `${hex}|${mat}|${transparency}`;
  if (matCache.has(key)) return matCache.get(key);
  let m;
  if (mat === "Neon") m = new THREE.MeshBasicMaterial({ color: hexColor(hex).multiplyScalar(2.2) });
  else if (mat === "Metal" || mat === "Foil" || mat === "DiamondPlate") m = new THREE.MeshStandardMaterial({ color: hexColor(hex), roughness: 0.35, metalness: 0.55 });
  else if (mat === "Glass") m = new THREE.MeshStandardMaterial({ color: hexColor(hex), roughness: 0.05, transparent: true, opacity: 0.45 });
  else m = new THREE.MeshStandardMaterial({ color: hexColor(hex), roughness: 0.72, metalness: 0.04 });
  if (transparency > 0.01 && mat !== "Glass") {
    m.transparent = true;
    m.opacity = Math.max(0.05, 1 - transparency);
    m.depthWrite = false;
  }
  matCache.set(key, m);
  return m;
}
function matrixOf(cf, out = new THREE.Matrix4()) {
  const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = cf;
  return out.set(r00, r01, r02, x, r10, r11, r12, y, r20, r21, r22, z, 0, 0, 0, 1);
}

async function main() {
  await document.fonts.load('40px "Luckiest Guy"');
  const data = await fetch("/scenes/anim_moves.json").then((r) => r.json());
  const fps = data.fps;

  const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
  renderer.setSize(W, H);
  renderer.setPixelRatio(1);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  const stage = document.getElementById("stage");
  stage.style.width = W + "px";
  stage.style.height = H + "px";
  stage.prepend(renderer.domElement);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(40, W / H, 0.1, 600);

  // sky: a warm forge-evening gradient
  scene.add(
    new THREE.Mesh(
      new THREE.SphereGeometry(300, 32, 16),
      new THREE.ShaderMaterial({
        side: THREE.BackSide,
        depthWrite: false,
        vertexShader: `varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
        fragmentShader: `varying vec3 vP; void main(){ float h = vP.y;
          vec3 top = vec3(0.32, 0.55, 0.86); vec3 mid = vec3(0.98, 0.78, 0.55); vec3 low = vec3(0.55, 0.42, 0.36);
          vec3 c = mix(mid, top, smoothstep(0.02, 0.5, h)); c = mix(c, low, smoothstep(0.0, -0.25, h));
          gl_FragColor = vec4(c, 1.0); }`,
      }),
    ),
  );
  scene.fog = new THREE.Fog(0xe9b98e, 60, 200);

  // the ground: grass, a round stone platform with a forge-orange rim
  const grass = new THREE.Mesh(new THREE.CircleGeometry(160, 48), new THREE.MeshStandardMaterial({ color: hexColor("6fae4f"), roughness: 0.95 }));
  grass.rotation.x = -Math.PI / 2;
  grass.position.y = -0.02;
  grass.receiveShadow = true;
  scene.add(grass);
  const plate = new THREE.Mesh(new THREE.CylinderGeometry(7.5, 7.8, 0.4, 48), new THREE.MeshStandardMaterial({ color: hexColor("b9a896"), roughness: 0.9 }));
  plate.position.y = -0.2;
  plate.receiveShadow = true;
  scene.add(plate);
  const rim = new THREE.Mesh(new THREE.TorusGeometry(7.55, 0.12, 8, 64), new THREE.MeshBasicMaterial({ color: hexColor("ff9a3c") }));
  rim.rotation.x = Math.PI / 2;
  rim.position.y = 0.01;
  scene.add(rim);
  // tiles on the plate
  {
    const tileMat = new THREE.MeshStandardMaterial({ color: hexColor("a89785"), roughness: 0.92 });
    for (let r = 2; r <= 6; r += 2) {
      const ring = new THREE.Mesh(new THREE.RingGeometry(r - 0.04, r + 0.04, 64), tileMat);
      ring.rotation.x = -Math.PI / 2;
      ring.position.y = 0.005;
      scene.add(ring);
    }
  }
  // a few rocks and crystals far back (forge mood, not in the way)
  {
    const rockMat = new THREE.MeshStandardMaterial({ color: hexColor("8a7a6c"), roughness: 0.95, flatShading: true });
    const crystal = new THREE.MeshBasicMaterial({ color: hexColor("ffb35c") });
    const spots = [[-22, -30, 4], [26, -34, 5], [-34, 10, 3.5], [34, 6, 4.5], [8, 38, 4], [-14, 36, 3]];
    for (const [x, z, s] of spots) {
      const rock = new THREE.Mesh(new THREE.DodecahedronGeometry(s, 0), rockMat);
      rock.position.set(x, s * 0.45, z);
      rock.rotation.set(x, z, 0);
      rock.castShadow = true;
      scene.add(rock);
      const c = new THREE.Mesh(new THREE.OctahedronGeometry(s * 0.35, 0), crystal);
      c.position.set(x + s * 0.4, s * 1.05, z);
      c.scale.y = 1.8;
      scene.add(c);
    }
  }

  scene.add(new THREE.HemisphereLight(0xfff1dd, 0x6d5a48, 1.25));
  const sun = new THREE.DirectionalLight(0xfff0d8, 2.3);
  sun.position.set(14, 26, -10);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  sun.shadow.camera.left = -12;
  sun.shadow.camera.right = 12;
  sun.shadow.camera.top = 12;
  sun.shadow.camera.bottom = -12;
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 0.02;
  scene.add(sun);
  const fill = new THREE.DirectionalLight(0xbcd4ff, 0.55);
  fill.position.set(-12, 8, 14);
  scene.add(fill);

  // groups: one Object3D per body part / prop, its parts as child meshes
  const groups = data.groups.map((g) => {
    const obj = new THREE.Group();
    obj.matrixAutoUpdate = false;
    const inner = new THREE.Group();
    inner.matrixAutoUpdate = false;
    obj.add(inner);
    for (const p of g.parts) {
      const [shape, sx, sy, sz, cf, hex, mat, transparency] = p;
      if (transparency > 0.98 || Math.min(sx, sy, sz) < 1e-4) continue;
      const mesh = new THREE.Mesh(geometries[shape] || geometries[SHAPE_BLOCK], material(hex, mat, transparency));
      mesh.matrixAutoUpdate = false;
      mesh.matrix.copy(matrixOf(cf)).multiply(new THREE.Matrix4().makeScale(sx, sy, sz));
      mesh.castShadow = mat !== "Neon";
      mesh.receiveShadow = mat !== "Neon";
      inner.add(mesh);
    }
    scene.add(obj);
    return { name: g.name, obj, inner };
  });

  const dots = document.getElementById("dots");
  data.segments.forEach(() => dots.appendChild(document.createElement("div")));
  const titleEl = document.getElementById("title");
  const subEl = document.getElementById("subtitle");

  const m4 = new THREE.Matrix4();
  window.renderFrame = (t) => {
    const index = clamp(Math.round(t * fps), 0, data.frames.length - 1);
    const row = data.frames[index];
    groups.forEach((g, i) => {
      const cf = row[i];
      if (!cf) {
        g.obj.visible = false;
        return;
      }
      g.obj.visible = true;
      g.obj.matrix.copy(matrixOf(cf, m4));
      // the beam: a unit block stretched to its length
      if (cf.length > 12) g.inner.matrix.makeScale(1, 1, cf[12]);
      g.obj.matrixWorldNeedsUpdate = true;
    });
    // the segment: camera and caption
    let seg = data.segments[0];
    let segIndex = 0;
    data.segments.forEach((s, i) => {
      if (t >= s.start) {
        seg = s;
        segIndex = i;
      }
    });
    const local = t - seg.start;
    const length = seg.stop - seg.start;
    const [px, py, pz] = seg.camera.position;
    // a slow drift around the look-at point keeps the shot alive
    const [tx, , tz] = seg.camera.target;
    const drift = (local / length - 0.5) * 0.12;
    const cos = Math.cos(drift), sin = Math.sin(drift);
    const dx = px - tx, dz = pz - tz;
    camera.position.set(tx + dx * cos - dz * sin, py, tz + dx * sin + dz * cos);
    camera.fov = seg.camera.fov;
    camera.updateProjectionMatrix();
    camera.lookAt(new THREE.Vector3(...seg.camera.target));
    titleEl.textContent = seg.title;
    subEl.textContent = seg.subtitle;
    const pop = clamp(local / 0.35);
    const out = clamp((length - local) / 0.2);
    const s = 0.6 + 0.4 * easeOutBack(pop);
    titleEl.style.transform = `scale(${s.toFixed(3)})`;
    titleEl.style.transformOrigin = "left bottom";
    titleEl.style.opacity = String(Math.min(clamp(pop * 2), out));
    subEl.style.opacity = String(Math.min(clamp((local - 0.12) / 0.25), out));
    subEl.style.transform = `translateY(${((1 - clamp((local - 0.12) / 0.25)) * 0.8).toFixed(3)}vw)`;
    [...dots.children].forEach((d, i) => (d.className = i === segIndex ? "on" : i < segIndex ? "done" : ""));
    renderer.render(scene, camera);
  };
  window.__duration = data.duration;
  window.renderFrame(0);
  window.__ready = true;
}

main().catch((e) => {
  window.__error = String(e && e.stack ? e.stack : e);
});
