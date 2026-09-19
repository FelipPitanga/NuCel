import { supabaseConfig } from './config';

function message(text: string) {
  try {
    const parsed = JSON.parse(text);
    return parsed.message || parsed.error_description || parsed.error || text;
  } catch {
    return text;
  }
}

export async function adminRest<T>(path: string, init: RequestInit = {}): Promise<T> {
  const { url, secretKey } = supabaseConfig();
  const headers = new Headers(init.headers);
  headers.set('apikey', secretKey);
  headers.set('Content-Type', 'application/json');
  headers.set('Accept', 'application/json');

  const response = await fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers,
    cache: 'no-store',
  });
  const text = await response.text();
  if (!response.ok) {
    console.error('NuCel Supabase REST:', response.status, message(text));
    throw new Error('DATABASE');
  }
  return (text ? JSON.parse(text) : null) as T;
}

export function query(table: string, params: Record<string, string>) {
  const search = new URLSearchParams(params);
  return `${table}?${search.toString()}`;
}
