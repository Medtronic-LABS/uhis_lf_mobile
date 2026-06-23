import { test, expect } from '@playwright/test';
import { loginViaUi, waitForFlutterReady } from '../fixtures/flutter';

test.describe('login flow', () => {
  test('login screen renders with all form elements', async ({ page }) => {
    await page.goto('/');
    await waitForFlutterReady(page);
    await expect(page.getByLabel(/username/i)).toBeVisible({ timeout: 30_000 });
    await expect(page.getByLabel(/password/i)).toBeVisible({ timeout: 30_000 });
    await expect(page.getByRole('button', { name: /sign in/i })).toBeVisible();
  });

  test('credentials are accepted and app navigates past login screen', async ({ page }) => {
    await loginViaUi(page);

    // After successful login the app either:
    //   a) Shows the dashboard ("Total Patients" etc.) if the user has villages, OR
    //   b) Shows the sync-error screen ("No villages assigned") if the backend user
    //      is configured without a village assignment.
    // Both outcomes confirm that login succeeded.
    const dashboardVisible = page.getByText(/Total Patients/i);
    const syncError        = page.getByText(/No villages assigned/i);

    // Wait for whichever screen appears first (up to 60 s).
    await expect(dashboardVisible.or(syncError)).toBeVisible({ timeout: 60_000 });

    // If the sync-error screen appeared, confirm the Sign-in button is gone
    // (we are no longer on the login page) and optionally continue to the dashboard.
    const isErrorScreen = await syncError.isVisible().catch(() => false);
    if (isErrorScreen) {
      // Login was accepted — sign-in button must be gone.
      await expect(page.getByRole('button', { name: /sign in/i })).not.toBeVisible();

      // Tap "Continue with what we have" to reach the dashboard with local data.
      const continueBtn = page.getByText(/continue with what we have/i);
      if (await continueBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
        await continueBtn.click();
        // Dashboard loads with 0-data counters — just confirm it rendered.
        await expect(page.getByText(/Total Patients/i)).toBeVisible({ timeout: 30_000 });
      }
    }
  });
});
