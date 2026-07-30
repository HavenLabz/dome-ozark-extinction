/**
 * DOME: OZARK EXTINCTION — Playable Vertical Slice
 * Three.js + Rapier.js first-person prehistoric survival hunter
 */
import * as THREE from 'three';
import RAPIER from '@dimforge/rapier3d-compat';
import creaturesData from './data/creatures.json';
import weaponsData from './data/weapons.json';

// ── Minimal PointerLock FPS controls (no examples/ dependency) ──
class SimplePointerLock {
  constructor(camera, domElement) {
    this.camera = camera;
    this.domElement = domElement;
    this.isLocked = false;
    this.euler = new THREE.Euler(0, 0, 0, 'YXZ');
    this.PI_2 = Math.PI / 2;
    this.object = new THREE.Object3D();
    this.object.add(camera);
    camera.position.set(0, 0, 0);

    this._onMouseMove = (e) => {
      if (!this.isLocked) return;
      const movementX = e.movementX || 0;
      const movementY = e.movementY || 0;
      this.euler.setFromQuaternion(this.object.quaternion);
      this.euler.y -= movementX * 0.002;
      this.euler.x -= movementY * 0.002;
      this.euler.x = Math.max(-this.PI_2, Math.min(this.PI_2, this.euler.x));
      this.object.quaternion.setFromEuler(this.euler);
    };
    this._onLockChange = () => {
      this.isLocked = document.pointerLockElement === this.domElement;
      if (this.isLocked) this.dispatch('lock');
      else this.dispatch('unlock');
    };
    this._listeners = { lock: [], unlock: [] };
    document.addEventListener('mousemove', this._onMouseMove);
    document.addEventListener('pointerlockchange', this._onLockChange);
  }
  getObject() { return this.object; }
  lock() { this.domElement.requestPointerLock(); }
  unlock() { document.exitPointerLock(); }
  addEventListener(type, fn) { (this._listeners[type] || []).push(fn); }
  dispatch(type) { (this._listeners[type] || []).forEach(fn => fn()); }
}

let scene, camera, renderer, controls, world, clock;
let playerBody;
let dinosaurs = [];
let footprints = [];
let fires = [];
let trophies = [];

const KEYS = {};
let isLocked = false;
let currentWeapon = 'ar15';
let ammo = { ar15: 30, m1911: 7 };
let reserveAmmo = { ar15: 120, m1911: 28 };
let isReloading = false;
let lastShot = 0;
let isAiming = false;
let mouseDown = false;
let messageTimer = 0;
let gameTime = 6 * 3600;
let weather = 'clear';

const player = {
  health: 100, hunger: 100, thirst: 100, temp: 22,
  speed: 6.5, sprintMult: 1.7, crouchMult: 0.45
};

const WORLD_SIZE = 360;
const GRAVITY = -18;

async function init() {
  await RAPIER.init();
  clock = new THREE.Clock();
  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x87a0b8);
  scene.fog = new THREE.FogExp2(0x87a0b8, 0.009);

  camera = new THREE.PerspectiveCamera(75, innerWidth / innerHeight, 0.1, 500);
  camera.position.set(0, 2, 0);

  renderer = new THREE.WebGLRenderer({
    canvas: document.getElementById('game-canvas'),
    antialias: true,
    powerPreference: 'high-performance'
  });
  renderer.setSize(innerWidth, innerHeight);
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;

  world = new RAPIER.World({ x: 0, y: GRAVITY, z: 0 });

  setupLighting();
  createTerrain();
  createPlayer();
  scatterTrees(140);
  scatterRocks(45);
  createLakes();
  spawnDinosaurs();

  controls = new SimplePointerLock(camera, document.body);
  scene.add(controls.getObject());

  setupInput();
  document.getElementById('start-btn').addEventListener('click', () => {
    document.getElementById('start-screen').style.display = 'none';
    controls.lock();
  });

  window.addEventListener('resize', () => {
    camera.aspect = innerWidth / innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(innerWidth, innerHeight);
  });

  animate();
}

