-- Planty initial schema.
-- Public catalogue data (species, achievements) is readable by everyone.
-- Private data is readable and writable only by its owner through Row Level Security.
-- XP, levels, achievements and subscriptions are written only by server-side functions,
-- never directly by the app.

create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text check (char_length(username) between 2 and 32),
  avatar_url text,
  preferred_language text not null default 'en' check (preferred_language in ('en', 'de', 'ru')),
  hemisphere text not null default 'north' check (hemisphere in ('north', 'south')),
  plant_count_range text check (plant_count_range in ('none', '1-3', '4-10', '11+')),
  experience_level text check (experience_level in ('beginner', 'experienced')),
  plant_locations text[] not null default '{}',
  care_frequency text check (care_frequency in ('daily', 'few_times_week', 'weekly', 'rarely')),
  wants_daily_reminders boolean,
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- Every new auth user (Apple, email or anonymous guest) gets a profile row.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  insert into public.user_progress (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Botanical catalogue (public)
-- ---------------------------------------------------------------------------

create table public.plant_species (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]+$'),
  scientific_name text not null,
  family text,
  origin text,
  difficulty smallint not null default 2 check (difficulty between 1 and 3),
  light text not null check (light in ('low', 'medium', 'bright_indirect', 'direct')),
  watering_min_days smallint not null check (watering_min_days > 0),
  watering_max_days smallint not null,
  fertilize_interval_days smallint check (fertilize_interval_days > 0),
  fertilize_in_winter boolean not null default false,
  inspect_interval_days smallint not null default 30 check (inspect_interval_days > 0),
  humidity text check (humidity in ('low', 'medium', 'high')),
  temperature_min_c numeric(4, 1),
  temperature_max_c numeric(4, 1),
  pet_safe boolean,
  categories text[] not null default '{}',
  -- Localized long-form care text: {"en": {"description": "...", "soil": "..."}, "de": {...}}
  care jsonb not null default '{}',
  -- Citations for every care value: [{"title": "...", "url": "...", "fields": ["watering"]}]
  source_refs jsonb not null default '[]',
  data_source text not null default 'curated',
  is_premium boolean not null default false,
  updated_at timestamptz not null default now(),
  check (watering_max_days >= watering_min_days)
);

create table public.species_names (
  id bigint generated always as identity primary key,
  species_id uuid not null references public.plant_species (id) on delete cascade,
  locale text not null check (locale in ('en', 'de', 'ru', 'la')),
  name text not null,
  is_primary boolean not null default false,
  unique (species_id, locale, name)
);

create index species_names_name_trgm on public.species_names using gin (lower(name) extensions.gin_trgm_ops);
create index species_names_species on public.species_names (species_id);

create table public.species_images (
  id bigint generated always as identity primary key,
  species_id uuid not null references public.plant_species (id) on delete cascade,
  url text not null,
  author text not null,
  license text not null,
  source_url text not null,
  sort_order smallint not null default 0
);

create index species_images_species on public.species_images (species_id, sort_order);

create trigger plant_species_updated_at before update on public.plant_species
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Private garden data
-- ---------------------------------------------------------------------------

create table public.user_plants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  species_id uuid not null references public.plant_species (id),
  custom_name text not null check (char_length(custom_name) between 1 and 40),
  acquired_at date,
  location text check (location in ('living_room', 'bedroom', 'kitchen', 'bathroom', 'office', 'balcony', 'outdoor', 'other')),
  light text check (light in ('low', 'medium', 'bright_indirect', 'direct')),
  pot_size text check (pot_size in ('small', 'medium', 'large')),
  photo_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index user_plants_sync on public.user_plants (user_id, updated_at);

create table public.care_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  user_plant_id uuid not null references public.user_plants (id) on delete cascade,
  event_type text not null check (event_type in ('water', 'fertilize', 'repot', 'prune', 'inspect', 'note', 'skip_water')),
  completed_at timestamptz not null,
  notes text check (char_length(notes) <= 1000),
  problem_noted boolean not null default false,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  -- Allow small clock skew from devices, but no events logged far in the future.
  check (completed_at <= created_at + interval '1 day')
);

create index care_events_sync on public.care_events (user_id, updated_at);
create index care_events_plant on public.care_events (user_plant_id, completed_at desc);

create table public.care_recommendations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  user_plant_id uuid not null references public.user_plants (id) on delete cascade,
  recommendation_type text not null check (recommendation_type in ('water', 'fertilize', 'repot', 'prune', 'inspect')),
  window_start timestamptz not null,
  window_end timestamptz not null,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'recommended', 'overdue', 'done', 'skipped', 'snoozed', 'not_needed')),
  reasoning jsonb not null default '[]',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (window_end >= window_start)
);

