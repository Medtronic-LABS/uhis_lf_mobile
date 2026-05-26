import { test, expect } from '@playwright/test';
import { loginViaUi } from '../fixtures/flutter';

test.describe('household search', () => {
  test('open household search screen + chips visible', async ({ page }) => {
    await loginViaUi(page);
    await page.getByText(/Search households/i).click();
    await expect(page.getByText(/^Name$/).first()).toBeVisible({ timeout: 30_000 });
    await expect(page.getByText(/Household No/i).first()).toBeVisible();
  });

  test('name query terminates with a result or empty state', async ({ page }) => {
    await loginViaUi(page);
    await page.getByText(/Search households/i).click();
    await page.getByRole('textbox').first().fill('a');
    await page.keyboard.press('Enter');
    const terminal = page.locator(
      'text=/(No households matched|Result list capped|members|unnamed)/i',
    ).first();
    await expect(terminal).toBeVisible({ timeout: 60_000 });
  });
});