function setupLighting() {
  scene.add(new THREE.AmbientLight(0x6a7a8a, 0.42));
  const sun = new THREE.DirectionalLight(0xfff0d0, 1.35);
  sun.position.set(80, 120, 40);
  sun.castShadow = true;
  sun.shadow.mapSize.set(1536, 1536);
  sun.shadow.camera.near = 5;
  sun.shadow.camera.far = 280;
  sun.shadow.camera.left = -100;
  sun.shadow.camera.right = 100;
  sun.shadow.camera.top = 100;
  sun.shadow.camera.bottom = -100;
  sun.shadow.bias = -0.0004;
  scene.add(sun);
  scene.userData.sun = sun;
  scene.add(new THREE.HemisphereLight(0x88aacc, 0x334422, 0.32));
}

function sampleHeight(x, z) {
  let y = Math.sin(x * 0.03) * Math.cos(z * 0.025) * 4;
  y += Math.sin(x * 0.08 + 1.2) * Math.sin(z * 0.07) * 1.8;
  y += Math.sin(x * 0.15) * 0.55;
  const dist = Math.hypot(x, z);
  if (dist < 35) y *= dist / 35;
  return y;
}

function createTerrain() {
  const segs = 96;
  const geo = new THREE.PlaneGeometry(WORLD_SIZE, WORLD_SIZE, segs, segs);
  geo.rotateX(-Math.PI / 2);
  const pos = geo.attributes.position;
  const colors = [];
  const c = new THREE.Color();
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i), z = pos.getZ(i);
    const y = sampleHeight(x, z);
    pos.setY(i, y);
    if (y < 0.4) c.setHex(0x3a5a2a);
    else if (y < 2.5) c.setHex(0x4a6b3a);
    else if (y < 5) c.setHex(0x5a7a4a);
    else c.setHex(0x6a8a5a);
    colors.push(c.r, c.g, c.b);
  }
  geo.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  geo.computeVertexNormals();

  const mesh = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({
    vertexColors: true, roughness: 0.92, metalness: 0.04
  }));
  mesh.receiveShadow = true;
  scene.add(mesh);

  const vertices = new Float32Array(pos.array);
  const indices = new Uint32Array(geo.index.array);
  const body = world.createRigidBody(RAPIER.RigidBodyDesc.fixed());
  world.createCollider(RAPIER.ColliderDesc.trimesh(vertices, indices), body);

  const ground = world.createRigidBody(RAPIER.RigidBodyDesc.fixed().setTranslation(0, -3, 0));
  world.createCollider(RAPIER.ColliderDesc.cuboid(WORLD_SIZE, 1, WORLD_SIZE), ground);
}

function createLakes() {
  [[55, -35, 16], [-65, 45, 13], [15, 75, 11]].forEach(([x, z, r]) => {
    const geo = new THREE.CircleGeometry(r, 28);
    geo.rotateX(-Math.PI / 2);
    const mat = new THREE.MeshStandardMaterial({
      color: 0x2a5a7a, transparent: true, opacity: 0.72, roughness: 0.12, metalness: 0.35
    });
    const m = new THREE.Mesh(geo, mat);
    m.position.set(x, 0.12, z);
    scene.add(m);
  });
}

function scatterTrees(n) {
  const trunkGeo = new THREE.CylinderGeometry(0.22, 0.32, 3.8, 6);
  const trunkMat = new THREE.MeshStandardMaterial({ color: 0x3a2a1a, roughness: 0.95 });
  const leafGeo = new THREE.ConeGeometry(2.0, 4.8, 7);
  const leafMat = new THREE.MeshStandardMaterial({ color: 0x2a5a2a, roughness: 0.85 });
  for (let i = 0; i < n; i++) {
    const x = (Math.random() - 0.5) * WORLD_SIZE * 0.88;
    const z = (Math.random() - 0.5) * WORLD_SIZE * 0.88;
    if (Math.hypot(x, z) < 22) continue;
    const g = new THREE.Group();
    const trunk = new THREE.Mesh(trunkGeo, trunkMat);
    trunk.position.y = 1.9; trunk.castShadow = true; g.add(trunk);
    const leaves = new THREE.Mesh(leafGeo, leafMat);
    leaves.position.y = 5.2; leaves.castShadow = true; g.add(leaves);
    const y = sampleHeight(x, z);
    g.position.set(x, y, z);
    g.rotation.y = Math.random() * 6.28;
    g.scale.setScalar(0.65 + Math.random() * 0.55);
    scene.add(g);
    const body = world.createRigidBody(RAPIER.RigidBodyDesc.fixed().setTranslation(x, y + 1.9, z));
    world.createCollider(RAPIER.ColliderDesc.cylinder(1.9, 0.35), body);
  }
}

