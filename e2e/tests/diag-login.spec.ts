import { test, expect } from '@playwright/test';
import { waitForFlutterReady } from '../fixtures/flutter';

const USER = process.env.LF_USER ;
const PASS = process.env.LF_PASS || 'Uhis123';

test('diag: capture network during login', async ({ page }) => {
  page.on('console', m => console.log('[console]', m.type(), m.text()));
  page.on('pageerror', e => console.log('[pageerror]', e.message));
  page.on('request', r => {
    if (r.url().includes('service')) console.log('[req]', r.method(), r.url());
  });
  page.on('response', async r => {
    if (r.url().includes('service')) {
      let body = '';
      try { body = (await r.text()).slice(0, 200); } catch {}
      console.log('[res]', r.status(), r.url(), '|', body);
    }
  });
  await page.goto('/');
  await waitForFlutterReady(page);
  await page.getByLabel(/username/i).fill(USER);
  await page.getByLabel(/password/i).fill(PASS);
  await page.getByRole('button', { name: /sign in/i }).click();
  await page.waitForTimeout(8000);
  console.log('[url]', page.url());
});
