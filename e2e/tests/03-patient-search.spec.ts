import { test, expect } from '@playwright/test';
import { loginViaUi } from '../fixtures/flutter';

test.describe('patient search', () => {
  test('open patient search screen + chips visible', async ({ page }) => {
    await loginViaUi(page);
    await page.getByText(/Search patients/i).click();
    await expect(page.getByText(/Name$/).first()).toBeVisible({ timeout: 30_000 });
    await expect(page.getByText(/Phone/i).first()).toBeVisible();
    await expect(page.getByText(/^NID$/i).first()).toBeVisible();
  });

  test('name query returns results or empty state', async ({ page }) => {
    await loginViaUi(page);
    await page.getByText(/Search patients/i).click();
    await page.getByRole('textbox').first().fill('a');
    await page.keyboard.press('Enter');
    const result = page.locator('text=/(No patients matched|Age|NID|unnamed)/i').first();
    await expect(result).toBeVisible({ timeout: 30_000 });
  });
});