function scatterRocks(n) {
  const geo = new THREE.DodecahedronGeometry(1, 0);
  const mat = new THREE.MeshStandardMaterial({ color: 0x5a5a4a, roughness: 0.9 });
  for (let i = 0; i < n; i++) {
    const x = (Math.random() - 0.5) * WORLD_SIZE * 0.82;
    const z = (Math.random() - 0.5) * WORLD_SIZE * 0.82;
    const m = new THREE.Mesh(geo, mat);
    const s = 0.35 + Math.random() * 1.1;
    m.scale.setScalar(s);
    m.position.set(x, sampleHeight(x, z) + s * 0.35, z);
    m.rotation.set(Math.random(), Math.random(), Math.random());
    m.castShadow = true; m.receiveShadow = true;
    scene.add(m);
  }
}

function createPlayer() {
  const desc = RAPIER.RigidBodyDesc.dynamic()
    .setTranslation(0, 4, 0)
    .setAdditionalMass(80)
    .lockRotations();
  playerBody = world.createRigidBody(desc);
  world.createCollider(
    RAPIER.ColliderDesc.capsule(0.45, 0.32).setFriction(0.85).setRestitution(0),
    playerBody
  );
}

function createDinoMesh(def) {
  const g = new THREE.Group();
  const [sx, sy, sz] = def.scale;
  const mat = new THREE.MeshStandardMaterial({ color: def.color, roughness: 0.82, metalness: 0.04 });
  const body = new THREE.Mesh(new THREE.BoxGeometry(sx * 0.65, sy * 0.55, sz * 0.5), mat);
  body.position.y = sy * 0.42; body.castShadow = true; g.add(body);
  const head = new THREE.Mesh(new THREE.BoxGeometry(sx * 0.32, sy * 0.32, sz * 0.28), mat);
  head.position.set(0, sy * 0.52, sz * 0.32); head.castShadow = true; g.add(head);
  const legGeo = new THREE.BoxGeometry(sx * 0.13, sy * 0.45, sz * 0.1);
  [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([lx, lz]) => {
    const leg = new THREE.Mesh(legGeo, mat);
    leg.position.set(lx * sx * 0.22, sy * 0.22, lz * sz * 0.16);
    leg.castShadow = true; g.add(leg);
  });
  const tail = new THREE.Mesh(new THREE.BoxGeometry(sx * 0.1, sy * 0.1, sz * 0.45), mat);
  tail.position.set(0, sy * 0.38, -sz * 0.38); tail.castShadow = true; g.add(tail);

  if (def.id === 'triceratops') {
    const hornMat = new THREE.MeshStandardMaterial({ color: 0xe8e0d0 });
    [-0.22, 0.22].forEach(ox => {
      const horn = new THREE.Mesh(new THREE.ConeGeometry(0.07, 0.55, 5), hornMat);
      horn.position.set(ox, sy * 0.68, sz * 0.4);
      horn.rotation.x = -0.55; g.add(horn);
    });
    const frill = new THREE.Mesh(new THREE.BoxGeometry(sx * 0.85, sy * 0.45, 0.07), mat);
    frill.position.set(0, sy * 0.62, sz * 0.22); g.add(frill);
  }
  if (def.id === 'stegosaurus') {
    for (let i = 0; i < 6; i++) {
      const plate = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.45 + Math.random() * 0.25, 0.35), mat);
      plate.position.set(0, sy * 0.72, -sz * 0.22 + i * 0.22); g.add(plate);
    }
  }
  const eyeMat = new THREE.MeshBasicMaterial({ color: 0xff2200 });
  [-1, 1].forEach(s => {
    const eye = new THREE.Mesh(new THREE.SphereGeometry(0.05, 5, 5), eyeMat);
    eye.position.set(s * sx * 0.16, sy * 0.58, sz * 0.45); g.add(eye);
  });
  return g;
}

