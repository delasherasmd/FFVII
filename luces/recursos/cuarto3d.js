// El cuarto en 3D. Las luces de Smart Life son luces de verdad dentro de la escena:
// iluminan con el mismo color y brillo que las reales.
import * as THREE from "three";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import { RectAreaLightUniformsLib } from "three/addons/lights/RectAreaLightUniformsLib.js";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";

// Medidas en metros. El cuarto va de x -1.7 a 1.7, z -1.5 (pared del fondo) a 1.6, alto 2.6.
const R = { x0: -1.7, x1: 1.7, z0: -1.5, z1: 1.6, h: 2.6 };
export const UBICACIONES = {
  techo: { x: 0, y: 2.45, z: -0.25, forma: "techo" },
  tira: { x: -0.25, y: 0.82, z: -1.45, forma: "tira" },
  foco: { x: -1.3, y: 0.35, z: -0.65, forma: "foco" },
};

// ------------------------------------------------------------------ texturas hechas a mano
function lienzo(w, h, dibujar) {
  const c = document.createElement("canvas"); c.width = w; c.height = h;
  dibujar(c.getContext("2d"), w, h);
  return c;
}
function textura(canvas, { repetir = [1, 1], color = true } = {}) {
  const t = new THREE.CanvasTexture(canvas);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(repetir[0], repetir[1]);
  t.anisotropy = 8;
  if (color) t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
function ruido(ctx, w, h, n, alfa, oscuro = true) {
  for (let i = 0; i < n; i++) {
    const v = oscuro ? 0 : 255;
    ctx.fillStyle = `rgba(${v},${v},${v},${Math.random() * alfa})`;
    ctx.fillRect(Math.random() * w, Math.random() * h, 1 + Math.random() * 2, 1 + Math.random() * 2);
  }
}
const TX = {};
function crearTexturas() {
  TX.yeso = textura(lienzo(512, 512, (c, w, h) => {
    c.fillStyle = "#808080"; c.fillRect(0, 0, w, h);
    for (let i = 0; i < 9000; i++) { const g = 100 + Math.random() * 60;
      c.fillStyle = `rgba(${g},${g},${g},.55)`; c.beginPath(); c.arc(Math.random() * w, Math.random() * h, Math.random() * 2.4, 0, 7); c.fill(); }
  }), { repetir: [6, 5], color: false });
  TX.alfombra = textura(lienzo(512, 512, (c, w, h) => {
    c.fillStyle = "#8f8c87"; c.fillRect(0, 0, w, h);
    for (let i = 0; i < 26000; i++) { const g = 90 + Math.random() * 110;
      c.fillStyle = `rgb(${g},${g - 2},${g - 6})`; c.fillRect(Math.random() * w, Math.random() * h, 1.6, 1.6); }
  }), { repetir: [8, 8] });
  TX.alfombraRelieve = textura(lienzo(256, 256, (c, w, h) => {
    c.fillStyle = "#777"; c.fillRect(0, 0, w, h); ruido(c, w, h, 9000, .9, true); ruido(c, w, h, 9000, .9, false);
  }), { repetir: [16, 16], color: false });
  TX.madera = textura(lienzo(1024, 256, (c, w, h) => {
    const g = c.createLinearGradient(0, 0, 0, h); g.addColorStop(0, "#e4b47a"); g.addColorStop(1, "#d6a265");
    c.fillStyle = g; c.fillRect(0, 0, w, h);
    for (let i = 0; i < 140; i++) { const y = Math.random() * h, a = Math.random() * .18;
      c.strokeStyle = `rgba(120,70,25,${a})`; c.lineWidth = .6 + Math.random() * 1.6; c.beginPath(); c.moveTo(0, y);
      for (let x = 0; x <= w; x += 32) c.lineTo(x, y + Math.sin(x / 90 + i) * 3 + Math.random() * 1.2); c.stroke(); }
  }));
  TX.arce = textura(lienzo(128, 1024, (c, w, h) => {
    c.fillStyle = "#ead0a2"; c.fillRect(0, 0, w, h);
    for (let i = 0; i < 70; i++) { const x = Math.random() * w; c.strokeStyle = `rgba(160,110,50,${Math.random() * .15})`;
      c.lineWidth = 1 + Math.random(); c.beginPath(); c.moveTo(x, 0); c.bezierCurveTo(x + 6, h / 3, x - 6, h / 2, x + 3, h); c.stroke(); }
  }));
  TX.cuerpoBajo = textura(lienzo(512, 512, (c, w, h) => {
    const g = c.createRadialGradient(w * .5, h * .55, 20, w * .5, h * .5, w * .7);
    g.addColorStop(0, "#f0b366"); g.addColorStop(.7, "#d68a3c"); g.addColorStop(1, "#8a4b1c");
    c.fillStyle = g; c.fillRect(0, 0, w, h);
    for (let i = 0; i < 90; i++) { const x = Math.random() * w; c.strokeStyle = `rgba(110,55,15,${Math.random() * .2})`;
      c.lineWidth = .8 + Math.random() * 1.5; c.beginPath(); c.moveTo(x, 0);
      c.bezierCurveTo(x + 20, h * .3, x - 20, h * .6, x + 8, h); c.stroke(); }
  }));
  TX.galaxia = textura(lienzo(1024, 384, (c, w, h) => {
    const g = c.createLinearGradient(0, 0, w, h); g.addColorStop(0, "#150f33"); g.addColorStop(.5, "#2f1755"); g.addColorStop(1, "#5a1f5e");
    c.fillStyle = g; c.fillRect(0, 0, w, h);
    for (const [x, y, r, col] of [[.25, .5, .35, "rgba(120,60,200,.45)"], [.7, .4, .3, "rgba(230,70,150,.35)"], [.5, .8, .25, "rgba(60,120,230,.3)"]]) {
      const n = c.createRadialGradient(x * w, y * h, 0, x * w, y * h, r * w); n.addColorStop(0, col); n.addColorStop(1, "rgba(0,0,0,0)");
      c.fillStyle = n; c.fillRect(0, 0, w, h); }
    for (let i = 0; i < 500; i++) { c.fillStyle = `rgba(255,255,255,${Math.random()})`; c.fillRect(Math.random() * w, Math.random() * h, 1.4, 1.4); }
  }));
  TX.pantalla = textura(lienzo(1024, 600, (c, w, h) => {
    const g = c.createLinearGradient(0, 0, w, h); g.addColorStop(0, "#14234f"); g.addColorStop(.55, "#3a2570"); g.addColorStop(1, "#8a3463");
    c.fillStyle = g; c.fillRect(0, 0, w, h);
    for (let k = 0; k < 4; k++) { c.beginPath(); c.moveTo(0, h * (.55 + k * .08));
      for (let x = 0; x <= w; x += 8) c.lineTo(x, h * (.55 + k * .08) + Math.sin(x / (140 + k * 30) + k) * 40);
      c.lineTo(w, h); c.lineTo(0, h); c.fillStyle = `rgba(${255 - k * 40},${120 + k * 20},${190 + k * 15},${.18 + k * .05})`; c.fill(); }
    c.fillStyle = "rgba(255,255,255,.12)"; c.fillRect(w * .35, h - 46, w * .3, 30);
    for (let i = 0; i < 7; i++) { c.fillStyle = `hsla(${i * 50},70%,70%,.8)`; c.beginPath(); c.arc(w * .38 + i * 42, h - 31, 9, 0, 7); c.fill(); }
  }));
  TX.rejilla = textura(lienzo(256, 256, (c, w, h) => {
    c.clearRect(0, 0, w, h); c.strokeStyle = "#f2f2f0"; c.lineWidth = 5;
    for (let i = 0; i <= w; i += 32) { c.beginPath(); c.moveTo(i, 0); c.lineTo(i, h); c.stroke(); c.beginPath(); c.moveTo(0, i); c.lineTo(w, i); c.stroke(); }
  }), { repetir: [9, 5] });
  TX.malla = textura(lienzo(128, 128, (c, w, h) => {
    c.clearRect(0, 0, w, h); c.strokeStyle = "#141417"; c.lineWidth = 7;
    for (let i = -w; i <= w * 2; i += 22) { c.beginPath(); c.moveTo(i, 0); c.lineTo(i + 40, h); c.stroke(); c.beginPath(); c.moveTo(i, h); c.lineTo(i + 40, 0); c.stroke(); }
  }), { repetir: [14, 14] });
  TX.cuadro = textura(lienzo(512, 700, (c, w, h) => {
    const g = c.createLinearGradient(0, 0, 0, h); g.addColorStop(0, "#1d2350"); g.addColorStop(.5, "#b9567a"); g.addColorStop(.75, "#f58a6a"); g.addColorStop(1, "#f7b26a");
    c.fillStyle = g; c.fillRect(0, 0, w, h);
    c.fillStyle = "#ffe0a0"; c.beginPath(); c.arc(w * .62, h * .5, 70, 0, 7); c.fill();
    const capa = (y, col, amp) => { c.beginPath(); c.moveTo(0, h);
      for (let x = 0; x <= w; x += 10) c.lineTo(x, y + Math.sin(x / 70) * amp + Math.cos(x / 31) * amp * .4); c.lineTo(w, h); c.fillStyle = col; c.fill(); };
    capa(h * .62, "#3b2a5c", 40); capa(h * .72, "#291e45", 34); capa(h * .82, "#18122d", 24);
  }));
  TX.hoja = textura(lienzo(64, 512, (c, w, h) => {
    c.fillStyle = "#2f6b3a"; c.fillRect(0, 0, w, h);
    for (let y = 0; y < h; y += 14 + Math.random() * 12) { c.fillStyle = `rgba(150,200,120,${.15 + Math.random() * .2})`; c.fillRect(0, y, w, 4 + Math.random() * 5); }
    c.fillStyle = "#c9c25a"; c.fillRect(0, 0, 5, h); c.fillRect(w - 5, 0, 5, h);
  }));
}

// ------------------------------------------------------------------ materiales
const M = {};
function crearMateriales() {
  M.pared = new THREE.MeshStandardMaterial({ color: 0xece9e3, roughness: .95, bumpMap: TX.yeso, bumpScale: 1.2 });
  M.techo = new THREE.MeshStandardMaterial({ color: 0xf3f1ec, roughness: .95 });
  M.alfombra = new THREE.MeshStandardMaterial({ map: TX.alfombra, roughness: 1, bumpMap: TX.alfombraRelieve, bumpScale: 2 });
  M.zocalo = new THREE.MeshStandardMaterial({ color: 0xdedad2, roughness: .7 });
  M.madera = new THREE.MeshStandardMaterial({ map: TX.madera, roughness: .55 });
  M.metal = new THREE.MeshStandardMaterial({ color: 0xa7adb4, metalness: .85, roughness: .32 });
  M.cromo = new THREE.MeshStandardMaterial({ color: 0xd8dde3, metalness: 1, roughness: .18 });
  M.negro = new THREE.MeshStandardMaterial({ color: 0x18181b, roughness: .55 });
  M.negroMate = new THREE.MeshStandardMaterial({ color: 0x1d1d20, roughness: .85 });
  M.plastico = new THREE.MeshStandardMaterial({ color: 0x232327, roughness: .45 });
  M.cuero = new THREE.MeshPhysicalMaterial({ color: 0x1e1e22, roughness: .42, clearcoat: .4, clearcoatRoughness: .5 });
  M.cueroBlanco = new THREE.MeshPhysicalMaterial({ color: 0xe9e9e9, roughness: .45, clearcoat: .3 });
  M.rejilla = new THREE.MeshStandardMaterial({ map: TX.rejilla, transparent: true, alphaTest: .4, roughness: .5, side: THREE.DoubleSide });
  M.malla = new THREE.MeshStandardMaterial({ map: TX.malla, transparent: true, alphaTest: .35, roughness: .8, side: THREE.DoubleSide });
  M.tela = new THREE.MeshStandardMaterial({ color: 0x232327, roughness: .95 });
  M.galaxia = new THREE.MeshStandardMaterial({ map: TX.galaxia, roughness: .9 });
  M.pantalla = new THREE.MeshStandardMaterial({ color: 0x000000, emissive: 0xffffff, emissiveMap: TX.pantalla, emissiveIntensity: 1.25, roughness: .25 });
  M.vidrio = new THREE.MeshPhysicalMaterial({ color: 0x111418, roughness: .05, metalness: 0, transparent: true, opacity: .35 });
  M.cuerpoBajo = new THREE.MeshPhysicalMaterial({ map: TX.cuerpoBajo, roughness: .35, clearcoat: 1, clearcoatRoughness: .08 });
  M.arce = new THREE.MeshPhysicalMaterial({ map: TX.arce, roughness: .4, clearcoat: .6, clearcoatRoughness: .2 });
  M.golpeador = new THREE.MeshPhysicalMaterial({ color: 0x141012, roughness: .3, clearcoat: .8 });
  M.cuerdas = new THREE.MeshStandardMaterial({ color: 0xcfd3d8, metalness: 1, roughness: .25 });
  M.maceta = new THREE.MeshStandardMaterial({ color: 0xc2673f, roughness: .85 });
  M.tierra = new THREE.MeshStandardMaterial({ color: 0x3b2a1f, roughness: 1 });
  M.hoja = new THREE.MeshStandardMaterial({ map: TX.hoja, roughness: .6, side: THREE.DoubleSide });
  M.cuadro = new THREE.MeshStandardMaterial({ map: TX.cuadro, roughness: .7 });
  M.marcoPuerta = new THREE.MeshStandardMaterial({ color: 0x1c1917, roughness: .5 });
  M.puerta = new THREE.MeshStandardMaterial({ map: TX.madera, color: 0xf0d8b0, roughness: .6 });
}
const brillante = (hex, f = 1) => new THREE.MeshBasicMaterial({ color: new THREE.Color(hex).multiplyScalar(f), toneMapped: false });

// ------------------------------------------------------------------ ayudas de modelado
function caja(w, h, d, mat, x, y, z, r = 0) {
  const g = r > 0 ? new RoundedBoxGeometry(w, h, d, 3, Math.min(r, w / 2, h / 2, d / 2)) : new THREE.BoxGeometry(w, h, d);
  const m = new THREE.Mesh(g, mat); m.position.set(x, y, z); return m;
}
function cil(r1, r2, h, mat, x, y, z, seg = 24) { const m = new THREE.Mesh(new THREE.CylinderGeometry(r1, r2, h, seg), mat); m.position.set(x, y, z); return m; }
function tubo(puntos, r, mat, seg = 40) {
  const curva = new THREE.CatmullRomCurve3(puntos.map(p => new THREE.Vector3(...p)));
  return new THREE.Mesh(new THREE.TubeGeometry(curva, seg, r, 10, false), mat);
}
function barra(a, b, r, mat) {   // cilindro de a hasta b
  const va = new THREE.Vector3(...a), vb = new THREE.Vector3(...b), d = vb.clone().sub(va);
  const m = new THREE.Mesh(new THREE.CylinderGeometry(r, r, d.length(), 12), mat);
  m.position.copy(va).add(vb).multiplyScalar(.5);
  m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.normalize()); return m;
}
function grupo(...hijos) { const g = new THREE.Group(); hijos.forEach(h => g.add(h)); return g; }
function silueta(puntos) { const s = new THREE.Shape(); s.moveTo(...puntos[0]); for (const p of puntos.slice(1)) s.lineTo(...p); return s; }
function base5(radio, matPata, matRueda, y = .07) {   // base de silla de cinco patas
  const g = new THREE.Group();
  for (let i = 0; i < 5; i++) {
    const a = i * Math.PI * 2 / 5, ex = Math.cos(a) * radio, ez = Math.sin(a) * radio;
    g.add(barra([0, y + .04, 0], [ex, y, ez], .018, matPata));
    const rueda = cil(.028, .028, .03, matRueda, ex, .03, ez); rueda.rotation.x = Math.PI / 2; rueda.rotation.y = a; g.add(rueda);
  }
  return g;
}

