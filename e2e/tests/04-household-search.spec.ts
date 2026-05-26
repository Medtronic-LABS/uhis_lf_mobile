import { test, expect } from '@playwright/test';
import { loginViaUi } from '../fixtures/flutter';

test.describe('global search — households', () => {
  test('households-only scope filter', async ({ page }) => {
    await loginViaUi(page);
    await page.getByText(/Search patients or households/i).click();
    await page.getByText(/^Households$/).first().click();
    await page.getByRole('textbox').first().fill('a');
    const terminal = page.locator(
      'text=/(No matches|No household matches|members|Result list capped|Households\\s+·|Scanning households)/i',
    ).first();
    await expect(terminal).toBeVisible({ timeout: 60_000 });
  });
});
