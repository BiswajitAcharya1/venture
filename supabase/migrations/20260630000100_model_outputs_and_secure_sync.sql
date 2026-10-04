-- Backend state for Venture's measured outputs.
-- Raw camera frames, raw voice recordings, and transcripts are intentionally not stored.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  terms_version text not null default '2026-06-30',
  accepted_terms_at timestamptz,
  accepted_privacy_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.scan_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  captured_at timestamptz not null,
  drift_score integer check (drift_score between 0 and 100),
  app_version text,
  device_model text,
  created_at timestamptz not null default now()
);

create index if not exists scan_sessions_user_captured_idx
  on public.scan_sessions(user_id, captured_at desc);

create table if not exists public.signal_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  scan_id uuid references public.scan_sessions(id) on delete cascade,
  domain text not null check (domain in ('eyes', 'voice', 'cognition', 'mood', 'recovery', 'cardiac', 'support')),
  name text not null,
  value double precision not null,
  unit text not null default '',
  baseline double precision,
  inverse boolean not null default false,
  evidence jsonb not null default '[]'::jsonb,
  measured_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists signal_metrics_user_domain_time_idx
  on public.signal_metrics(user_id, domain, measured_at desc);

create table if not exists public.model_outputs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  scan_id uuid references public.scan_sessions(id) on delete cascade,
  model_id text not null,
  model_name text not null,
  runtime text not null check (runtime in ('Core ML', 'llama.cpp', 'HealthKit', 'app-native')),
  state text not null check (state in ('bundledExecutable', 'sourceBound', 'unavailable')),
  output_type text not null check (output_type in ('likelihood', 'classification', 'quality', 'summary', 'unavailable')),
  label text not null,
  likelihood_percent double precision check (likelihood_percent is null or likelihood_percent between 0 and 100),
  evidence jsonb not null default '[]'::jsonb,
  action text,
  created_at timestamptz not null default now()
);

create index if not exists model_outputs_user_created_idx
  on public.model_outputs(user_id, created_at desc);

create index if not exists model_outputs_user_model_idx
  on public.model_outputs(user_id, model_id, created_at desc);

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_events_user_created_idx
  on public.audit_events(user_id, created_at desc);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

alter table public.profiles enable row level security;
alter table public.scan_sessions enable row level security;
alter table public.signal_metrics enable row level security;
alter table public.model_outputs enable row level security;
alter table public.audit_events enable row level security;

drop policy if exists "profiles are owned by authenticated user" on public.profiles;
create policy "profiles are owned by authenticated user"
on public.profiles
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "scan sessions are owned by authenticated user" on public.scan_sessions;
create policy "scan sessions are owned by authenticated user"
on public.scan_sessions
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "signal metrics are owned by authenticated user" on public.signal_metrics;
create policy "signal metrics are owned by authenticated user"
on public.signal_metrics
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "model outputs are owned by authenticated user" on public.model_outputs;
create policy "model outputs are owned by authenticated user"
on public.model_outputs
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "users can read own audit events" on public.audit_events;
create policy "users can read own audit events"
on public.audit_events
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "users can create own audit events" on public.audit_events;
create policy "users can create own audit events"
on public.audit_events
for insert
to authenticated
with check (auth.uid() = user_id);