function randomPos(minR, maxR) {
  const a = Math.random() * Math.PI * 2;
  const r = minR + Math.random() * (maxR - minR);
  return { x: Math.cos(a) * r, z: Math.sin(a) * r };
}

function spawnOne(def, pos) {
  const mesh = createDinoMesh(def);
  const y = sampleHeight(pos.x, pos.z) + 0.4;
  mesh.position.set(pos.x, y, pos.z);
  scene.add(mesh);
  const body = world.createRigidBody(
    RAPIER.RigidBodyDesc.dynamic()
      .setTranslation(pos.x, y + 1, pos.z)
      .setAdditionalMass(def.health * 0.7)
      .lockRotations()
  );
  world.createCollider(
    RAPIER.ColliderDesc.cuboid(def.scale[0] * 0.32, def.scale[1] * 0.38, def.scale[2] * 0.28).setFriction(0.55),
    body
  );
  dinosaurs.push({
    def, mesh, body,
    health: def.health, maxHealth: def.health,
    state: 'idle', stateTimer: 2 + Math.random() * 4,
    wanderTarget: null, lastFootprint: 0, dead: false,
    territory: new THREE.Vector3(pos.x, 0, pos.z)
  });
}

function spawnDinosaurs() {
  const herbs = creaturesData.herbivores;
  const preds = creaturesData.predators;
  for (let i = 0; i < 5; i++) spawnOne(herbs[i % herbs.length], randomPos(50, 150));
  const raptor = preds.find(p => p.id === 'raptor');
  const pack = randomPos(70, 130);
  for (let i = 0; i < 3; i++) {
    spawnOne(raptor, {
      x: pack.x + (Math.random() - 0.5) * 18,
      z: pack.z + (Math.random() - 0.5) * 18
    });
  }
  spawnOne(preds.find(p => p.id === 'carnotaurus'), randomPos(90, 160));
}