// ------------------------------------------------------------------ el cuarto
function cuarto(escena, superficies) {
  const W = R.x1 - R.x0, D = R.z1 - R.z0;
  const piso = new THREE.Mesh(new THREE.PlaneGeometry(W, D), M.alfombra);
  piso.rotation.x = -Math.PI / 2; piso.position.set(0, 0, (R.z0 + R.z1) / 2); escena.add(piso); superficies.push(piso);
  const fondo = caja(W, R.h, .06, M.pared, 0, R.h / 2, R.z0 - .03); escena.add(fondo); superficies.push(fondo);
  const izq = caja(.06, R.h, D, M.pared, R.x0 - .03, R.h / 2, (R.z0 + R.z1) / 2); escena.add(izq); superficies.push(izq);
  const der = caja(.06, R.h, D, M.pared, R.x1 + .03, R.h / 2, (R.z0 + R.z1) / 2); escena.add(der); superficies.push(der);
  const techo = caja(W, .06, D, M.techo, 0, R.h + .03, (R.z0 + R.z1) / 2); escena.add(techo); superficies.push(techo);
  escena.add(caja(W, .08, .015, M.zocalo, 0, .04, R.z0 + .008));
  escena.add(caja(.015, .08, D, M.zocalo, R.x0 + .008, .04, (R.z0 + R.z1) / 2));
  escena.add(caja(.015, .08, D, M.zocalo, R.x1 - .008, .04, (R.z0 + R.z1) / 2));
  // Puerta en la pared derecha, con su marco oscuro
  const pz = .95;
  escena.add(caja(.04, 2.12, .07, M.marcoPuerta, R.x1 - .02, 1.06, pz - .46), caja(.04, 2.12, .07, M.marcoPuerta, R.x1 - .02, 1.06, pz + .46),
    caja(.04, .07, .99, M.marcoPuerta, R.x1 - .02, 2.12, pz));
  escena.add(caja(.03, 2.06, .86, M.puerta, R.x1 - .035, 1.03, pz));
  const manija = cil(.012, .012, .12, M.cromo, R.x1 - .07, 1.0, pz - .33); manija.rotation.x = Math.PI / 2; escena.add(manija);
  // Luminaria de techo (se ilumina cuando la luz está prendida)
  const plafon = grupo(cil(.22, .2, .05, M.zocalo, 0, 0, 0, 48));
  const difusor = cil(.19, .19, .012, new THREE.MeshStandardMaterial({ color: 0xffffff, emissive: 0xffffff, emissiveIntensity: 0, roughness: .4 }), 0, -.03, 0, 48);
  plafon.add(difusor); plafon.position.set(UBICACIONES.techo.x, R.h - .025, UBICACIONES.techo.z); escena.add(plafon);
  return { difusor };
}

