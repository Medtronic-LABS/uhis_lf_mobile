import { test, expect } from '@playwright/test';
import { createHmac } from 'crypto';
import { apiBaseUrl, requireEnv } from '../fixtures/env';

const BASE = apiBaseUrl();
const KEY  = requireEnv('LF_HASH_KEY');
const USER = requireEnv('LF_USER');
const PASS = requireEnv('LF_PASS');

function hashPassword(plaintext: string, key: string): string {
  return createHmac('sha512', key).update(plaintext).digest('hex');
}

test.describe('login API (raw HTTP)', () => {
  test('HMAC-SHA512 with configured key returns 200', async ({ request }) => {
    const hash = hashPassword(PASS, KEY);
    console.log(`[api-login] user=${USER} hash_prefix=${hash.substring(0, 16)}...`);

    const res = await request.post(`${BASE}/auth-service/session`, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'client': 'mob',
      },
      data: `username=${encodeURIComponent(USER)}&password=${encodeURIComponent(hash)}`,
    });

    const body = await res.json();
    console.log(`[api-login] status=${res.status()} body_keys=${Object.keys(body).join(',')}`);

    expect(res.status(), `Login failed: ${JSON.stringify(body)}`).toBe(200);
    expect(body).toHaveProperty('id');
  });
});
