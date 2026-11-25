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
