import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  retries: 0,
  timeout: 90_000,
  expect: { timeout: 30_000 },
  reporter: [['html', { outputFolder: 'report', open: 'never' }], ['list']],
  use: {
    baseURL: process.env.LF_MOBILE_BASE_URL || 'http://localhost:5050',
    headless: false,
    trace: 'on',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    viewport: { width: 412, height: 915 },
  },
  projects: [
    {
      name: 'flutter-web',
      use: {
        ...devices['Desktop Chrome'],
        // CORS: the backend allows only production origins. Tests run against
        // localhost:5050 so we disable the same-origin check for the browser.
        launchOptions: { args: ['--disable-web-security', '--disable-site-isolation-trials'] },
      },
    },
  ],
});
