// Run after serving build/web: NODE_PATH=<playwright node_modules> node tools/web_smoke.cjs
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--enable-webgl', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1400, height: 840 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    const response = await page.goto('http://127.0.0.1:8060/', { waitUntil: 'load' });
    if (!response || !response.ok()) throw new Error('Web build did not load');
    await page.waitForFunction(() => !document.querySelector('#status'), { timeout: 120000 });
    await page.waitForTimeout(3000);
    const canvas = page.locator('#canvas');
    if (!await canvas.isVisible()) throw new Error('Game canvas is not visible');
    if (errors.length) throw new Error(errors.join('\n'));
    console.log('Web game started and rendered a visible canvas.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
