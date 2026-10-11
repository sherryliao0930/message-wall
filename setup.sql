-- 活動留言牆：資料表設定
-- 貼到 Supabase Dashboard → SQL Editor → Run，執行一次即可（重跑也不會出錯）。
-- 專案：qdpklfsrgdtgbsutckib（與互動文字雲同一個）

-- 1. 留言
create table if not exists public.wall_messages (
  id         bigint generated always as identity primary key,
  room       text        not null default 'default',
  name       text,
  body       text        not null,
  mood       text,
  keyword    text,
  hidden     boolean     not null default false,
  created_at timestamptz not null default now()
);
create index if not exists wall_messages_room_idx on public.wall_messages (room, id desc);

-- 2. 心情 emoji（手機端每 0.5 秒合併成一筆，n = 這段時間按了幾下）
create table if not exists public.wall_reactions (
  id         bigint generated always as identity primary key,
  room       text        not null default 'default',
  emoji      text        not null,
  n          int         not null default 1,
  created_at timestamptz not null default now()
);
create index if not exists wall_reactions_room_idx on public.wall_reactions (room);

-- 3. 各 emoji 的總數（牆一打開就要知道累計多少，不必把每一筆都撈回來）
create or replace view public.wall_reaction_totals
with (security_invoker = on) as
  select room, emoji, sum(n)::bigint as total
  from public.wall_reactions
  group by room, emoji;

-- 4. 權限：來賓（anon）可讀、可新增；留言只有 hidden 欄位可以改（牆上「移除」用）
alter table public.wall_messages  enable row level security;
alter table public.wall_reactions enable row level security;

drop policy if exists "wall_messages read"   on public.wall_messages;
drop policy if exists "wall_messages insert" on public.wall_messages;
drop policy if exists "wall_messages hide"   on public.wall_messages;
create policy "wall_messages read"   on public.wall_messages for select to anon, authenticated using (true);
create policy "wall_messages insert" on public.wall_messages for insert to anon, authenticated
  with check (
    char_length(body) between 1 and 140
    and coalesce(char_length(name), 0)    <= 20
    and coalesce(char_length(keyword), 0) <= 12
    and coalesce(char_length(mood), 0)    <= 16
    and char_length(room) <= 40
    and hidden = false
  );
create policy "wall_messages hide"   on public.wall_messages for update to anon, authenticated using (true) with check (true);

drop policy if exists "wall_reactions read"   on public.wall_reactions;
drop policy if exists "wall_reactions insert" on public.wall_reactions;
create policy "wall_reactions read"   on public.wall_reactions for select to anon, authenticated using (true);
create policy "wall_reactions insert" on public.wall_reactions for insert to anon, authenticated
  with check (n between 1 and 40 and char_length(emoji) <= 16 and char_length(room) <= 40);

grant select, insert on public.wall_messages  to anon, authenticated;
grant select, insert on public.wall_reactions to anon, authenticated;
revoke update on public.wall_messages from anon, authenticated;
grant update (hidden) on public.wall_messages to anon, authenticated;
grant select on public.wall_reaction_totals to anon, authenticated;

-- 5. 即時推播
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'wall_messages') then
    alter publication supabase_realtime add table public.wall_messages;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'wall_reactions') then
    alter publication supabase_realtime add table public.wall_reactions;
  end if;
end $$;
