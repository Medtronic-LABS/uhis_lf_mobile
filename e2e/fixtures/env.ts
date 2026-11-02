export function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required (set it in your shell; never commit it)`);
  return value;
}

export function apiBaseUrl(): string {
  return requireEnv('LF_API_BASE_URL').replace(/\/+$/, '');
}