function updateDinoAI(dino, dt, playerPos) {
  if (dino.dead) return;
  dino.stateTimer -= dt;
  const t = dino.body.translation();
  const dist = Math.hypot(t.x - playerPos.x, t.z - playerPos.z);

  if (dino.def.type === 'predator') {
    if (dist < 32 && dino.state !== 'attack') { dino.state = 'investigate'; dino.stateTimer = 3; }
    if (dist < 16 && dino.def.aggression > 0.5) { dino.state = 'attack'; }
    if (dist > 48 && dino.state === 'attack') { dino.state = 'return'; dino.stateTimer = 5; }
  } else if (dist < 22 && dino.def.fear > 0.3) {
    dino.state = 'flee'; dino.stateTimer = 4;
  }

  if (dino.stateTimer <= 0 && dino.state !== 'attack') {
    const r = Math.random();
    dino.state = r < 0.3 ? 'idle' : r < 0.65 ? 'explore' : r < 0.8 ? 'feed' : 'sleep';
    dino.stateTimer = 3 + Math.random() * 5;
  }

  let dir = new THREE.Vector3();
  let speed = 0;
  switch (dino.state) {
    case 'idle': case 'sleep': break;
    case 'explore': case 'feed':
      if (!dino.wanderTarget || dino.stateTimer < 1) {
        dino.wanderTarget = new THREE.Vector3(
          t.x + (Math.random() - 0.5) * 36, 0, t.z + (Math.random() - 0.5) * 36
        );
      }
      dir.subVectors(dino.wanderTarget, new THREE.Vector3(t.x, 0, t.z)).normalize();
      speed = dino.def.speed * 0.4;
      break;
    case 'flee':
      dir.set(t.x - playerPos.x, 0, t.z - playerPos.z).normalize();
      speed = dino.def.speed * 1.1;
      break;
    case 'investigate': case 'attack':
      dir.set(playerPos.x - t.x, 0, playerPos.z - t.z).normalize();
      speed = dino.def.speed * (dino.state === 'attack' ? 1.15 : 0.65);
      if (dino.state === 'attack' && dist < 3.2) {
        player.health = Math.max(0, player.health - (dino.def.damage || 18) * dt * 0.55);
        if (Math.random() < 0.015) showMessage('You are under attack!');
      }
      break;
    case 'return':
      dir.subVectors(dino.territory, new THREE.Vector3(t.x, 0, t.z)).normalize();
      speed = dino.def.speed * 0.5;
      break;
  }

  const lv = dino.body.linvel();
  if (speed > 0) {
    dino.body.setLinvel({ x: dir.x * speed, y: lv.y, z: dir.z * speed }, true);
    if (dir.lengthSq() > 0.01) dino.mesh.rotation.y = Math.atan2(dir.x, dir.z);
  } else {
    dino.body.setLinvel({ x: 0, y: lv.y, z: 0 }, true);
  }

  const nt = dino.body.translation();
  dino.mesh.position.set(nt.x, sampleHeight(nt.x, nt.z), nt.z);

  dino.lastFootprint -= dt;
  if (dino.lastFootprint <= 0 && speed > 1) {
    dino.lastFootprint = 0.55;
    const fgeo = new THREE.CircleGeometry(dino.def.size * 0.35, 6);
    fgeo.rotateX(-Math.PI / 2);
    const fmat = new THREE.MeshBasicMaterial({ color: 0x2a1a0a, transparent: true, opacity: 0.4 });
    const fm = new THREE.Mesh(fgeo, fmat);
    fm.position.set(nt.x, sampleHeight(nt.x, nt.z) + 0.04, nt.z);
    scene.add(fm);
    footprints.push({ mesh: fm, life: 40 });
    if (footprints.length > 70) {
      const old = footprints.shift();
      scene.remove(old.mesh);
    }
  }

  if (dino.health <= 0 && !dino.dead) {
    dino.dead = true;
    dino.mesh.rotation.z = Math.PI / 2;
    dino.mesh.position.y = sampleHeight(nt.x, nt.z) + 0.25;
    world.removeRigidBody(dino.body);
    showMessage(`${dino.def.name} slain — press E near carcass for trophy`);
  }
}

function fireWeapon() {
  const w = weaponsData[currentWeapon];
  if (isReloading || ammo[currentWeapon] <= 0) {
    if (ammo[currentWeapon] <= 0) showMessage('Empty — press R to reload');
    return;
  }
  const now = performance.now() / 1000;
  if (now - lastShot < w.fireRate) return;
  lastShot = now;
  ammo[currentWeapon]--;

  const origin = new THREE.Vector3();
  const dir = new THREE.Vector3();
  camera.getWorldPosition(origin);
  camera.getWorldDirection(dir);
  const spread = w.spread * (isAiming ? 0.28 : 1.15);
  dir.x += (Math.random() - 0.5) * spread;
  dir.y += (Math.random() - 0.5) * spread;
  dir.z += (Math.random() - 0.5) * spread;
  dir.normalize();

  const points = [
    origin.clone().addScaledVector(dir, 1.4),
    origin.clone().addScaledVector(dir, 35)
  ];
  const tracer = new THREE.Line(
    new THREE.BufferGeometry().setFromPoints(points),
    new THREE.LineBasicMaterial({ color: 0xffcc66, transparent: true, opacity: 0.65 })
  );
  scene.add(tracer);
  setTimeout(() => scene.remove(tracer), 70);

  let hit = null, hitDist = w.range;
  for (const d of dinosaurs) {
    if (d.dead) continue;
    const to = new THREE.Vector3().subVectors(d.mesh.position, origin);
    const proj = to.dot(dir);
    if (proj < 0 || proj > hitDist) continue;
    const closest = origin.clone().addScaledVector(dir, proj);
    if (closest.distanceTo(d.mesh.position) < d.def.size * 1.15) {
      hit = d; hitDist = proj;
    }
  }
  if (hit) {
    hit.health -= w.damage;
    const flash = new THREE.Mesh(
      new THREE.SphereGeometry(0.25, 5, 5),
      new THREE.MeshBasicMaterial({ color: 0x880000 })
    );
    flash.position.copy(hit.mesh.position); flash.position.y += 1;
    scene.add(flash);
    setTimeout(() => scene.remove(flash), 120);
    hit.state = hit.def.type === 'predator' ? 'attack' : 'flee';
    hit.stateTimer = 6;
    showMessage(`Hit ${hit.def.name} (${Math.max(0, Math.floor(hit.health))} HP)`);
  }
  camera.rotation.x += (Math.random() * 0.015 + 0.008) * w.recoil * (isAiming ? 0.35 : 1);
}

