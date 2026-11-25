-- Anatomia online: accounts, the learning progress of each account (sync between devices), friends and their
-- leaderboard. Applied to the Supabase project through the Management API. Every table has row level security:
-- an account reads and changes only its own rows; friends and the leaderboard go through the functions below.

-- a number from a JSON text, or 0 when it is none (the progress comes from the app; a broken value must not break
-- the leaderboard of the whole group)
create or replace function public.num(t text) returns bigint
language sql immutable set search_path = '' as $$
  select case when t ~ '^-?[0-9]{1,12}(\.[0-9]+)?$' then greatest(0, least(1000000000, floor(t::numeric)))::bigint else 0 end;
$$;

-- profiles: the nickname friends see and the code to be added as a friend
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 2 and 24),
  friend_code text not null unique check (friend_code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  created_at timestamptz not null default now()
);

-- progress: the app's whole saved state of the account, with a revision for the sync (each write adds one)
create table if not exists public.progress (
  user_id uuid primary key references auth.users (id) on delete cascade,
  rev integer not null default 0,
  data jsonb not null check (jsonb_typeof(data) = 'object' and pg_column_size(data) < 3000000),
  device text check (device is null or char_length(device) <= 60),
  updated_at timestamptz not null default now()
);

-- friends: stored both ways (adding someone makes both friends of each other)
create table if not exists public.friends (
  user_id uuid not null references auth.users (id) on delete cascade,
  friend_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

alter table public.profiles enable row level security;
alter table public.progress enable row level security;
alter table public.friends enable row level security;

drop policy if exists "own profile" on public.profiles;
drop policy if exists "own profile name" on public.profiles;
drop policy if exists "own progress read" on public.progress;
drop policy if exists "own progress insert" on public.progress;
drop policy if exists "own progress update" on public.progress;
drop policy if exists "own friends" on public.friends;
create policy "own profile" on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy "own profile name" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy "own progress read" on public.progress for select to authenticated using (user_id = (select auth.uid()));
create policy "own progress insert" on public.progress for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own progress update" on public.progress for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own friends" on public.friends for select to authenticated using (user_id = (select auth.uid()));

-- what the app's API may do with the tables (new tables are not exposed on their own)
revoke all on public.profiles, public.progress, public.friends from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (name) on public.profiles to authenticated;
grant select, insert, update on public.progress to authenticated;
grant select on public.friends to authenticated;

-- each write of the progress: the next revision and the time (the app writes "where rev = the one it knows", so a
-- write from another device in between is noticed and merged first)
create or replace function public.progress_stamp() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then new.rev := 1; else new.rev := old.rev + 1; new.user_id := old.user_id; end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists progress_stamp on public.progress;
create trigger progress_stamp before insert or update on public.progress
  for each row execute function public.progress_stamp();

-- a friend code: 8 letters and digits without the look-alikes 0/O and 1/I
create or replace function public.new_friend_code() returns text
language plpgsql set search_path = '' as $$
declare
  abc constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  b bytea; c text;
begin
  loop
    b := extensions.gen_random_bytes(8); c := '';
    for i in 0..7 loop c := c || substr(abc, 1 + get_byte(b, i) % 32, 1); end loop;
    exit when not exists (select 1 from public.profiles where friend_code = c);
  end loop;
  return c;
end $$;

-- a new account gets its profile: the nickname given at sign-up, else the first name of a Google/Apple account
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v text;
begin
  v := btrim(coalesce(new.raw_user_meta_data ->> 'nickname',
                      split_part(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''), ' ', 1)));
  if char_length(v) < 2 then v := 'Anatomie-Fan'; end if;
  insert into public.profiles (id, name, friend_code) values (new.id, left(v, 24), public.new_friend_code());
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- add a friend by their code (both become friends of each other)
create or replace function public.add_friend(code text) returns json
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); f record;
begin
  if me is null then return json_build_object('ok', false, 'error', 'auth'); end if;
  select id, name into f from public.profiles
   where friend_code = upper(regexp_replace(coalesce(code, ''), '[^A-Za-z0-9]', '', 'g'));
  if f.id is null then return json_build_object('ok', false, 'error', 'unknown'); end if;
  if f.id = me then return json_build_object('ok', false, 'error', 'self'); end if;
  if (select count(*) from public.friends where user_id = me) >= 200 then return json_build_object('ok', false, 'error', 'full'); end if;
  insert into public.friends (user_id, friend_id) values (me, f.id), (f.id, me) on conflict do nothing;
  return json_build_object('ok', true, 'id', f.id, 'name', f.name);
end $$;

-- remove a friend (both ways)
create or replace function public.remove_friend(friend uuid) returns void
language sql security definer set search_path = '' as $$
  delete from public.friends
   where (user_id = auth.uid() and friend_id = friend) or (user_id = friend and friend_id = auth.uid());
$$;

