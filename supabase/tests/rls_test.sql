-- Security and game-rule tests for the Planty schema.
-- Run with scripts/test-db.sh. Any failed check raises an exception and stops the run.
\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'alice@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'bob@example.com');

insert into public.plant_species (id, slug, scientific_name, light, watering_min_days, watering_max_days)
values ('10000000-0000-0000-0000-000000000001', 'monstera-deliciosa', 'Monstera deliciosa', 'bright_indirect', 7, 12);

create or replace function pg_temp.expect(ok boolean, label text) returns void language plpgsql as $$
begin
  if not ok then raise exception 'FAILED: %', label; end if;
  raise notice 'ok - %', label;
end; $$;

-- Signing up creates a profile and progress row.
select pg_temp.expect((select count(*) from public.profiles) = 2, 'profiles created on sign-up');
select pg_temp.expect((select count(*) from public.user_progress) = 2, 'progress rows created on sign-up');

-- Act as Alice.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

insert into public.user_plants (id, species_id, custom_name)
values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Monty');

select pg_temp.expect((select count(*) from public.profiles) = 1, 'Alice sees only her own profile');
select pg_temp.expect((select total_xp from public.user_progress) = 40, 'adding a first plant gives 20 XP + first_plant achievement 20 XP');
select pg_temp.expect(exists (select 1 from public.user_achievements where achievement_id = 'first_plant'), 'first_plant unlocked');

insert into public.care_events (id, user_plant_id, event_type, completed_at)
values ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'water', now() - interval '10 days');
select pg_temp.expect((select amount from public.xp_ledger where source_event_id = '30000000-0000-0000-0000-000000000001') = 10, 'first watering gives 10 XP');

insert into public.care_events (id, user_plant_id, event_type, completed_at)
values ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'water', now() - interval '8 days');
select pg_temp.expect(not exists (select 1 from public.xp_ledger where source_event_id = '30000000-0000-0000-0000-000000000002'), 'watering again after 2 days gives no XP');

insert into public.care_events (id, user_plant_id, event_type, completed_at)
values ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', 'water', now());
select pg_temp.expect((select amount from public.xp_ledger where source_event_id = '30000000-0000-0000-0000-000000000003') = 10, 'watering after 8 days gives XP');
select pg_temp.expect(exists (select 1 from public.user_achievements where achievement_id = 'first_week'), 'first_week unlocked after care spanning 10 days');

-- Correcting (soft-deleting) an event takes its XP back.
update public.care_events set deleted_at = now() where id = '30000000-0000-0000-0000-000000000003';
select pg_temp.expect(not exists (select 1 from public.xp_ledger where source_event_id = '30000000-0000-0000-0000-000000000003'), 'deleted event loses its XP');

-- The client cannot write XP, achievements, subscriptions or premium status.
do $$ begin
  insert into public.xp_ledger (user_id, amount, reason) values (auth.uid(), 100, 'cheat');
  raise exception 'FAILED: client inserted XP';
exception when insufficient_privilege then raise notice 'ok - client cannot insert XP';
end $$;

do $$ begin
  update public.user_progress set total_xp = 99999;
  raise exception 'FAILED: client updated progress';
exception when insufficient_privilege then raise notice 'ok - client cannot update progress';
end $$;

do $$ begin
  insert into public.subscriptions (user_id, product_id, original_transaction_id, status, environment)
  values (auth.uid(), 'premium.yearly', 'fake', 'active', 'Production');
  raise exception 'FAILED: client created a subscription';
exception when insufficient_privilege then raise notice 'ok - client cannot create a subscription';
end $$;

do $$ begin
  update public.care_events set event_type = 'repot' where id = '30000000-0000-0000-0000-000000000001';
  raise exception 'FAILED: client rewrote an event type';
exception when insufficient_privilege then raise notice 'ok - event type cannot be rewritten';
end $$;

do $$ begin
  perform public.refresh_progress(auth.uid());
  raise exception 'FAILED: client called an internal function';
exception when insufficient_privilege then raise notice 'ok - internal functions are not callable';
end $$;

-- Free plan: the 6th active plant is refused.
insert into public.user_plants (species_id, custom_name)
select '10000000-0000-0000-0000-000000000001', 'Plant ' || n from generate_series(2, 5) n;
do $$ begin
  insert into public.user_plants (species_id, custom_name) values ('10000000-0000-0000-0000-000000000001', 'Sixth');
  raise exception 'FAILED: sixth plant accepted';
exception when raise_exception then
  if sqlerrm <> 'plant_limit_reached' then raise; end if;
  raise notice 'ok - free plan stops at 5 plants';
end $$;
select pg_temp.expect(exists (select 1 from public.user_achievements where achievement_id = 'five_plants'), 'five_plants unlocked');

-- Act as Bob: he sees none of Alice's data and cannot write into her garden.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select pg_temp.expect((select count(*) from public.user_plants) = 0, 'Bob cannot see Alice''s plants');
select pg_temp.expect((select count(*) from public.care_events) = 0, 'Bob cannot see Alice''s care events');
select pg_temp.expect((select count(*) from public.xp_ledger) = 0, 'Bob cannot see Alice''s XP');

do $$ begin
  insert into public.care_events (user_plant_id, event_type, completed_at)
  values ('20000000-0000-0000-0000-000000000001', 'water', now());
  raise exception 'FAILED: Bob logged care on Alice''s plant';
exception when insufficient_privilege then raise notice 'ok - Bob cannot log care on Alice''s plant';
end $$;

do $$ begin
  insert into public.user_plants (user_id, species_id, custom_name)
  values ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', 'Planted for Alice');
  raise exception 'FAILED: Bob created a plant for Alice';
exception when insufficient_privilege then raise notice 'ok - Bob cannot create plants for Alice';
end $$;

update public.user_plants set custom_name = 'Hacked' where id = '20000000-0000-0000-0000-000000000001';
reset role;
select pg_temp.expect((select custom_name from public.user_plants where id = '20000000-0000-0000-0000-000000000001') = 'Monty', 'Bob''s update of Alice''s plant changed nothing');

-- Anonymous visitors can read the catalogue and nothing else.
set role anon;
select set_config('request.jwt.claim.sub', '', false);
select pg_temp.expect((select count(*) from public.plant_species) = 1, 'anon can read species');
do $$ begin
  perform 1 from public.user_plants;
  raise exception 'FAILED: anon read plants';
exception when insufficient_privilege then raise notice 'ok - anon cannot read plants';
end $$;
reset role;

-- Server-side levels match PlantyKit.
select pg_temp.expect(public.garden_level_for(99) = 1 and public.garden_level_for(100) = 2
  and public.garden_level_for(282) = 2 and public.garden_level_for(283) = 3 and public.garden_level_for(800) = 5,
  'garden levels match PlantyKit');
select pg_temp.expect(public.plant_level_for(49) = 1 and public.plant_level_for(50) = 2 and public.plant_level_for(700) = 5,
  'plant levels match PlantyKit');

\echo 'All database tests passed.'