create index care_recommendations_sync on public.care_recommendations (user_id, updated_at);

create table public.plant_status (
  user_plant_id uuid primary key references public.user_plants (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  water_level smallint not null check (water_level between 0 and 4),
  health text not null check (health in ('good', 'fair', 'check')),
  mood text not null check (mood in ('thriving', 'happy', 'neutral', 'thirsty', 'needs_attention')),
  updated_at timestamptz not null default now()
);

create table public.notification_prefs (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  enabled boolean not null default true,
  reminder_time time not null default '09:00',
  quiet_start time default '22:00',
  quiet_end time default '08:00',
  categories jsonb not null default '{"care": true, "achievements": true, "tips": false}',
  muted_plant_ids uuid[] not null default '{}',
  updated_at timestamptz not null default now()
);

create trigger user_plants_updated_at before update on public.user_plants
  for each row execute function public.set_updated_at();
create trigger care_events_updated_at before update on public.care_events
  for each row execute function public.set_updated_at();
create trigger care_recommendations_updated_at before update on public.care_recommendations
  for each row execute function public.set_updated_at();
create trigger plant_status_updated_at before update on public.plant_status
  for each row execute function public.set_updated_at();
create trigger notification_prefs_updated_at before update on public.notification_prefs
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Progress, achievements, subscriptions (server-written)
-- ---------------------------------------------------------------------------

create table public.user_progress (
  user_id uuid primary key references auth.users (id) on delete cascade,
  total_xp integer not null default 0 check (total_xp >= 0),
  garden_level integer not null default 1 check (garden_level >= 1),
  updated_at timestamptz not null default now()
);

create table public.plant_progress (
  user_plant_id uuid primary key references public.user_plants (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  xp integer not null default 0 check (xp >= 0),
  level integer not null default 1 check (level between 1 and 5),
  updated_at timestamptz not null default now()
);

create table public.xp_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  user_plant_id uuid references public.user_plants (id) on delete cascade,
  amount integer not null check (amount > 0 and amount <= 200),
  reason text not null,
  source_event_id uuid unique references public.care_events (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index xp_ledger_user on public.xp_ledger (user_id, created_at);
create unique index xp_ledger_one_award_per_reason on public.xp_ledger (user_id, reason)
  where reason like 'achievement:%' or reason like 'plant_added:%';

create table public.achievements (
  id text primary key check (id ~ '^[a-z0-9_]+$'),
  xp_reward integer not null default 0 check (xp_reward between 0 and 200),
  icon text not null,
  sort_order smallint not null default 0
);

create table public.user_achievements (
  user_id uuid not null references auth.users (id) on delete cascade,
  achievement_id text not null references public.achievements (id),
  unlocked_at timestamptz not null default now(),
  primary key (user_id, achievement_id)
);

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  product_id text not null,
  original_transaction_id text not null unique,
  status text not null check (status in ('active', 'in_grace_period', 'in_billing_retry', 'expired', 'revoked')),
  expires_at timestamptz,
  environment text not null check (environment in ('Production', 'Sandbox')),
  updated_at timestamptz not null default now()
);

insert into public.achievements (id, xp_reward, icon, sort_order) values
  ('first_plant', 20, 'leaf', 1),
  ('first_care', 10, 'drop', 2),
  ('first_week', 30, 'calendar', 3),
  ('seven_day_streak', 50, 'flame', 4),
  ('five_plants', 40, 'square.grid.2x2', 5),
  ('plant_collector', 80, 'books.vertical', 6),
  ('perfect_routine', 100, 'checkmark.seal', 7),
  ('green_thumb', 150, 'hand.thumbsup', 8);

-- ---------------------------------------------------------------------------
-- Rules: plant limit, XP and achievements
-- ---------------------------------------------------------------------------

create or replace function public.is_premium(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.subscriptions s
    where s.user_id = uid
      and s.status in ('active', 'in_grace_period', 'in_billing_retry')
      and (s.expires_at is null or s.expires_at > now())
  );
$$;

-- Free plan: 5 active plants. Checked on insert and when a deleted plant is restored,
-- so a device that was offline cannot sync past the limit.
create or replace function public.enforce_plant_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Rows written for another user are left to Row Level Security to refuse.
  if new.user_id is distinct from auth.uid() then
    return new;
  end if;
  if new.deleted_at is null
     and (tg_op = 'INSERT' or old.deleted_at is not null)
     and not public.is_premium(new.user_id)
     and (select count(*) from public.user_plants p
          where p.user_id = new.user_id and p.deleted_at is null and p.id <> new.id) >= 5 then
    raise exception 'plant_limit_reached' using hint = 'The free plan holds 5 plants.';
  end if;
  return new;
end;
$$;

create trigger user_plants_limit before insert or update of deleted_at on public.user_plants
  for each row execute function public.enforce_plant_limit();

create or replace function public.plant_level_for(xp integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case
    when xp >= 700 then 5
    when xp >= 350 then 4
    when xp >= 150 then 3
    when xp >= 50 then 2
    else 1
  end;
$$;

-- Level L starts at round(100 × (L − 1)^1.5) XP. Mirrors GardenLevel in PlantyKit.
create or replace function public.garden_level_for(xp integer)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  lvl integer := 1;
begin
  while round(100 * power(lvl::numeric, 1.5)) <= xp loop
    lvl := lvl + 1;
  end loop;
  return lvl;
end;
$$;

-- XP for one care event. Mirrors XPRules in PlantyKit.
-- Watering sooner than 60% of the species' shortest interval earns nothing,
-- so the game never rewards overwatering.
create or replace function public.xp_for_event(e public.care_events)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  min_days integer;
  previous timestamptz;
begin
  case e.event_type
    when 'water' then
      select s.watering_min_days into min_days
      from public.user_plants p
      join public.plant_species s on s.id = p.species_id
      where p.id = e.user_plant_id;

      select max(c.completed_at) into previous
      from public.care_events c
      where c.user_plant_id = e.user_plant_id
        and c.event_type = 'water'
        and c.deleted_at is null
        and c.id <> e.id
        and c.completed_at < e.completed_at;

      if previous is not null
         and e.completed_at - previous < interval '1 day' * (min_days * 0.6)::float8 then
        return 0;
      end if;
      return 10;
    when 'fertilize', 'repot' then return 15;
    when 'prune' then return 10;
    else return 5;
  end case;
end;
$$;

create or replace function public.unlock_achievement(uid uuid, achievement text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted integer;
  reward integer;
begin
  insert into public.user_achievements (user_id, achievement_id)
  values (uid, achievement)
  on conflict do nothing;
  get diagnostics inserted = row_count;

  if inserted > 0 then
    select xp_reward into reward from public.achievements where id = achievement;
    if reward > 0 then
      insert into public.xp_ledger (user_id, amount, reason)
      values (uid, reward, 'achievement:' || achievement)
      on conflict do nothing;
    end if;
  end if;
end;
$$;

create or replace function public.check_achievements(uid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  plants integer;
  care_count integer;
  care_span interval;
  streak integer;
  total integer;
begin
  select count(*) into plants
  from public.user_plants where user_id = uid and deleted_at is null;

  select count(*), max(completed_at) - min(completed_at) into care_count, care_span
  from public.care_events
  where user_id = uid and deleted_at is null and event_type <> 'note';

  -- Longest run of consecutive UTC days with at least one care event.
  with days as (
    select distinct (completed_at at time zone 'utc')::date as d
    from public.care_events
    where user_id = uid and deleted_at is null and event_type <> 'note'
  ), runs as (
    select d - (row_number() over (order by d))::integer as grp from days
  )
  select coalesce(max(n), 0) into streak
  from (select count(*) as n from runs group by grp) r;

  if plants >= 1 then perform public.unlock_achievement(uid, 'first_plant'); end if;
  if plants >= 5 then perform public.unlock_achievement(uid, 'five_plants'); end if;
  if plants >= 10 then perform public.unlock_achievement(uid, 'plant_collector'); end if;
  if care_count >= 1 then perform public.unlock_achievement(uid, 'first_care'); end if;
  if care_span >= interval '7 days' then perform public.unlock_achievement(uid, 'first_week'); end if;
  if streak >= 7 then perform public.unlock_achievement(uid, 'seven_day_streak'); end if;

  select coalesce(sum(amount), 0) into total from public.xp_ledger where user_id = uid;
  if public.garden_level_for(total) >= 10 then perform public.unlock_achievement(uid, 'green_thumb'); end if;
  -- 'perfect_routine' needs synced care windows; it is unlocked from Step 4 on.
end;
$$;

create or replace function public.refresh_progress(uid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  total integer;
begin
  perform public.check_achievements(uid);

  insert into public.plant_progress (user_plant_id, user_id, xp, level)
  select p.id, p.user_id, coalesce(sum(l.amount), 0)::integer, public.plant_level_for(coalesce(sum(l.amount), 0)::integer)
  from public.user_plants p
  left join public.xp_ledger l on l.user_plant_id = p.id
  where p.user_id = uid
  group by p.id, p.user_id
  on conflict (user_plant_id) do update
    set xp = excluded.xp, level = excluded.level, updated_at = now();

  select coalesce(sum(amount), 0) into total from public.xp_ledger where user_id = uid;
  insert into public.user_progress (user_id, total_xp, garden_level)
  values (uid, total, public.garden_level_for(total))
  on conflict (user_id) do update
    set total_xp = excluded.total_xp, garden_level = excluded.garden_level, updated_at = now();
end;
$$;

create or replace function public.on_user_plant_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Adding a plant earns XP once per plant, and only for the first 30 plants ever added,
  -- so deleting and re-adding plants cannot farm XP.
  if tg_op = 'INSERT'
     and (select count(*) from public.user_plants where user_id = new.user_id) <= 30 then
    insert into public.xp_ledger (user_id, user_plant_id, amount, reason)
    values (new.user_id, new.id, 20, 'plant_added:' || new.id)
    on conflict do nothing;
  end if;
  perform public.refresh_progress(new.user_id);
  return null;
end;
$$;

create trigger user_plants_progress after insert or update of deleted_at on public.user_plants
  for each row execute function public.on_user_plant_changed();

create or replace function public.on_care_event_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  amount integer;
begin
  if tg_op = 'INSERT' and new.deleted_at is null then
    amount := public.xp_for_event(new);
    if amount > 0 then
      insert into public.xp_ledger (user_id, user_plant_id, amount, reason, source_event_id)
      values (new.user_id, new.user_plant_id, amount, 'care:' || new.event_type, new.id)
      on conflict do nothing;
    end if;
  elsif tg_op = 'UPDATE' and new.deleted_at is not null and old.deleted_at is null then
    -- A corrected (deleted) event gives its XP back.
    delete from public.xp_ledger where source_event_id = new.id;
  end if;
  perform public.refresh_progress(new.user_id);
  return null;
end;
$$;

create trigger care_events_progress after insert or update of deleted_at on public.care_events
  for each row execute function public.on_care_event_changed();

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Access: grants and Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.plant_species enable row level security;
alter table public.species_names enable row level security;
alter table public.species_images enable row level security;
alter table public.user_plants enable row level security;
alter table public.care_events enable row level security;
alter table public.care_recommendations enable row level security;
alter table public.plant_status enable row level security;
alter table public.notification_prefs enable row level security;
alter table public.user_progress enable row level security;
alter table public.plant_progress enable row level security;
alter table public.xp_ledger enable row level security;
alter table public.achievements enable row level security;
alter table public.user_achievements enable row level security;
alter table public.subscriptions enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
grant usage on schema public to anon, authenticated;

grant execute on function public.plant_level_for(integer) to anon, authenticated;
grant execute on function public.garden_level_for(integer) to anon, authenticated;

grant select on public.plant_species, public.species_names, public.species_images, public.achievements
  to anon, authenticated;

grant select on public.profiles to authenticated;
grant update (username, avatar_url, preferred_language, hemisphere, plant_count_range, experience_level,
              plant_locations, care_frequency, wants_daily_reminders, onboarding_completed_at)
  on public.profiles to authenticated;

grant select, insert on public.user_plants to authenticated;
grant update (species_id, custom_name, acquired_at, location, light, pot_size, photo_path, deleted_at)
  on public.user_plants to authenticated;

grant select, insert on public.care_events to authenticated;
grant update (notes, problem_noted, metadata, deleted_at) on public.care_events to authenticated;

grant select, insert, update, delete on public.care_recommendations, public.plant_status, public.notification_prefs
  to authenticated;

grant select on public.user_progress, public.plant_progress, public.xp_ledger, public.user_achievements,
  public.subscriptions to authenticated;

create policy "catalogue is public" on public.plant_species for select using (true);
create policy "catalogue is public" on public.species_names for select using (true);
create policy "catalogue is public" on public.species_images for select using (true);
create policy "catalogue is public" on public.achievements for select using (true);

create policy "own profile" on public.profiles for select using (id = (select auth.uid()));
create policy "own profile update" on public.profiles for update
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "own plants" on public.user_plants for all
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "own care events" on public.care_events for all
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.user_plants p where p.id = user_plant_id and p.user_id = (select auth.uid()))
  );

create policy "own recommendations" on public.care_recommendations for all
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.user_plants p where p.id = user_plant_id and p.user_id = (select auth.uid()))
  );

create policy "own plant status" on public.plant_status for all
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.user_plants p where p.id = user_plant_id and p.user_id = (select auth.uid()))
  );

create policy "own notification prefs" on public.notification_prefs for all
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "read own progress" on public.user_progress for select using (user_id = (select auth.uid()));
create policy "read own plant progress" on public.plant_progress for select using (user_id = (select auth.uid()));
create policy "read own xp" on public.xp_ledger for select using (user_id = (select auth.uid()));
create policy "read own achievements" on public.user_achievements for select using (user_id = (select auth.uid()));
create policy "read own subscription" on public.subscriptions for select using (user_id = (select auth.uid()));