-- the leaderboard of me and my friends: XP in all, XP of this week (from the days in the progress, the caller's
-- Monday to today) and the streak (only while it runs: last day today or yesterday)
create or replace function public.leaderboard(week_start date, today date)
returns table (id uuid, name text, me boolean, xp bigint, week_xp bigint, streak bigint)
language sql stable security definer set search_path = '' as $$
  with people as (
    select auth.uid() as id where auth.uid() is not null
    union
    select f.friend_id from public.friends f where f.user_id = auth.uid()
  )
  select p.id, pr.name, p.id = auth.uid(),
         public.num(g.data ->> 'xp'),
         coalesce((select sum(public.num(l.value)) from jsonb_each_text(case when jsonb_typeof(g.data -> 'log') = 'object' then g.data -> 'log' else '{}'::jsonb end) l
                    where l.key >= to_char(week_start, 'YYYY-MM-DD') and l.key <= to_char(today, 'YYYY-MM-DD')), 0)::bigint
       + coalesce((select sum(public.num(l.value)) from jsonb_each_text(case when jsonb_typeof(g.data -> 'xlog') = 'object' then g.data -> 'xlog' else '{}'::jsonb end) l
                    where l.key >= to_char(week_start, 'YYYY-MM-DD') and l.key <= to_char(today, 'YYYY-MM-DD')), 0)::bigint,
         case when coalesce(g.data ->> 'lastDay', '') >= to_char(today - 1, 'YYYY-MM-DD') then public.num(g.data ->> 'streak') else 0 end
    from people p
    join public.profiles pr on pr.id = p.id
    left join public.progress g on g.user_id = p.id;
$$;

-- delete my account with everything in it (profile, progress, friends go with it)
create or replace function public.delete_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from auth.users where id = auth.uid();
end $$;

-- who may call which function through the API
revoke execute on function public.num(text), public.progress_stamp(), public.new_friend_code(), public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.add_friend(text), public.remove_friend(uuid), public.leaderboard(date, date), public.delete_account() from public, anon;
grant execute on function public.add_friend(text), public.remove_friend(uuid), public.leaderboard(date, date), public.delete_account() to authenticated;

-- ---- 2. the global leaderboard: everyone who shows their nickname, by XP in all or this week ----

-- shown in the global leaderboard (each account can switch it off)
alter table public.profiles add column if not exists public boolean not null default true;
grant update (name, public) on public.profiles to authenticated;

-- the numbers of each account for the leaderboard, worked out from its progress at each write
create table if not exists public.stats (
  user_id uuid primary key references auth.users (id) on delete cascade,
  xp bigint not null default 0,
  week_start date,
  week_xp bigint not null default 0,
  streak bigint not null default 0,
  last_day text,
  updated_at timestamptz not null default now()
);
alter table public.stats enable row level security;
revoke all on public.stats from anon, authenticated;
create index if not exists stats_xp on public.stats (xp desc);
create index if not exists stats_week on public.stats (week_start, week_xp desc);

-- today in German time: the global leaderboard's weeks run from Monday
create or replace function public.berlin_today() returns date
language sql stable set search_path = '' as $$
  select (now() at time zone 'Europe/Berlin')::date;
$$;