function resorte(a, b, r, vueltas, mat) {   // resorte (helicoide) de a hasta b
  const va = new THREE.Vector3(...a), vb = new THREE.Vector3(...b), eje = vb.clone().sub(va), largo = eje.length();
  const pts = [];
  for (let i = 0; i <= vueltas * 16; i++) { const t = i / (vueltas * 16), ang = t * vueltas * Math.PI * 2;
    pts.push(new THREE.Vector3(Math.cos(ang) * r, t * largo, Math.sin(ang) * r)); }
  const m = new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), vueltas * 16, r * .18, 6, false), mat);
  m.position.copy(va); m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), eje.normalize()); return m;
}

function joystick() {   // el joystick de la foto: negro, cruceta dorada y anillos naranjas en las palancas
  const j = new THREE.Group();
  const f = new THREE.Shape();
  f.moveTo(-.055, .042); f.lineTo(.055, .042);
  f.bezierCurveTo(.072, .042, .08, .03, .08, .012);
  f.bezierCurveTo(.08, -.02, .08, -.045, .068, -.062);
  f.bezierCurveTo(.06, -.072, .046, -.072, .038, -.058);
  f.bezierCurveTo(.03, -.044, .022, -.032, 0, -.032);
  f.bezierCurveTo(-.022, -.032, -.03, -.044, -.038, -.058);
  f.bezierCurveTo(-.046, -.072, -.06, -.072, -.068, -.062);
  f.bezierCurveTo(-.08, -.045, -.08, -.02, -.08, .012);
  f.bezierCurveTo(-.08, .03, -.072, .042, -.055, .042);
  const cuerpo = new THREE.Mesh(new THREE.ExtrudeGeometry(f, { depth: .018, bevelEnabled: true, bevelThickness: .009, bevelSize: .008, bevelSegments: 5, curveSegments: 32 }),
    new THREE.MeshPhysicalMaterial({ color: 0x141416, roughness: .5, clearcoat: .3 }));
  cuerpo.rotation.x = -Math.PI / 2; j.add(cuerpo);
  const naranja = new THREE.MeshStandardMaterial({ color: 0xff7a1a, roughness: .35, emissive: 0x401400 });
  const dorado = new THREE.MeshStandardMaterial({ color: 0xd9a93a, metalness: .8, roughness: .3 });
  const palanca = (x, z) => {
    const p = grupo(cil(.011, .012, .012, M.negro, 0, .03, 0, 24));
    const aro = new THREE.Mesh(new THREE.TorusGeometry(.0105, .0022, 10, 32), naranja); aro.rotation.x = Math.PI / 2; aro.position.y = .036; p.add(aro);
    const tapa = cil(.009, .0085, .004, M.negroMate, 0, .038, 0, 24); p.add(tapa);
    p.position.set(x, 0, z); return p;
  };
  j.add(palanca(-.04, -.012), palanca(.022, .018));
  j.add(caja(.022, .005, .007, dorado, -.022, .029, .018, .002), caja(.007, .005, .022, dorado, -.022, .029, .018, .002));
  for (const [x, z] of [[.045, -.022], [.045, -.002], [.035, -.012], [.055, -.012]]) j.add(cil(.0045, .0045, .005, M.negroMate, x, .029, z, 16));
  j.add(cil(.006, .006, .003, new THREE.MeshStandardMaterial({ color: 0x3a3a40, metalness: .4, roughness: .3 }), 0, .028, -.018, 20));
  return j;
}

