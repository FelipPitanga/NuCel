-- NuCel database schema. Run this in the dedicated Supabase project.
create table if not exists public.nucel_members (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  name text not null,
  auth_user_id uuid unique references auth.users(id) on delete set null,
  role text not null default 'collaborator' check (role in ('admin', 'collaborator')),
  created_at timestamptz not null default now(),
  constraint nucel_members_email_lower check (email = lower(email))
);

create table if not exists public.nucel_bridges (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  url text not null,
  secret text not null check (char_length(secret) >= 60),
  created_at timestamptz not null default now()
);

create table if not exists public.nucel_devices (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  serial text not null,
  model text not null,
  bridge_id uuid not null references public.nucel_bridges(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (bridge_id, serial)
);

create table if not exists public.nucel_grants (
  member_id uuid not null references public.nucel_members(id) on delete cascade,
  device_id uuid not null references public.nucel_devices(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (member_id, device_id)
);

alter table public.nucel_members enable row level security;
alter table public.nucel_bridges enable row level security;
alter table public.nucel_devices enable row level security;
alter table public.nucel_grants enable row level security;

-- The browser never talks directly to these tables. The Next.js server uses a
-- Supabase secret key after checking the logged-in user's NuCel membership.
revoke all on public.nucel_members from anon, authenticated;
revoke all on public.nucel_bridges from anon, authenticated;
revoke all on public.nucel_devices from anon, authenticated;
revoke all on public.nucel_grants from anon, authenticated;
grant all on public.nucel_members to service_role;
grant all on public.nucel_bridges to service_role;
grant all on public.nucel_devices to service_role;
grant all on public.nucel_grants to service_role;

create or replace function public.nucel_set_grants(p_member_id uuid, p_device_ids uuid[])
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from public.nucel_grants where member_id = p_member_id;
  insert into public.nucel_grants(member_id, device_id)
  select p_member_id, device_id
  from (select distinct unnest(coalesce(p_device_ids, '{}'::uuid[])) as device_id) ids;
end;
$$;

revoke all on function public.nucel_set_grants(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.nucel_set_grants(uuid, uuid[]) to service_role;