-- an account's numbers from its progress: XP in all, XP of this week (log and xlog), the streak with its last day;
-- values nobody reaches by learning count as nothing
create or replace function public.stats_put(uid uuid, d jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  ws date := date_trunc('week', public.berlin_today())::date;
  a text := to_char(ws, 'YYYY-MM-DD'); z text := to_char(ws + 6, 'YYYY-MM-DD');
  x bigint := public.num(d ->> 'xp'); w bigint;
begin
  w := coalesce((select sum(public.num(l.value)) from jsonb_each_text(case when jsonb_typeof(d -> 'log') = 'object' then d -> 'log' else '{}'::jsonb end) l where l.key between a and z), 0)
     + coalesce((select sum(public.num(l.value)) from jsonb_each_text(case when jsonb_typeof(d -> 'xlog') = 'object' then d -> 'xlog' else '{}'::jsonb end) l where l.key between a and z), 0);
  if x > 10000000 then x := 0; end if;
  if w > 100000 then w := 0; end if;
  insert into public.stats (user_id, xp, week_start, week_xp, streak, last_day, updated_at)
  values (uid, x, ws, w, public.num(d ->> 'streak'), left(coalesce(d ->> 'lastDay', ''), 10), now())
  on conflict (user_id) do update set xp = excluded.xp, week_start = excluded.week_start, week_xp = excluded.week_xp,
    streak = excluded.streak, last_day = excluded.last_day, updated_at = now();
end $$;
create or replace function public.progress_stats() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.stats_put(new.user_id, new.data);
  return new;
end $$;
drop trigger if exists progress_stats on public.progress;
create trigger progress_stats after insert or update on public.progress
  for each row execute function public.progress_stats();
-- the accounts that have progress already
select public.stats_put(user_id, data) from public.progress;

-- the global leaderboard (period 'week' or 'all'): how many are on it, my place, the first lim (up to 100).
-- On it: everyone shown with XP above 0; I always see my own place, also when I am not shown to others.
create or replace function public.global_board(period text, lim integer default 50) returns json
language sql stable security definer set search_path = '' as $$
  with cur as (select date_trunc('week', public.berlin_today())::date ws, public.berlin_today() td),
  v as (
    select s.user_id, p.name, p.public,
           case when period = 'week' then case when s.week_start = (select ws from cur) then s.week_xp else 0 end else s.xp end val,
           case when s.last_day >= to_char((select td from cur) - 1, 'YYYY-MM-DD') then s.streak else 0 end streak
      from public.stats s join public.profiles p on p.id = s.user_id
  ),
  shown as (select * from v where val > 0 and (public or user_id = auth.uid())),
  ranked as (select user_id, name, val, streak, rank() over (order by val desc) rk from shown)
  select json_build_object(
    'total', (select count(*) from shown),
    'me', (select json_build_object('rank', rk, 'value', val, 'streak', streak) from ranked where user_id = auth.uid()),
    'top', coalesce((select json_agg(json_build_object('rank', t.rk, 'name', t.name, 'value', t.val, 'streak', t.streak, 'me', t.user_id = auth.uid()) order by t.rk, t.name)
                       from (select * from ranked order by rk, name limit greatest(1, least(coalesce(lim, 50), 100))) t), '[]'::json))
  where auth.uid() is not null;
$$;

revoke execute on function public.berlin_today(), public.stats_put(uuid, jsonb), public.progress_stats() from public, anon, authenticated;
revoke execute on function public.global_board(text, integer) from public, anon;
grant execute on function public.global_board(text, integer) to authenticated;

-- ---- 3. groups: everyone says which group they belong to; the groups are compared by the XP per person ----

alter table public.profiles add column if not exists grp text
  check (grp is null or grp in ('medstud', 'doctor', 'dental', 'nursing', 'physio', 'ems', 'health', 'self'));
grant update (name, public, grp) on public.profiles to authenticated;

-- a new account: also its group, when the app sends a known one
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v text; g text := new.raw_user_meta_data ->> 'grp';
begin
  v := btrim(coalesce(new.raw_user_meta_data ->> 'nickname',
                      split_part(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''), ' ', 1)));
  if char_length(v) < 2 then v := 'Anatomie-Fan'; end if;
  if g is null or g not in ('medstud', 'doctor', 'dental', 'nursing', 'physio', 'ems', 'health', 'self') then g := null; end if;
  insert into public.profiles (id, name, friend_code, grp) values (new.id, left(v, 24), public.new_friend_code(), g);
  return new;
end $$;

-- the groups compared (period 'week' or 'all'): per group the people who learnt (shown accounts with XP above 0),
-- their XP together and the XP per person; the groups in order of XP per person (then together). Also my group, my
-- place in it and the first 10 of it (shown accounts and me).
create or replace function public.group_board(period text) returns json
language sql stable security definer set search_path = '' as $$
  with cur as (select date_trunc('week', public.berlin_today())::date ws, public.berlin_today() td),
  v as (
    select s.user_id, p.name, p.public, p.grp,
           case when period = 'week' then case when s.week_start = (select ws from cur) then s.week_xp else 0 end else s.xp end val,
           case when s.last_day >= to_char((select td from cur) - 1, 'YYYY-MM-DD') then s.streak else 0 end streak
      from public.stats s join public.profiles p on p.id = s.user_id
     where p.grp is not null
  ),
  mine as (select grp from public.profiles where id = auth.uid()),
  g as (select grp, count(*) n, sum(val) total, round(avg(val))::bigint per from v where val > 0 and public group by grp),
  gr as (select grp, n, total, per, rank() over (order by per desc, total desc) rk from g),
  mem as (select user_id, name, val, streak, rank() over (order by val desc) rk from v
           where grp = (select grp from mine) and val > 0 and (public or user_id = auth.uid()))
  select json_build_object(
    'mine', (select grp from mine),
    'groups', coalesce((select json_agg(json_build_object('grp', grp, 'n', n, 'total', total, 'per', per, 'rank', rk) order by rk, grp) from gr), '[]'::json),
    'me', (select json_build_object('rank', rk, 'value', val) from mem where user_id = auth.uid()),
    'size', (select count(*) from mem),
    'top', coalesce((select json_agg(json_build_object('rank', t.rk, 'name', t.name, 'value', t.val, 'streak', t.streak, 'me', t.user_id = auth.uid()) order by t.rk, t.name)
                       from (select * from mem order by rk, name limit 10) t), '[]'::json))
  where auth.uid() is not null;
$$;
revoke execute on function public.group_board(text) from public, anon;
grant execute on function public.group_board(text) to authenticated;