function reload() {
  if (isReloading) return;
  const w = weaponsData[currentWeapon];
  if (ammo[currentWeapon] >= w.magazine) return;
  if (reserveAmmo[currentWeapon] <= 0) { showMessage('No reserve ammo'); return; }
  isReloading = true;
  showMessage('Reloading...');
  setTimeout(() => {
    const need = w.magazine - ammo[currentWeapon];
    const take = Math.min(need, reserveAmmo[currentWeapon]);
    ammo[currentWeapon] += take;
    reserveAmmo[currentWeapon] -= take;
    isReloading = false;
    showMessage('Reloaded');
  }, w.reloadTime * 1000);
}

function tryCollectTrophy() {
  const p = controls.getObject().position;
  for (const d of dinosaurs) {
    if (!d.dead) continue;
    if (d.mesh.position.distanceTo(p) < 4.2) {
      trophies.push({ name: d.def.name, rarity: d.def.rarity, value: d.def.trophyValue });
      scene.remove(d.mesh);
      dinosaurs = dinosaurs.filter(x => x !== d);
      showMessage(`Trophy: ${d.def.name} (${d.def.rarity}) +${d.def.trophyValue}`);
      player.hunger = Math.min(100, player.hunger + 12);
      return;
    }
  }
  showMessage('No trophy nearby');
}

function deployFlare() {
  const p = controls.getObject().position;
  const flare = new THREE.Mesh(
    new THREE.SphereGeometry(0.14, 8, 8),
    new THREE.MeshBasicMaterial({ color: 0xff4400 })
  );
  flare.position.set(p.x, p.y + 0.8, p.z);
  scene.add(flare);
  const light = new THREE.PointLight(0xff4400, 2.8, 28);
  light.position.copy(flare.position);
  scene.add(light);
  showMessage('Extraction flare deployed — hold position');
  setTimeout(() => {
    scene.remove(flare); scene.remove(light);
    showMessage(trophies.length ? `Extraction OK — ${trophies.length} trophies secured` : 'No trophies to extract');
  }, 7000);
}

function buildFire() {
  const p = controls.getObject().position;
  const dir = new THREE.Vector3();
  camera.getWorldDirection(dir);
  const place = p.clone().addScaledVector(dir, 2.4);
  place.y = sampleHeight(place.x, place.z);
  const g = new THREE.Group();
  const logMat = new THREE.MeshStandardMaterial({ color: 0x2a1a0a });
  for (let i = 0; i < 4; i++) {
    const log = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.09, 0.75, 5), logMat);
    log.rotation.z = Math.PI / 2;
    log.rotation.y = (i / 4) * Math.PI;
    log.position.y = 0.08; g.add(log);
  }
  const flame = new THREE.Mesh(
    new THREE.ConeGeometry(0.28, 0.75, 6),
    new THREE.MeshBasicMaterial({ color: 0xff6600, transparent: true, opacity: 0.85 })
  );
  flame.position.y = 0.48; g.add(flame);
  const light = new THREE.PointLight(0xff8833, 1.4, 16);
  light.position.y = 0.7; g.add(light);
  g.position.copy(place);
  scene.add(g);
  fires.push({ group: g, light, flame, life: 100 });
  showMessage('Campfire lit — warmth & predator deterrence');
  player.temp = Math.min(28, player.temp + 4);
}

