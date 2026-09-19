import { getAuthenticatedUser } from '@/lib/supabase/auth';
import { adminRest, query } from '@/lib/supabase/rest';
import { supabaseConfig } from '@/lib/supabase/config';

export type Member = {
  id: string;
  email: string;
  name: string;
  auth_user_id: string | null;
  role: 'admin' | 'collaborator';
};

export type Bridge = {
  id: string;
  name: string;
  url: string;
  secret: string;
};

export type Device = {
  id: string;
  name: string;
  serial: string;
  model: string;
  bridge_id: string;
};

export type Grant = { member_id: string; device_id: string };

export async function selectAll<T>(table: string, order?: string): Promise<T[]> {
  const params: Record<string, string> = { select: '*' };
  if (order) params.order = order;
  return adminRest<T[]>(query(table, params));
}

export async function identity(): Promise<Member> {
  const user = await getAuthenticatedUser();
  if (!user?.id || !user.email) throw new Error('UNAUTHENTICATED');
  const email = user.email.toLowerCase();

  let rows = await adminRest<Member[]>(query('nucel_members', {
    select: 'id,email,name,auth_user_id,role',
    auth_user_id: `eq.${user.id}`,
    limit: '1',
  }));
  if (rows[0]) return rows[0];

  rows = await adminRest<Member[]>(query('nucel_members', {
    select: 'id,email,name,auth_user_id,role',
    email: `eq.${email}`,
    limit: '1',
  }));
  if (rows[0]) {
    if (!rows[0].auth_user_id) {
      const updated = await adminRest<Member[]>(query('nucel_members', { id: `eq.${rows[0].id}` }), {
        method: 'PATCH',
        headers: { Prefer: 'return=representation' },
        body: JSON.stringify({ auth_user_id: user.id }),
      });
      return updated[0] || { ...rows[0], auth_user_id: user.id };
    }
    throw new Error('FORBIDDEN');
  }

  const { ownerEmail } = supabaseConfig();
  if (email !== ownerEmail) throw new Error('FORBIDDEN');

  const name = typeof user.user_metadata?.full_name === 'string' && user.user_metadata.full_name.trim()
    ? user.user_metadata.full_name.trim()
    : email.split('@')[0];
  const created = await adminRest<Member[]>('nucel_members', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify({ email, name, auth_user_id: user.id, role: 'admin' }),
  });
  if (!created[0]) throw new Error('DATABASE');
  return created[0];
}

const enc = new TextEncoder();
function b64(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

export async function sign(secret: string, data: object) {
  const payload = b64(enc.encode(JSON.stringify(data)));
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return payload + '.' + b64(new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(payload))));
}
