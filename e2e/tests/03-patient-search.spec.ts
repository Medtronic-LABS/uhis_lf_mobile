import { test, expect } from '@playwright/test';
import { loginViaUi } from '../fixtures/flutter';

test.describe('global search — patients', () => {
  test('open via top SearchBar + scope chips visible', async ({ page }) => {
    await loginViaUi(page);
    await page.getByText(/Search patients or households/i).click();
    await expect(page.getByText(/^All$/).first()).toBeVisible({ timeout: 30_000 });
    await expect(page.getByText(/^Patients$/).first()).toBeVisible();
    await expect(page.getByText(/^Households$/).first()).toBeVisible();
  });

  test('name query lands in a patient result or empty state', async ({ page }) => {
    await loginViaUi(page);
    await page.getByText(/Search patients or households/i).click();
    await page.getByRole('textbox').first().fill('a');
    const terminal = page.locator(
      'text=/(No matches|No patient matches|Age|NID|Patients\\s+·)/i',
    ).first();
    await expect(terminal).toBeVisible({ timeout: 30_000 });
  });
});