function updateDayNight(dt) {
  gameTime += dt * 55;
  if (gameTime >= 86400) gameTime -= 86400;
  const hours = (gameTime / 3600) % 24;
  const sun = scene.userData.sun;
  const angle = ((hours - 6) / 24) * Math.PI * 2;
  sun.position.set(Math.cos(angle) * 95, Math.sin(angle) * 75 + 18, 35);
  sun.intensity = Math.max(0.08, Math.sin(angle) * 1.45);
  const night = hours < 5.5 || hours > 20;
  const dusk = (hours > 17 && hours < 20) || (hours > 5 && hours < 7);
  if (night) {
    scene.background.setHex(0x0a1020);
    scene.fog.color.setHex(0x0a1020);
    scene.fog.density = 0.013;
  } else if (dusk) {
    scene.background.setHex(0x4a3a2a);
    scene.fog.color.setHex(0x4a3a2a);
    scene.fog.density = 0.01;
  } else {
    scene.background.setHex(0x87a0b8);
    scene.fog.color.setHex(0x87a0b8);
    scene.fog.density = 0.009;
  }
  if (Math.random() < 0.00025) {
    weather = Math.random() < 0.55 ? 'rain' : Math.random() < 0.35 ? 'storm' : 'clear';
    if (weather !== 'clear') showMessage(weather === 'storm' ? 'Storm rolling in...' : 'Rain starts...');
  }
  if (weather !== 'clear') {
    player.temp = Math.max(7, player.temp - dt * 0.4);
    fires.forEach(f => (f.life -= 1.5 * dt));
  }
}

function updateSurvival(dt) {
  player.hunger = Math.max(0, player.hunger - dt * 0.35);
  player.thirst = Math.max(0, player.thirst - dt * 0.5);
  if (player.hunger < 18 || player.thirst < 12) player.health = Math.max(0, player.health - dt * 1.2);
  const p = controls.getObject().position;
  fires.forEach(f => {
    if (f.group.position.distanceTo(p) < 5.5) player.temp = Math.min(30, player.temp + dt * 2.5);
  });
  if (player.temp < 11) player.health = Math.max(0, player.health - dt * 0.7);
  if (player.health <= 0) {
    showMessage('YOU DIED — refresh page to restart');
    controls.unlock();
  }
}

function showMessage(text) {
  const el = document.getElementById('message');
  el.textContent = text;
  el.classList.add('show');
  messageTimer = 3.2;
}

function updateHUD() {
  document.getElementById('hp-val').textContent = Math.floor(player.health);
  document.getElementById('hp-bar').style.width = player.health + '%';
  document.getElementById('hunger-val').textContent = Math.floor(player.hunger);
  document.getElementById('hunger-bar').style.width = player.hunger + '%';
  document.getElementById('thirst-val').textContent = Math.floor(player.thirst);
  document.getElementById('thirst-bar').style.width = player.thirst + '%';
  document.getElementById('temp-val').textContent = Math.floor(player.temp) + '°C';
  const w = weaponsData[currentWeapon];
  document.getElementById('weapon-name').textContent = w.name;
  document.getElementById('ammo-count').textContent = `${ammo[currentWeapon]} / ${reserveAmmo[currentWeapon]}`;
  const h = Math.floor((gameTime / 3600) % 24);
  const m = Math.floor((gameTime % 3600) / 60);
  document.getElementById('time-display').textContent =
    `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}  ${weather.toUpperCase()}`;
  const dir = new THREE.Vector3();
  camera.getWorldDirection(dir);
  const ang = Math.atan2(dir.x, dir.z);
  const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  document.getElementById('compass').textContent = dirs[Math.round(((ang + Math.PI) / (Math.PI * 2)) * 8) % 8];
}