function amplificador() {   // amplificador naranja de bajo/guitarra
  const a = new THREE.Group();
  const tolex = new THREE.MeshStandardMaterial({ color: 0xf07b18, roughness: .75 });
  a.add(caja(.34, .27, .2, tolex, 0, .135, 0, .02));
  const rejilla = new THREE.Mesh(new THREE.PlaneGeometry(.29, .17), new THREE.MeshStandardMaterial({ map: TX.malla, color: 0x1a1a1a, roughness: .9 }));
  rejilla.position.set(0, .11, .101); a.add(rejilla);
  a.add(caja(.3, .18, .004, new THREE.MeshStandardMaterial({ color: 0x0e0e0e, roughness: .95 }), 0, .11, .098));
  a.add(caja(.3, .045, .01, new THREE.MeshStandardMaterial({ color: 0xe9dcc4, roughness: .6 }), 0, .232, .098));
  for (let k = 0; k < 7; k++) { const p = cil(.007, .007, .012, M.negro, -.11 + k * .034, .232, .108, 16); p.rotation.x = Math.PI / 2; a.add(p); }
  a.add(caja(.14, .02, .03, M.negroMate, 0, .28, 0, .008));
  return a;
}

function escritorio(escena, superficies) {
  const g = new THREE.Group(), cx = -.25, cz = -1.18, ancho = 1.2, prof = .62, alto = .75;
  const izq = cx - ancho / 2, der = cx + ancho / 2;
  const tapa = caja(ancho, .032, prof, M.madera, 0, alto - .016, 0, .008); g.add(tapa); superficies.push(tapa);
  for (const [sx, sz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) g.add(caja(.032, alto - .03, .032, M.metal, sx * (ancho / 2 - .03), (alto - .03) / 2, sz * (prof / 2 - .03)));
  g.add(caja(ancho - .06, .025, .025, M.metal, 0, .68, prof / 2 - .03), caja(.025, .025, prof - .06, M.metal, -(ancho / 2 - .03), .12, 0),
    caja(.025, .025, prof - .06, M.metal, ancho / 2 - .03, .12, 0));
  const panel = new THREE.Mesh(new THREE.PlaneGeometry(ancho - .08, .54), M.rejilla); panel.position.set(0, .4, prof / 2 - .03); g.add(panel);
  g.position.set(cx, 0, cz); escena.add(g);
  const sobre = alto;
  // Monitor con cámara (centrado a la izquierda de los parlantes)
  const mx = cx - .05;
  const mon = new THREE.Group();
  mon.add(caja(.63, .375, .028, M.negro, 0, 0, 0, .008));
  const pant = new THREE.Mesh(new THREE.PlaneGeometry(.605, .345), M.pantalla); pant.position.z = .0145; mon.add(pant);
  mon.add(caja(.2, .16, .04, M.plastico, 0, -.02, -.03, .01));
  mon.add(caja(.09, .028, .035, M.negro, 0, .2, .005, .012));
  const lente = cil(.008, .008, .006, new THREE.MeshPhysicalMaterial({ color: 0x223355, roughness: .05, clearcoat: 1 }), 0, .2, .024); lente.rotation.x = Math.PI / 2; mon.add(lente);
  mon.position.set(mx, sobre + .29, cz - .08); mon.rotation.x = -.04; escena.add(mon);
  escena.add(caja(.045, .2, .03, M.plastico, mx, sobre + .1, cz - .13), caja(.26, .014, .19, M.plastico, mx, sobre + .007, cz - .1, .006));
  // Parlantes: los dos apoyados sobre la mesa, a la derecha del monitor
  const parlante = (w, h, d, x, z, rw) => {
    const p = new THREE.Group(); p.add(caja(w, h, d, M.negroMate, 0, 0, 0, .008));
    const w1 = cil(rw, rw * .8, .012, M.plastico, 0, -h * .18, d / 2, 32); w1.rotation.x = Math.PI / 2; p.add(w1);
    const w2 = cil(rw * .35, rw * .35, .014, M.negro, 0, -h * .18, d / 2 + .002, 24); w2.rotation.x = Math.PI / 2; p.add(w2);
    const tw = cil(rw * .32, rw * .32, .01, M.plastico, 0, h * .28, d / 2, 24); tw.rotation.x = Math.PI / 2; p.add(tw);
    p.position.set(x, sobre + h / 2, z); p.rotation.y = -.12; escena.add(p);
  };
  parlante(.15, .26, .2, cx + .38, cz - .12, .05);
  parlante(.11, .17, .14, cx + .53, cz - .1, .035);
  // Mousepad galáctico, teclado RGB, mouse y joystick
  escena.add(caja(.9, .004, .3, M.galaxia, cx - .03, sobre + .002, cz + .14, .002));
  const tec = new THREE.Group(); tec.add(caja(.44, .022, .14, M.negro, 0, 0, 0, .006));
  const tecla = new THREE.BoxGeometry(.0165, .009, .0165), cols = 22, filas = 6;
  const teclas = new THREE.InstancedMesh(tecla, new THREE.MeshBasicMaterial({ toneMapped: false }), cols * filas);
  const m4 = new THREE.Matrix4(), col = new THREE.Color(); let i = 0;
  for (let f = 0; f < filas; f++) for (let c = 0; c < cols; c++) {
    m4.makeTranslation(-.2 + c * .019, .014, -.052 + f * .0205); teclas.setMatrixAt(i, m4);
    teclas.setColorAt(i++, col.setHSL((c / cols + f * .03) % 1, 1, .55).multiplyScalar(1.4));
  }
  tec.add(teclas); tec.position.set(cx, sobre + .015, cz + .15); escena.add(tec);
  const raton = new THREE.Mesh(new THREE.SphereGeometry(.035, 24, 16), M.negro); raton.scale.set(.85, .45, 1.3);
  raton.position.set(cx + .31, sobre + .016, cz + .16); escena.add(raton);
  const aro = new THREE.Mesh(new THREE.TorusGeometry(.028, .003, 8, 32), brillante(0x3fe0ff, 1.6)); aro.rotation.x = Math.PI / 2; aro.scale.set(1, 1.5, 1);
  aro.position.set(cx + .31, sobre + .006, cz + .16); escena.add(aro);
  const joy = joystick(); joy.position.set(cx - .37, sobre + .004, cz + .17); joy.rotation.y = .35; escena.add(joy);
  // Brazo articulado (tijera con resortes) y micrófono con espuma, como en la foto
  const bx = izq + .04, bz = cz - .2;
  escena.add(caja(.05, .05, .07, M.negro, bx, sobre + .01, bz), caja(.05, .1, .02, M.negro, bx, sobre - .05, bz + .03),
    cil(.012, .012, .08, M.negro, bx, sobre + .06, bz));
  const codo = [bx - .02, sobre + .52, bz - .06], punta = [cx - .4, sobre + .6, cz + .06];
  const base = [bx, sobre + .1, bz];
  escena.add(barra(base, codo, .0075, M.negro), barra([base[0] + .025, base[1], base[2]], [codo[0] + .025, codo[1] + .02, codo[2]], .0075, M.negro));
  escena.add(barra(codo, punta, .0075, M.negro), barra([codo[0], codo[1] + .035, codo[2]], [punta[0], punta[1] + .03, punta[2]], .0075, M.negro));
  escena.add(resorte([base[0] + .012, base[1] + .08, base[2]], [codo[0] + .012, codo[1] - .1, codo[2]], .006, 18, M.negro));
  escena.add(resorte([codo[0] + .06, codo[1] + .02, codo[2] + .01], [punta[0] - .12, punta[1] + .018, punta[2] - .02], .006, 20, M.negro));
  escena.add(caja(.04, .05, .015, M.negro, codo[0] + .01, codo[1] + .015, codo[2]), caja(.035, .06, .015, M.negro, punta[0], punta[1] + .015, punta[2]));
  escena.add(barra(punta, [punta[0], punta[1] - .09, punta[2]], .006, M.cromo));
  const mic = new THREE.Group();
  for (const zz of [-.02, .03]) { const r = new THREE.Mesh(new THREE.TorusGeometry(.036, .004, 8, 32), M.negro); r.position.z = zz; mic.add(r); }
  const cuerpoMic = new THREE.Mesh(new THREE.CylinderGeometry(.024, .024, .13, 24), M.negroMate); cuerpoMic.rotation.x = Math.PI / 2; mic.add(cuerpoMic);
  const espuma = new THREE.Mesh(new THREE.CapsuleGeometry(.034, .04, 10, 24), new THREE.MeshStandardMaterial({ color: 0x121212, roughness: 1, bumpMap: TX.alfombraRelieve, bumpScale: 4 }));
  espuma.rotation.x = Math.PI / 2; espuma.position.z = .095; mic.add(espuma);
  mic.position.set(punta[0], punta[1] - .13, punta[2]); mic.rotation.y = .45; mic.rotation.x = .1; escena.add(mic);
  // Gabinete de la PC: en el piso, al costado derecho de la mesa, alineado con ella
  const pcx = der + .05 + .105;
  const pc = new THREE.Group();
  pc.add(caja(.21, .46, .44, M.negro, 0, 0, 0, .01));
  pc.add(caja(.17, .4, .005, new THREE.MeshStandardMaterial({ color: 0x0b0b0d, roughness: .9 }), 0, 0, .222));
  [0xff2d6a, 0xa64dff, 0xff2d6a].forEach((c, k) => { const t = new THREE.Mesh(new THREE.TorusGeometry(.058, .005, 10, 48), brillante(c, 2.2));
    t.position.set(0, .12 - k * .125, .227); pc.add(t);
    const aspa = cil(.05, .05, .004, new THREE.MeshStandardMaterial({ color: 0x111114, roughness: .6 }), 0, .12 - k * .125, .224, 24); aspa.rotation.x = Math.PI / 2; pc.add(aspa); });
  pc.add(caja(.006, .38, .006, brillante(0x6fd6ff, 1.8), .092, 0, .224));
  const lado = new THREE.Mesh(new THREE.PlaneGeometry(.4, .4), M.vidrio); lado.rotation.y = Math.PI / 2; lado.position.set(.1055, 0, 0); pc.add(lado);
  pc.position.set(pcx, .232, cz + .02); escena.add(pc);
  // Amplificador naranja, prolijo contra la pared a la izquierda de la mesa
  const amp = amplificador(); amp.position.set(izq - .27, 0, cz - .1); amp.rotation.y = .25; escena.add(amp);
  return { pantallaPos: new THREE.Vector3(mx, sobre + .29, cz - .05), pcPos: new THREE.Vector3(pcx, .25, cz + .28), teclas };
}

function sillaGamer(escena) {
  const s = new THREE.Group();
  s.add(base5(.32, M.cromo, M.negro));
  s.add(cil(.026, .026, .32, M.cromo, 0, .27, 0), cil(.04, .045, .14, M.negro, 0, .2, 0));
  s.add(caja(.54, .1, .52, M.cuero, 0, .48, 0, .04));
  s.add(caja(.2, .012, .46, M.cueroBlanco, 0, .533, 0, .005));
  s.add(caja(.08, .1, .5, M.cueroBlanco, -.24, .5, 0, .03), caja(.08, .1, .5, M.cueroBlanco, .24, .5, 0, .03));
  const resp = new THREE.Group();
  resp.add(caja(.5, .82, .1, M.cuero, 0, .41, 0, .045));
  resp.add(caja(.08, .7, .11, M.cueroBlanco, -.19, .4, .002, .035), caja(.08, .7, .11, M.cueroBlanco, .19, .4, .002, .035));
  resp.add(caja(.3, .16, .11, M.cuero, 0, .84, 0, .05));
  resp.add(caja(.16, .06, .112, M.cueroBlanco, 0, .85, .001, .02));
  resp.position.set(0, .52, .25); resp.rotation.x = .17; s.add(resp);   // respaldo reclinado hacia atrás
  for (const lx of [-.3, .3]) {
    s.add(tubo([[lx, .52, .22], [lx, .66, .12], [lx, .68, -.08], [lx * .95, .62, -.2]], .014, M.cromo));
    s.add(caja(.06, .03, .26, M.negroMate, lx, .695, 0, .012));
  }
  s.position.set(-.5, 0, -.5); s.rotation.y = -.3; escena.add(s);
}

function sillaMalla(escena) {
  const s = new THREE.Group();
  s.add(base5(.33, M.negroMate, M.negro));
  s.add(cil(.026, .026, .3, M.cromo, 0, .27, 0), cil(.05, .05, .12, M.negroMate, 0, .2, 0));
  s.add(caja(.52, .08, .5, M.tela, 0, .46, 0, .035));
  // respaldo de malla (se ve a través)
  const forma = new THREE.Shape(); forma.moveTo(-.25, 0); forma.bezierCurveTo(-.3, .25, -.28, .5, -.24, .66);
  forma.quadraticCurveTo(0, .71, .24, .66); forma.bezierCurveTo(.28, .5, .3, .25, .25, 0); forma.quadraticCurveTo(0, -.04, -.25, 0);
  const malla = new THREE.Mesh(new THREE.ShapeGeometry(forma, 24), M.malla);
  const borde = new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(forma.getSpacedPoints(80).map(p => new THREE.Vector3(p.x, p.y, 0)), true), 200, .014, 8, true), M.negroMate);
  const resp = grupo(malla, borde); resp.add(caja(.46, .03, .03, M.negroMate, 0, .2, -.01, .01));
  resp.position.set(0, .58, .26); resp.rotation.x = .12; s.add(resp);   // respaldo reclinado hacia atrás
  // cabezal
  const fc = new THREE.Shape(); fc.moveTo(-.16, 0); fc.quadraticCurveTo(-.2, .07, -.16, .14); fc.quadraticCurveTo(0, .17, .16, .14);
  fc.quadraticCurveTo(.2, .07, .16, 0); fc.quadraticCurveTo(0, -.02, -.16, 0);
  const cab = grupo(new THREE.Mesh(new THREE.ShapeGeometry(fc, 16), M.malla),
    new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(fc.getSpacedPoints(60).map(p => new THREE.Vector3(p.x, p.y, 0)), true), 120, .012, 8, true), M.negroMate));
  cab.position.set(0, 1.36, .37); cab.rotation.x = .15; s.add(cab);
  s.add(barra([-.05, 1.2, .34], [-.05, 1.37, .37], .012, M.negroMate), barra([.05, 1.2, .34], [.05, 1.37, .37], .012, M.negroMate));
  for (const lx of [-.29, .29]) { s.add(barra([lx, .48, .1], [lx, .66, .05], .016, M.negroMate)); s.add(caja(.07, .03, .25, M.negroMate, lx, .675, .02, .012)); }
  s.position.set(.86, 0, -.12); s.rotation.y = 1.5; escena.add(s);   // corrida al costado: no tapa el bajo
}

