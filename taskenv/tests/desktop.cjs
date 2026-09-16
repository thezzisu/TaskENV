// Browser acceptance: URL and private credentials path are explicit inputs.
const fs = require('fs');
const crypto = require('crypto');
const { chromium } = require('playwright');
(async () => {
  const [url, credentialsPath, evidencePrefix] = process.argv.slice(2);
  const credentials = JSON.parse(fs.readFileSync(credentialsPath, 'utf8'));
  const browser = await chromium.launch();
  try {
    const context = await browser.newContext({
      httpCredentials: credentials,
      extraHTTPHeaders: { Authorization: 'Basic ' + Buffer.from(credentials.username + ':' + credentials.password).toString('base64') },
      permissions: ['clipboard-read', 'clipboard-write'], viewport: { width: 1600, height: 960 }, acceptDownloads: true
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(url);
    await page.waitForTimeout(4000);
    if (!(await page.title()).includes('Selkies')) throw Error('desktop frontend did not load');
    if ((await page.locator('body').innerText()).includes('WebSocket disconnected')) throw Error('desktop stream disconnected');
    await page.locator('.toggle-handle').click();
    await page.locator('.sidebar-section-header').filter({ hasText: 'Files' }).click();
    const name = 'taskenv-transfer.bin';
    const payload = crypto.randomBytes(256 * 1024);
    const selecting = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Upload Files', exact: true }).click();
    await (await selecting).setFiles({ name, mimeType: 'application/octet-stream', buffer: payload });
    let uploaded = false;
    for (let i = 0; i < 30; i++) {
      await page.waitForTimeout(200);
      const result = await page.request.get(url + 'api/files/' + name);
      if (result.status() === 200 && (await result.body()).equals(payload)) { uploaded = true; break; }
    }
    if (!uploaded) throw Error('native upload did not match');
    await page.getByRole('button', { name: 'Download Files', exact: true }).click();
    let frame;
    for (let i = 0; i < 30; i++) {
      frame = page.frames().find(frame => frame.url().includes('/api/files/'));
      if (frame) break;
      await page.waitForTimeout(100);
    }
    if (!frame) throw Error('native file index not available');
    const downloading = page.waitForEvent('download');
    await frame.locator('a[href="' + name + '"]').click();
    await (await downloading).saveAs(evidencePrefix + '.download');
    if (!fs.readFileSync(evidencePrefix + '.download').equals(payload)) throw Error('native download did not match');
    if (errors.length) throw Error(errors.join('\n'));
    await page.screenshot({ path: evidencePrefix + '.png' });
    const result = { desktop: true, nativeUpload: true, nativeDownload: true, bytes: payload.length, sha256: crypto.createHash('sha256').update(payload).digest('hex') };
    fs.writeFileSync(evidencePrefix + '.json', JSON.stringify(result));
    console.log('TASKENV_DESKTOP_BROWSER_PASS', JSON.stringify(result));
  } finally { await browser.close(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