function setupInput() {
  document.addEventListener('keydown', e => {
    KEYS[e.code] = true;
    if (e.code === 'KeyR') reload();
    if (e.code === 'Digit1') { currentWeapon = 'ar15'; showMessage('AR-15'); }
    if (e.code === 'Digit2') { currentWeapon = 'm1911'; showMessage('1911 .45'); }
    if (e.code === 'KeyE') tryCollectTrophy();
    if (e.code === 'KeyT') deployFlare();
    if (e.code === 'KeyF') buildFire();
    if (e.code === 'KeyB') showMessage('Binoculars active — scan tracks & distant fauna');
    if (e.code === 'Escape') controls.unlock();
  });
  document.addEventListener('keyup', e => { KEYS[e.code] = false; });
  document.addEventListener('mousedown', e => {
    if (!isLocked) return;
    if (e.button === 0) { mouseDown = true; fireWeapon(); }
    if (e.button === 2) isAiming = true;
  });
  document.addEventListener('mouseup', e => {
    if (e.button === 0) mouseDown = false;
    if (e.button === 2) isAiming = false;
  });
  document.addEventListener('contextmenu', e => e.preventDefault());
  controls.addEventListener('lock', () => {
    isLocked = true;
    document.getElementById('ui-overlay').style.display = 'block';
  });
  controls.addEventListener('unlock', () => { isLocked = false; });
}

function updatePlayer(dt) {
  if (!isLocked) return;
  const speed = player.speed *
    ((KEYS['ShiftLeft'] || KEYS['ShiftRight']) ? player.sprintMult : 1) *
    ((KEYS['ControlLeft'] || KEYS['ControlRight']) ? player.crouchMult : 1);
  const forward = new THREE.Vector3();
  const right = new THREE.Vector3();
  camera.getWorldDirection(forward);
  forward.y = 0; forward.normalize();
  right.crossVectors(forward, new THREE.Vector3(0, 1, 0)).normalize();
  let mx = 0, mz = 0;
  if (KEYS['KeyW']) { mx += forward.x; mz += forward.z; }
  if (KEYS['KeyS']) { mx -= forward.x; mz -= forward.z; }
  if (KEYS['KeyD']) { mx += right.x; mz += right.z; }
  if (KEYS['KeyA']) { mx -= right.x; mz -= right.z; }
  const len = Math.hypot(mx, mz);
  if (len > 0) { mx /= len; mz /= len; }
  const vel = playerBody.linvel();
  playerBody.setLinvel({ x: mx * speed, y: vel.y, z: mz * speed }, true);
  if (KEYS['Space'] && Math.abs(vel.y) < 0.45) {
    playerBody.applyImpulse({ x: 0, y: 7.5, z: 0 }, true);
  }
  const t = playerBody.translation();
  controls.getObject().position.set(t.x, t.y + 0.55, t.z);
}

function animate() {
  requestAnimationFrame(animate);
  const dt = Math.min(clock.getDelta(), 0.05);
  world.step();

  if (isLocked) {
    updatePlayer(dt);
    if (mouseDown && weaponsData[currentWeapon].automatic) fireWeapon();
    const playerPos = controls.getObject().position.clone();
    dinosaurs.forEach(d => updateDinoAI(d, dt, playerPos));

    footprints.forEach(f => {
      f.life -= dt;
      f.mesh.material.opacity = Math.max(0, (f.life / 40) * 0.4);
    });
    footprints = footprints.filter(f => {
      if (f.life <= 0) { scene.remove(f.mesh); return false; }
      return true;
    });

    fires.forEach(f => {
      f.life -= dt;
      f.flame.scale.y = 0.85 + Math.sin(performance.now() * 0.012) * 0.2;
      f.light.intensity = 1.1 + Math.random() * 0.45;
    });
    fires = fires.filter(f => {
      if (f.life <= 0) { scene.remove(f.group); return false; }
      return true;
    });

    updateDayNight(dt);
    updateSurvival(dt);
    updateHUD();
    if (messageTimer > 0) {
      messageTimer -= dt;
      if (messageTimer <= 0) document.getElementById('message').classList.remove('show');
    }
  }

  camera.fov = THREE.MathUtils.lerp(camera.fov, isAiming ? 42 : 75, 0.12);
  camera.updateProjectionMatrix();
  renderer.render(scene, camera);
}

init().catch(err => {
  console.error(err);
  document.body.innerHTML = `<pre style="color:#f88;padding:24px;font-size:14px">Init failed: ${err.message}\n\n${err.stack}</pre>`;
});
