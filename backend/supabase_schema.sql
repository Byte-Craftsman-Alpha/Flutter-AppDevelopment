create table if not exists public.edu_users (
  roll_number text primary key,
  username text unique not null,
  email text,
  name text,
  department text,
  semester text,
  password_hash text,
  device_id text,
  subscribed_schedule_group text,
  is_online boolean not null default false,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.password_reset_otps (
  id bigint generated always as identity primary key,
  roll_number text not null references public.edu_users(roll_number) on delete cascade,
  email text not null,
  otp_hash text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists password_reset_otps_roll_created_idx
  on public.password_reset_otps (roll_number, created_at desc);

create table if not exists public.student_cloud_state (
  roll_number text primary key references public.edu_users(roll_number) on delete cascade,
  tasks jsonb not null default '[]'::jsonb,
  attendance jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.schedule_overrides (
  group_name text not null,
  date date not null,
  override_data jsonb not null default '[]'::jsonb,
  status text not null default 'active',
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (group_name, date)
);
