import { signUpWithPassword } from '@/lib/supabase/auth';
import { supabaseConfig } from '@/lib/supabase/config';
import { adminRest, query } from '@/lib/supabase/rest';
import type { Member } from '@/lib/server';

function sameOrigin(req: Request) {
  return req.headers.get('origin') === new URL(req.url).origin;
}

export async function POST(req: Request) {
  try {
    if (!sameOrigin(req)) return Response.json({ error: 'Origem inválida.' }, { status: 403 });
    const body = await req.json() as { email?: string; password?: string; name?: string };
    const email = body.email?.trim().toLowerCase() || '';
    const name = body.name?.trim() || '';
    const password = body.password || '';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return Response.json({ error: 'E-mail inválido.' }, { status: 400 });
    if (password.length < 8) return Response.json({ error: 'A senha precisa ter pelo menos 8 caracteres.' }, { status: 400 });
    if (!name || name.length > 100) return Response.json({ error: 'Informe seu nome.' }, { status: 400 });

    const { ownerEmail } = supabaseConfig();
    const existing = await adminRest<Member[]>(query('nucel_members', { select: 'id,email,name,auth_user_id,role', email: `eq.${email}`, limit: '1' }));
    if (email !== ownerEmail && !existing[0]) return Response.json({ error: 'Seu e-mail ainda não foi liberado pelo administrador.' }, { status: 403 });

    const result = await signUpWithPassword(email, password, name);
    if (existing[0] && result.user?.id && !existing[0].auth_user_id) {
      await adminRest(query('nucel_members', { id: `eq.${existing[0].id}` }), {
        method: 'PATCH',
        body: JSON.stringify({ auth_user_id: result.user.id }),
      });
    } else if (!existing[0] && email === ownerEmail) {
      await adminRest('nucel_members', {
        method: 'POST',
        body: JSON.stringify({ email, name, auth_user_id: result.user?.id || null, role: 'admin' }),
      });
    }

    const needsConfirmation = !result.access_token;
    return Response.json({ ok: true, needsConfirmation }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) {
    const message = error instanceof Error ? error.message : '';
    return Response.json({ error: message.startsWith('AUTH:') ? message.slice(5) : 'Não foi possível criar a conta.' }, { status: 400 });
  }
}