function texturaSunburst() {   // sunburst de tres tonos: negro en el borde, rojo y ámbar al centro
  return textura(lienzo(768, 1024, (c, w, h) => {
    c.fillStyle = "#0b0504"; c.fillRect(0, 0, w, h);
    c.save(); c.translate(w * .5, h * .6); c.scale(1, 1.18);
    const g = c.createRadialGradient(0, 0, 0, 0, 0, w * .56);
    g.addColorStop(0, "#f3b64e"); g.addColorStop(.38, "#e99a35"); g.addColorStop(.58, "#c9561d");
    g.addColorStop(.72, "#7c1d0f"); g.addColorStop(.84, "#2a0b07"); g.addColorStop(1, "#0b0504");
    c.fillStyle = g; c.beginPath(); c.arc(0, 0, w * .56, 0, 7); c.fill(); c.restore();
    for (let i = 0; i < 70; i++) { const x = Math.random() * w; c.strokeStyle = `rgba(90,40,10,${Math.random() * .1})`;
      c.lineWidth = 1 + Math.random() * 2; c.beginPath(); c.moveTo(x, 0); c.bezierCurveTo(x + 15, h * .3, x - 15, h * .6, x + 6, h); c.stroke(); }
  }));
}

function bajo(escena) {
  // Bajo tipo Precision de 4 cuerdas, como el de la foto: sunburst, golpeador blanco,
  // pastilla partida, placa de controles cromada y mango de arce con puntos oscuros.
  const b = new THREE.Group();
  const conUV = (geo, x0, ancho, y0, alto) => { const uv = geo.attributes.uv, p = geo.attributes.position;
    for (let k = 0; k < uv.count; k++) uv.setXY(k, (p.getX(k) - x0) / ancho, (p.getY(k) - y0) / alto); return geo; };
  const c = new THREE.Shape();
  c.moveTo(0, 0);
  c.bezierCurveTo(.09, 0, .165, .03, .168, .11);
  c.bezierCurveTo(.17, .17, .135, .2, .135, .25);
  c.bezierCurveTo(.135, .29, .158, .31, .152, .345);
  c.bezierCurveTo(.148, .375, .118, .392, .1, .372);
  c.bezierCurveTo(.08, .35, .06, .34, .04, .352);
  c.lineTo(.034, .392); c.lineTo(-.034, .392); c.lineTo(-.04, .36);
  c.bezierCurveTo(-.06, .345, -.08, .37, -.088, .41);
  c.bezierCurveTo(-.094, .45, -.11, .468, -.125, .458);
  c.bezierCurveTo(-.15, .44, -.158, .39, -.155, .34);
  c.bezierCurveTo(-.152, .29, -.13, .27, -.132, .23);
  c.bezierCurveTo(-.134, .19, -.175, .16, -.172, .1);
  c.bezierCurveTo(-.168, .03, -.09, 0, 0, 0);
  const sunburst = new THREE.MeshPhysicalMaterial({ map: texturaSunburst(), roughness: .25, clearcoat: 1, clearcoatRoughness: .05 });
  b.add(new THREE.Mesh(conUV(new THREE.ExtrudeGeometry(c, { depth: .036, bevelEnabled: true, bevelThickness: .006, bevelSize: .007, bevelSegments: 5, curveSegments: 64 }),
    -.18, .36, 0, .48), sunburst));
  const frente = .042 + .006;   // superficie del cuerpo
  // golpeador blanco
  const pg = new THREE.Shape();
  pg.moveTo(-.034, .384); pg.lineTo(-.044, .352);
  pg.bezierCurveTo(-.066, .336, -.088, .36, -.096, .405);
  pg.bezierCurveTo(-.1, .435, -.112, .448, -.122, .442);
  pg.bezierCurveTo(-.142, .425, -.146, .385, -.144, .34);
  pg.bezierCurveTo(-.142, .295, -.12, .27, -.122, .235);
  pg.bezierCurveTo(-.124, .2, -.146, .18, -.142, .155);
  pg.lineTo(-.06, .192); pg.lineTo(-.056, .246); pg.lineTo(.0, .246); pg.lineTo(.004, .206); pg.lineTo(.06, .206); pg.lineTo(.066, .172);
  pg.bezierCurveTo(.09, .162, .11, .172, .12, .192);
  pg.bezierCurveTo(.128, .23, .124, .27, .13, .3);
  pg.bezierCurveTo(.138, .33, .134, .356, .116, .364);
  pg.bezierCurveTo(.095, .36, .07, .345, .044, .356);
  pg.lineTo(.034, .384); pg.lineTo(-.034, .384);
  const blanco = new THREE.MeshPhysicalMaterial({ color: 0xf4f2ec, roughness: .3, clearcoat: .6 });
  const golpeador = new THREE.Mesh(new THREE.ExtrudeGeometry(pg, { depth: .0022, bevelEnabled: true, bevelThickness: .0006, bevelSize: .0008, bevelSegments: 1, curveSegments: 40 }), blanco);
  golpeador.position.z = frente; b.add(golpeador);
  for (const p of pg.getSpacedPoints(16).slice(0, -1)) {
    if (p.y > .34 && Math.abs(p.x) < .06) continue;
    const t = cil(.0022, .0022, .001, M.cromo, p.x * .94, p.y * .985 + .003, frente + .003, 10); t.rotation.x = Math.PI / 2; b.add(t);
  }
  // pastilla partida (estilo P)
  b.add(caja(.054, .022, .011, M.negro, -.026, .233, frente + .005, .004), caja(.054, .022, .011, M.negro, .031, .192, frente + .005, .004));
  // placa de controles cromada con dos perillas y la ficha
  const placa = grupo(caja(.032, .125, .003, M.cromo, 0, 0, 0, .012));
  for (const y of [.035, -.005]) { const k = grupo(cil(.011, .012, .016, M.cromo, 0, 0, .008, 24)); k.children[0].rotation.x = Math.PI / 2; k.position.y = y; placa.add(k); }
  const jack = cil(.006, .006, .006, M.negro, 0, -.045, .004, 16); jack.rotation.x = Math.PI / 2; placa.add(jack);
  placa.position.set(.122, .118, frente + .002); placa.rotation.z = .22; b.add(placa);
  // puente cromado de 4 selletas
  b.add(caja(.086, .046, .005, M.cromo, 0, .072, frente + .0025, .003));
  for (let k = 0; k < 4; k++) b.add(caja(.014, .02, .008, M.cromo, -.027 + k * .018, .074, frente + .008, .002));
  // mango de arce (más angosto en la cejilla) con trastes y puntos oscuros
  const nut = .924, base = .31;
  const mf = new THREE.Shape(); mf.moveTo(-.031, base); mf.lineTo(.031, base); mf.lineTo(.021, nut); mf.lineTo(-.021, nut); mf.lineTo(-.031, base);
  const mango = new THREE.Mesh(conUV(new THREE.ExtrudeGeometry(mf, { depth: .022, bevelEnabled: true, bevelThickness: .003, bevelSize: .002, bevelSegments: 3 }),
    -.04, .08, base, nut - base), M.arce);
  mango.position.z = frente - .015; b.add(mango);
  const tapaMango = frente - .015 + .022 + .003;
  const anchoEn = y => .042 + (.062 - .042) * (nut - y) / (nut - base);
  const traste = n => nut - (.864 - .864 / Math.pow(2, n / 12));
  for (let n = 1; n <= 20; n++) { const y = traste(n); b.add(caja(anchoEn(y) - .002, .0022, .002, M.cromo, 0, y, tapaMango + .001)); }
  const punto = new THREE.MeshStandardMaterial({ color: 0x1d1410, roughness: .4 });
  for (const n of [3, 5, 7, 9, 15, 17, 19]) { const y = (traste(n) + traste(n - 1)) / 2; const d = cil(.0032, .0032, .001, punto, 0, y, tapaMango + .0002, 16); d.rotation.x = Math.PI / 2; b.add(d); }
  for (const x of [-.01, .01]) { const y = (traste(12) + traste(11)) / 2; const d = cil(.0032, .0032, .001, punto, x, y, tapaMango + .0002, 16); d.rotation.x = Math.PI / 2; b.add(d); }
  b.add(caja(.043, .004, .005, new THREE.MeshStandardMaterial({ color: 0xf5f0e2, roughness: .4 }), 0, nut, tapaMango + .002));
  // pala estilo Fender con las 4 clavijas de un solo lado
  const h = new THREE.Shape();
  h.moveTo(-.021, 0); h.lineTo(-.024, .03);
  h.bezierCurveTo(-.03, .07, -.032, .14, -.03, .17);
  h.bezierCurveTo(-.028, .2, -.02, .216, -.004, .217);
  h.bezierCurveTo(.012, .217, .022, .206, .028, .19);
  h.bezierCurveTo(.036, .165, .048, .13, .056, .11);
  h.bezierCurveTo(.062, .09, .056, .07, .04, .06);
  h.bezierCurveTo(.028, .05, .022, .03, .021, 0);
  const pala = new THREE.Mesh(conUV(new THREE.ExtrudeGeometry(h, { depth: .014, bevelEnabled: true, bevelThickness: .002, bevelSize: .002, bevelSegments: 3, curveSegments: 40 }),
    -.04, .1, 0, .22), M.arce);
  pala.position.set(0, nut, frente - .008); b.add(pala);
  const frentePala = frente - .008 + .016;
  const postes = [];
  for (let k = 0; k < 4; k++) {   // de la cejilla hacia arriba: Sol, Re, La, Mi
    const y = nut + .045 + k * .04, x = -.017 + k * .0035; postes.push([x, y]);
    const poste = cil(.0045, .0045, .016, M.cromo, x, y, frentePala + .008, 16); poste.rotation.x = Math.PI / 2; b.add(poste);
    const buje = cil(.007, .007, .002, M.cromo, x, y, frentePala + .001, 20); buje.rotation.x = Math.PI / 2; b.add(buje);
    b.add(barra([-.03, y, frentePala - .01], [-.05, y, frentePala - .01], .003, M.cromo));
    const oreja = new THREE.Mesh(new THREE.CylinderGeometry(.017, .017, .004, 28), M.cromo);   // llave "oreja de elefante"
    oreja.scale.set(1, 1, .82); oreja.rotation.z = Math.PI / 2; oreja.rotation.y = .4; oreja.position.set(-.066, y, frentePala - .01); b.add(oreja);
  }
  const arbol = cil(.0035, .0035, .008, M.cromo, .0, nut + .1, frentePala + .004, 12); arbol.rotation.x = Math.PI / 2; b.add(arbol);
  // cuerdas: Mi, La, Re, Sol (de más gruesa a más fina)
  for (let k = 0; k < 4; k++) {
    const xb = -.027 + k * .018, xn = -.0165 + k * .011, zc = tapaMango + .006, [px, py] = postes[3 - k];
    b.add(barra([xb, .08, frente + .013], [xn, nut, zc], .00115 - k * .0002, M.cuerdas));
    b.add(barra([xn, nut, zc], [px, py, frentePala + .012], .0009 - k * .00012, M.cuerdas));
  }
  b.traverse(o => { if (o.isMesh) o.castShadow = true; });
  // soporte en A (negro), con horquilla para el mango
  const sop = new THREE.Group();
  sop.add(barra([-.13, .02, .13], [0, .12, .03], .01, M.negro), barra([.13, .02, .13], [0, .12, .03], .01, M.negro), barra([0, .02, -.22], [0, .12, .03], .01, M.negro));
  sop.add(barra([0, .12, .03], [0, .84, -.17], .01, M.negro), caja(.26, .02, .06, M.negroMate, 0, .11, .06, .01));
  sop.add(caja(.075, .02, .03, M.negroMate, 0, .845, -.155, .008));
  for (const x of [-.035, .035]) sop.add(barra([x, .84, -.155], [x, .88, -.13], .006, M.negroMate));
  b.position.set(0, .115, .05); b.rotation.x = -.2; sop.add(b);
  sop.position.set(1.18, 0, -1.08); sop.rotation.y = -.35; escena.add(sop);
}

