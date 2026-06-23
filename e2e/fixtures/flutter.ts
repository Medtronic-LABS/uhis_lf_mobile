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
  user = process.env.LF_USER ,
  pass = process.env.LF_PASS ,
) {
  await page.goto('/');
  await waitForFlutterReady(page);
  await expect(page.getByLabel(/username/i)).toBeVisible({ timeout: 30_000 });
  // Flutter web reads keyboard input from the page-level focused element, not
  // from the semantics <input> directly. Click to focus, then keyboard.type().
  await page.getByLabel(/username/i).click();
  await page.waitForTimeout(300);
  await page.keyboard.type(user, { delay: 100 });
  await page.getByLabel(/password/i).click();
  await page.waitForTimeout(500); // longer wait so Flutter fully registers focus before Shift+key
  await page.keyboard.type(pass, { delay: 100 });
  await page.getByRole('button', { name: /sign in/i }).click();
  // First dashboard load shows the "Use device unlock?" biometric offer as a
  // modal barrier; dismiss it like a real user so the dashboard is reachable.
  try {
    await page.getByRole('button', { name: /not now/i }).click({ timeout: 8_000 });
  } catch (_) {
    // Dialog did not appear (already offered / not supported) — proceed.
  }
  // First-run mandatory PIN setup (custom keypad): enter the PIN, then confirm.
  const pin = process.env.LF_PIN || '123456';
  try {
    await page.getByText(/Create a \d-digit PIN/i).waitFor({ timeout: 8_000 });
    await enterPin(page, pin);
    await page.getByText(/Confirm your PIN/i).waitFor({ timeout: 8_000 });
    await enterPin(page, pin);
  } catch (_) {
    // PIN already set (persisted) or not prompted — proceed.
  }
}

/// Taps the on-screen PIN keypad digit-by-digit.
export async function enterPin(page: Page, pin: string) {
  for (const digit of pin) {
    await page.getByRole('button', { name: digit, exact: true }).click();
  }
}
