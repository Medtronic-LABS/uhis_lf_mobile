import { test, expect } from '@playwright/test';
import { loginViaUi, waitForFlutterReady } from '../fixtures/flutter';

test.describe('login flow', () => {
  test('username + password fields are present', async ({ page }) => {
    await page.goto('/');
    await waitForFlutterReady(page);
    await expect(page.getByLabel(/username/i)).toBeVisible({ timeout: 30_000 });
    await expect(page.getByLabel(/password/i)).toBeVisible({ timeout: 30_000 });
    await expect(page.getByRole('button', { name: /sign in/i })).toBeVisible();
  });

  test('credentials submit and land on dashboard', async ({ page }) => {
    await loginViaUi(page);
    await expect(page.getByText(/Total Patients/i)).toBeVisible({ timeout: 60_000 });
    await expect(page.getByText(/Total Households/i)).toBeVisible({ timeout: 60_000 });
    await expect(page.getByText(/High-Risk Patients/i)).toBeVisible();
  });
});