function planta(escena) {
  const p = new THREE.Group();
  const perfil = [[0, 0], [.13, 0], [.15, .02], [.17, .3], [.18, .31], [.17, .32], [0, .32]].map(([x, y]) => new THREE.Vector2(x, y));
  p.add(new THREE.Mesh(new THREE.LatheGeometry(perfil, 40), M.maceta));
  p.add(cil(.165, .165, .01, M.tierra, 0, .3, 0, 32));
  const hojaForma = new THREE.Shape(); hojaForma.moveTo(-.025, 0); hojaForma.bezierCurveTo(-.04, .3, -.03, .5, 0, .7);
  hojaForma.bezierCurveTo(.03, .5, .04, .3, .025, 0); hojaForma.lineTo(-.025, 0);
  for (let k = 0; k < 11; k++) {
    const g = new THREE.ShapeGeometry(hojaForma, 12); const uv = g.attributes.uv, ps = g.attributes.position;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, (ps.getX(i) + .04) / .08, ps.getY(i) / .7);
    const h = new THREE.Mesh(g, M.hoja); const a = k * 2.4, r = .02 + (k % 3) * .03;
    h.position.set(Math.cos(a) * r, .3, Math.sin(a) * r); h.rotation.y = a + Math.PI / 2;
    h.rotation.z = (Math.random() - .5) * .35; h.scale.setScalar(.7 + Math.random() * .55); h.castShadow = true; p.add(h);
  }
  p.position.set(-1.42, 0, -.62); escena.add(p);
}

