import { cookies } from 'next/headers';
import { supabaseConfig } from './config';

const ACCESS_COOKIE = 'nucel_access';
const REFRESH_COOKIE = 'nucel_refresh';

type SupabaseUser = {
  id: string;
  email?: string;
  user_metadata?: Record<string, unknown>;
};

type SessionResponse = {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
  user?: SupabaseUser;
};

function authHeaders() {
  const { publishableKey } = supabaseConfig();
  return {
    apikey: publishableKey,
    'Content-Type': 'application/json',
  };
}

function cookieOptions(maxAge: number) {
  return {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax' as const,
    path: '/',
    maxAge,
  };
}

async function storeSession(session: SessionResponse) {
  if (!session.access_token || !session.refresh_token) return;
  const store = await cookies();
  store.set(ACCESS_COOKIE, session.access_token, cookieOptions(Math.max(60, session.expires_in || 3600)));
  store.set(REFRESH_COOKIE, session.refresh_token, cookieOptions(60 * 60 * 24 * 30));
}

async function authJson<T>(path: string, init: RequestInit): Promise<{ ok: boolean; status: number; data: T }> {
  const { url } = supabaseConfig();
  const response = await fetch(`${url}/auth/v1/${path}`, {
    ...init,
    headers: { ...authHeaders(), ...(init.headers || {}) },
    cache: 'no-store',
  });
  const text = await response.text();
  let data: unknown = {};
  try { data = text ? JSON.parse(text) : {}; } catch { data = { message: text }; }
  return { ok: response.ok, status: response.status, data: data as T };
}

export async function signInWithPassword(email: string, password: string) {
  const result = await authJson<SessionResponse & { message?: string; error_description?: string }>('token?grant_type=password', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  });
  if (!result.ok || !result.data.access_token) {
    const msg = result.data.error_description || result.data.message || 'E-mail ou senha inválidos.';
    throw new Error(`AUTH:${msg}`);
  }
  await storeSession(result.data);
  return result.data.user || null;
}

export async function signUpWithPassword(email: string, password: string, name: string) {
  const result = await authJson<SessionResponse & { message?: string; error_description?: string }>('signup', {
    method: 'POST',
    body: JSON.stringify({ email, password, data: { full_name: name } }),
  });
  if (!result.ok) {
    const msg = result.data.error_description || result.data.message || 'Não foi possível criar a conta.';
    throw new Error(`AUTH:${msg}`);
  }
  if (result.data.access_token && result.data.refresh_token) await storeSession(result.data);
  return result.data;
}

async function verifyAccessToken(token: string): Promise<SupabaseUser | null> {
  const result = await authJson<SupabaseUser>('user', {
    method: 'GET',
    headers: { Authorization: `Bearer ${token}` },
  });
  return result.ok && result.data?.id ? result.data : null;
}

async function refreshSession(refreshToken: string): Promise<SessionResponse | null> {
  const result = await authJson<SessionResponse>('token?grant_type=refresh_token', {
    method: 'POST',
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  if (!result.ok || !result.data.access_token || !result.data.refresh_token) return null;
  await storeSession(result.data);
  return result.data;
}

export async function getAuthenticatedUser(): Promise<SupabaseUser | null> {
  const store = await cookies();
  const access = store.get(ACCESS_COOKIE)?.value;
  if (access) {
    const user = await verifyAccessToken(access);
    if (user) return user;
  }
  const refresh = store.get(REFRESH_COOKIE)?.value;
  if (!refresh) return null;
  const session = await refreshSession(refresh);
  if (!session?.access_token) return null;
  return session.user || await verifyAccessToken(session.access_token);
}

export async function signOut() {
  const store = await cookies();
  const access = store.get(ACCESS_COOKIE)?.value;

  if (access) {
    try {
      await authJson<unknown>('logout?scope=local', {
        method: 'POST',
        headers: { Authorization: `Bearer ${access}` },
      });
    } catch {
      // Clearing the local cookies must still work if Supabase is temporarily unavailable.
    }
  }

  store.set(ACCESS_COOKIE, '', cookieOptions(0));
  store.set(REFRESH_COOKIE, '', cookieOptions(0));
}
