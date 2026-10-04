-- Runtime model availability is account/device state, not a scan result.
-- Keep it separate from model_outputs so unavailable or missing artifacts never
-- look like measured health-screening outputs.

create table if not exists public.model_artifact_audits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  model_id text not null,
  model_name text not null,
  runtime text not null check (runtime in ('Core ML', 'llama.cpp', 'HealthKit', 'app-native')),
  declared_state text not null check (declared_state in ('bundledExecutable', 'sourceBound', 'unavailable')),
  status text not null check (status in ('installed', 'source-bound', 'unavailable', 'missing')),
  executable boolean not null default false,
  source_path text,
  capability text not null,
  evidence text not null,
  action text not null,
  audited_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, model_id)
);

create index if not exists model_artifact_audits_user_status_idx
  on public.model_artifact_audits(user_id, status, audited_at desc);

alter table public.model_artifact_audits enable row level security;

drop policy if exists "model artifact audits are owned by authenticated user" on public.model_artifact_audits;
create policy "model artifact audits are owned by authenticated user"
on public.model_artifact_audits
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
