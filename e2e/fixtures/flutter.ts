import { expect, Page } from '@playwright/test';

export async function waitForFlutterReady(page: Page) {
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60_000 });
  await page.waitForFunction(
    () => document.querySelectorAll('flt-semantics, flutter-view').length > 0,
    null,
    { timeout: 60_000 },
  );
}

export async function loginViaUi(
  page: Page,
  user = process.env.LF_USER || 'sumaiya.sarkar.171@uhis.test',
  pass = process.env.LF_PASS || 'Uhis123',
) {
  await page.goto('/');
  await waitForFlutterReady(page);
  await expect(page.getByText(/UHIS Next/).first()).toBeVisible({ timeout: 30_000 });
  await page.getByLabel(/username/i).fill(user);
  await page.getByLabel(/password/i).fill(pass);
  await page.getByRole('button', { name: /sign in/i }).click();
}
