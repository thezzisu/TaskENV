const fs = require('fs');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');
(async () => {
  const [url, credentialsPath, sandbox, pane] = process.argv.slice(2);
  if (!/^[0-9a-f-]+$/.test(sandbox)) throw Error('invalid sandbox id');
  const credentials = JSON.parse(fs.readFileSync(credentialsPath, 'utf8'));
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ httpCredentials: credentials, extraHTTPHeaders: { Authorization: 'Basic ' + Buffer.from(credentials.username + ':' + credentials.password).toString('base64') }, permissions: ['clipboard-read', 'clipboard-write'] });
    await page.goto(url); await page.waitForTimeout(2500);
    const up = 'taskenv-client-' + Date.now(), down = 'taskenv-guest-' + Date.now();
    await page.evaluate(text => navigator.clipboard.writeText(text), up);
    await page.evaluate(() => { window.dispatchEvent(new Event('blur')); window.dispatchEvent(new Event('focus')); document.getElementById('overlayInput')?.focus(); });
    await page.keyboard.press('Control+v'); await page.waitForTimeout(1000);
    execFileSync('tmux', ['send-keys', '-t', pane, '-l', `taskenv exec ${sandbox} -- bash /tmp/clipboard.sh ${up} ${down}`]);
    execFileSync('tmux', ['send-keys', '-t', pane, 'Enter']);
    for (let i = 0; i < 40; i++) {
      await page.waitForTimeout(200);
      if (await page.evaluate(() => navigator.clipboard.readText()) === down) {
        console.log('TASKENV_BIDIRECTIONAL_CLIPBOARD_PASS'); return;
      }
    }
    throw Error('clipboard return value did not match');
  } finally { await browser.close(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
