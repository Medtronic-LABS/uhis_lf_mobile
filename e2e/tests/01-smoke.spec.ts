import { test, expect } from '@playwright/test';
import { waitForFlutterReady } from '../fixtures/flutter';

test.describe('app boot', () => {
  test('flutter web shell attaches', async ({ page }) => {
    await page.goto('/');
    await waitForFlutterReady(page);
    await expect(page.locator('flt-glass-pane')).toHaveCount(1);
  });

  test('login screen exposes UHIS Next brand', async ({ page }) => {
    await page.goto('/');
    await waitForFlutterReady(page);
    await expect(page.getByText(/UHIS Next/).first()).toBeVisible({ timeout: 30_000 });
  });
});
