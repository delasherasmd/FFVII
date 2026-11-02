// Abre la página de Proyectar en Chromium (como haría el proyector) y pulsa «OK».
// Uso: node tests/abrir_navegador.js http://IP:8765 [captura.png]
const { chromium } = require('playwright');
(async () => {
  const [url, shot] = process.argv.slice(2);
  const browser = await chromium.launch({ args: ['--no-proxy-server', '--autoplay-policy=user-gesture-required'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  page.on('pageerror', e => console.log('pageerror:', e.message));
  await page.goto(url);
  if (shot) await page.screenshot({ path: shot });
  await page.click('#go');
  console.log('listo');
  const end = async () => { await browser.close(); process.exit(0); };
  process.stdin.on('end', end);
  process.stdin.resume();
  setTimeout(end, 120000);
})().catch(e => { console.log('error:', e.message); process.exit(1); });
