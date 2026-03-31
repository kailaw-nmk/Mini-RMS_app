import { chromium } from 'playwright';
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJkZXZpY2VfaWQiOiJkYXNoYm9hcmRfb3BlcmF0b3IiLCJ0YWlsc2NhbGVfaXAiOiIxMjcuMC4wLjEiLCJyb2xlIjoib3BlcmF0b3IiLCJpYXQiOjE3NzQ5NTkzMzMsImV4cCI6MTc3NzU1MTMzM30.sdgIUV4TKBM7SfP3oaW9ORncLZIqa5CDs2Ef1UZ-nck';

let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (!condition) throw new Error(msg);
}

async function runTest(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    console.log(`  ✗ ${name}: ${e.message}`);
  }
}

async function main() {
  const browser = await chromium.launch({ headless: false });
  const page = await browser.newPage();

  await page.goto('http://127.0.0.1:3001');
  console.log('Dashboard loaded\n');

  // Test 1: Page title
  await runTest('Page title is TailCall', async () => {
    const title = await page.title();
    assert(title.includes('TailCall'), `Expected title containing TailCall, got: ${title}`);
  });

  // Test 2: Header exists
  await runTest('Header shows TailCall 管制ダッシュボード', async () => {
    const header = await page.textContent('header h1');
    assert(header.includes('管制ダッシュボード'), `Header: ${header}`);
  });

  // Test 3: Config bar has inputs
  await runTest('Config bar has server URL and token inputs', async () => {
    const urlInput = await page.inputValue('#server-url');
    assert(urlInput.includes('localhost'), `URL: ${urlInput}`);
    const tokenInput = await page.getAttribute('#auth-token', 'placeholder');
    assert(tokenInput.includes('JWT'), `Placeholder: ${tokenInput}`);
  });

  // Test 4: Stats cards exist
  await runTest('4 stat cards are present', async () => {
    const cards = await page.$$('.stat-card');
    assert(cards.length === 4, `Expected 4 cards, got ${cards.length}`);
  });

  // Test 5: Connect to server
  await runTest('Connect to server succeeds', async () => {
    await page.fill('#server-url', 'http://localhost:8080');
    await page.fill('#auth-token', TOKEN);
    await page.click('button.btn-call');
    await page.waitForTimeout(2000);

    const status = await page.textContent('#server-status');
    assert(status.includes('接続済み'), `Status: ${status}`);
  });

  // Test 6: Server dot turns green
  await runTest('Server status dot is green (online)', async () => {
    const dot = await page.$('#server-dot');
    const cls = await dot.getAttribute('class');
    assert(cls.includes('online'), `Dot class: ${cls}`);
  });

  // Test 7: Active sessions count
  await runTest('Active calls stat shows number', async () => {
    const val = await page.textContent('#stat-active');
    assert(val !== '-', `Active: ${val}`);
    assert(parseInt(val) >= 0, `Active is a number: ${val}`);
  });

  // Test 8: Total calls stat
  await runTest('Total calls stat shows number', async () => {
    const val = await page.textContent('#stat-total');
    assert(val !== '-' && parseInt(val) > 0, `Total: ${val}`);
  });

  // Test 9: Avg reconnect stat
  await runTest('Avg reconnect stat shows value', async () => {
    const val = await page.textContent('#stat-avg-reconnect');
    assert(val !== '-', `Avg reconnect: ${val}`);
  });

  // Test 10: Driver list populated
  await runTest('Driver list shows sessions', async () => {
    const cards = await page.$$('.driver-card');
    assert(cards.length >= 1, `Expected driver cards, got ${cards.length}`);
  });

  // Test 11: Driver card shows state badge
  await runTest('Driver cards have state badges', async () => {
    const badges = await page.$$('.state-badge');
    assert(badges.length >= 1, `Expected badges, got ${badges.length}`);
    const text = await badges[0].textContent();
    assert(text.length > 0, `Badge text empty`);
  });

  // Test 12: Quality bars exist
  await runTest('Quality bars are shown', async () => {
    const bars = await page.$$('.quality-bar');
    assert(bars.length >= 1, `Expected quality bars, got ${bars.length}`);
  });

  // Test 13: Log table has entries
  await runTest('Call log table has entries', async () => {
    const rows = await page.$$('#log-body tr');
    assert(rows.length >= 1, `Expected log rows, got ${rows.length}`);
    const firstCell = await rows[0].textContent();
    assert(!firstCell.includes('ログなし'), `First row should not be empty placeholder`);
  });

  // Test 14: Event badges in log
  await runTest('Log entries have event badges', async () => {
    const badges = await page.$$('.event-badge');
    assert(badges.length >= 1, `Expected event badges, got ${badges.length}`);
  });

  // Test 15: Screenshot for visual verification
  await runTest('Screenshot captured', async () => {
    await page.screenshot({ path: resolve(__dirname, 'dashboard-test.png'), fullPage: true });
  });

  console.log(`\nResults: ${passed} passed, ${failed} failed, ${passed + failed} total`);

  // Keep browser open for 5 seconds for visual inspection
  await page.waitForTimeout(5000);
  await browser.close();
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(e => { console.error(e); process.exit(1); });