function cuadro(escena) {
  const c = grupo(caja(.52, .7, .03, M.negro, 0, 0, 0, .006));
  const lam = new THREE.Mesh(new THREE.PlaneGeometry(.46, .64), M.cuadro); lam.position.z = .016; c.add(lam);
  c.position.set(-1.15, 1.5, R.z0 + .02); escena.add(c);
}

// ------------------------------------------------------------------ escena completa
export function crearCuarto(canvas) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: "high-performance" });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
  renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.05;
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  RectAreaLightUniformsLib.init();
  crearTexturas(); crearMateriales();

  const escena = new THREE.Scene(); escena.background = new THREE.Color(0x050407);
  const pmrem = new THREE.PMREMGenerator(renderer);
  escena.environment = pmrem.fromScene(new RoomEnvironment(), .04).texture; escena.environmentIntensity = .05;
  const superficies = [];
  const { difusor } = cuarto(escena, superficies);
  const fijos = escritorio(escena, superficies);
  sillaGamer(escena); sillaMalla(escena); bajo(escena); planta(escena); cuadro(escena);
  escena.traverse(o => { if (o.isMesh) { o.receiveShadow = true; if (o.material !== M.pared && o.material !== M.alfombra) o.castShadow = true; } });

  // Lo que siempre brilla un poco: el monitor ilumina el escritorio y la PC el piso
  const luzMonitor = new THREE.RectAreaLight(0x8fa0ff, 3.2, .6, .34);
  luzMonitor.position.copy(fijos.pantallaPos).add(new THREE.Vector3(0, 0, .03)); luzMonitor.lookAt(fijos.pantallaPos.clone().add(new THREE.Vector3(0, -.2, 1)));
  escena.add(luzMonitor);
  const luzPC = new THREE.PointLight(0xff3d8f, .45, 1.6, 2); luzPC.position.copy(fijos.pcPos); escena.add(luzPC);
  const luzTeclado = new THREE.PointLight(0x9a6bff, .12, .7, 2); luzTeclado.position.set(-.27, .85, -1.0); escena.add(luzTeclado);
  const ambiente = new THREE.HemisphereLight(0x8a96c8, 0x2a2018, .05); escena.add(ambiente);

  const camara = new THREE.PerspectiveCamera(52, 2, .05, 30);
  camara.position.set(.5, 1.5, 1.45);
  const controles = new OrbitControls(camara, canvas);
  controles.target.set(.02, .8, -.88); controles.enableDamping = true; controles.dampingFactor = .08; controles.enablePan = false;
  controles.minDistance = 1.4; controles.maxDistance = 2.75; controles.minPolarAngle = .95; controles.maxPolarAngle = 1.62;
  controles.update();
  const az = controles.getAzimuthalAngle(); controles.minAzimuthAngle = az - .55; controles.maxAzimuthAngle = az + .45;
  const vistaInicial = { pos: camara.position.clone(), target: controles.target.clone() };

  const composer = new EffectComposer(renderer);
  composer.addPass(new RenderPass(escena, camara));
  const bloom = new UnrealBloomPass(new THREE.Vector2(512, 256), .55, .5, .88); composer.addPass(bloom);
  composer.addPass(new OutputPass());

  // --- luces que corresponden a las de Smart Life
  const lamparas = new Map();   // id -> {luz, extra, forma, actual:{c,k}, meta:{c,k}}
  function crearLampara(id, forma) {
    let luz, extra = null;
    if (forma === "tira") {
      luz = new THREE.RectAreaLight(0xffffff, 0, 1.05, .05);
      extra = new THREE.Mesh(new THREE.BoxGeometry(1.05, .012, .012), new THREE.MeshBasicMaterial({ color: 0x000000, toneMapped: false }));
      escena.add(extra);
    } else {
      luz = new THREE.PointLight(0xffffff, 0, 0, 2);
      if (forma === "techo") { luz.castShadow = true; luz.shadow.mapSize.set(1024, 1024); luz.shadow.bias = -.002; luz.shadow.radius = 6; }
      else { extra = new THREE.Mesh(new THREE.SphereGeometry(.035, 20, 14), new THREE.MeshBasicMaterial({ color: 0x000000, toneMapped: false })); escena.add(extra); }
    }
    escena.add(luz);
    const l = { luz, extra, forma, actual: { c: new THREE.Color(0, 0, 0), k: 0 }, meta: { c: new THREE.Color(0, 0, 0), k: 0 }, pos: new THREE.Vector3(), alcance: 1 };
    lamparas.set(id, l); return l;
  }
  function ubicar(l, p) {
    l.pos.set(p.x, p.y, p.z); l.luz.position.copy(l.pos);
    if (l.forma === "tira") { l.luz.lookAt(l.pos.x, l.pos.y + .2, R.z0 - 1); l.extra.position.copy(l.pos).add(new THREE.Vector3(0, 0, .015)); }
    else if (l.extra) l.extra.position.copy(l.pos);
  }
  function setLuces(lista) {
    const vistos = new Set();
    for (const d of lista) {
      if (!d.pos) continue;
      vistos.add(d.id);
      let l = lamparas.get(d.id);
      if (l && l.forma !== d.pos.forma) { escena.remove(l.luz); if (l.extra) escena.remove(l.extra); lamparas.delete(d.id); l = null; }
      if (!l) l = crearLampara(d.id, d.pos.forma);
      ubicar(l, d.pos); l.alcance = d.pos.alcance || 1;
      l.meta.c.setRGB(...(d.color || [0, 0, 0]).map(v => v / 255), THREE.SRGBColorSpace); l.meta.k = d.k || 0;
    }
    for (const [id, l] of lamparas) if (!vistos.has(id)) { escena.remove(l.luz); if (l.extra) escena.remove(l.extra); lamparas.delete(id); }
  }

  const rebote = new THREE.Color(), tmp = new THREE.Color(), azulNoche = new THREE.Color(0x8a96c8);
  function animarLuces() {
    let totalTecho = 0, total = 0;
    rebote.setRGB(0, 0, 0);
    for (const l of lamparas.values()) {
      l.actual.c.lerp(l.meta.c, .15); l.actual.k += (l.meta.k - l.actual.k) * .15;
      const k = l.actual.k * l.alcance;
      l.luz.color.copy(l.actual.c);
      if (l.forma === "techo") { l.luz.intensity = k * 9; totalTecho += k; }
      else if (l.forma === "tira") { l.luz.intensity = k * 14; }
      else { l.luz.intensity = k * 3; }
      const peso = k * (l.forma === "techo" ? 1 : .35);
      total += peso; rebote.add(tmp.copy(l.actual.c).multiplyScalar(peso));
      if (l.extra) l.extra.material.color.copy(l.actual.c).multiplyScalar(l.actual.k * 2.4);
    }
    difusor.material.emissiveIntensity = Math.min(3, totalTecho * 3);
    const t = Math.min(1.2, total);
    // la luz que rebota en las paredes toma el color de las lámparas (si son rojas, el cuarto se pone rojo)
    if (total > .001) rebote.multiplyScalar(1 / total); else rebote.copy(azulNoche);
    ambiente.color.copy(azulNoche).lerp(rebote, Math.min(1, total * 2));
    ambiente.groundColor.copy(ambiente.color).multiplyScalar(.35);
    ambiente.intensity = .05 + .55 * t;
    escena.environmentIntensity = .03 + .08 * t;     // reflejos suaves
  }

  // RGB del teclado: ola de colores lenta
  const colTmp = new THREE.Color();
  function animarTeclado(tiempo) {
    const n = fijos.teclas.count;
    for (let i = 0; i < n; i++) { const c = i % 22, f = Math.floor(i / 22);
      fijos.teclas.setColorAt(i, colTmp.setHSL((c / 22 + f * .03 + tiempo * .05) % 1, 1, .55).multiplyScalar(1.4)); }
    fijos.teclas.instanceColor.needsUpdate = true;
  }

  function tamano() {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false); composer.setSize(w, h);
    camara.aspect = w / h; camara.updateProjectionMatrix();
  }
  new ResizeObserver(tamano).observe(canvas); tamano();

  let alCuadro = () => {};
  const reloj = new THREE.Clock();
  renderer.setAnimationLoop(() => {
    if (document.hidden) return;
    controles.update(); animarLuces(); animarTeclado(reloj.getElapsedTime()); composer.render(); alCuadro();
  });

  const proyectar = new THREE.Vector3(), ray = new THREE.Raycaster();
  return {
    UBICACIONES,
    setLuces,
    alCuadro(fn) { alCuadro = fn; },
    enPantalla(id) {   // dónde dibujar la marca de una luz (en % del lienzo)
      const l = lamparas.get(id); if (!l) return null;
      proyectar.copy(l.pos); if (l.forma === "techo") proyectar.y = R.h - .1;
      proyectar.project(camara);
      return { x: (proyectar.x + 1) / 2, y: (1 - proyectar.y) / 2, detras: proyectar.z > 1 };
    },
    superficie(nx, ny) {   // punto de pared/piso/techo/escritorio bajo el mouse
      ray.setFromCamera(new THREE.Vector2(nx * 2 - 1, -(ny * 2 - 1)), camara);
      const hit = ray.intersectObjects(superficies, false)[0]; if (!hit) return null;
      const n = hit.face.normal.clone().transformDirection(hit.object.matrixWorld);
      const p = hit.point.add(n.multiplyScalar(.12));
      return { x: +p.x.toFixed(3), y: +Math.min(R.h - .1, Math.max(.1, p.y)).toFixed(3), z: +p.z.toFixed(3) };
    },
    vistaInicial() { camara.position.copy(vistaInicial.pos); controles.target.copy(vistaInicial.target); controles.update(); },
    controles,
  };
}
