-- 活動留言牆：照片功能（在 setup.sql 之後執行，執行一次即可，重跑也不會出錯）
-- 貼到 Supabase Dashboard → SQL Editor → Run

-- 1. 留言多一個欄位放照片網址
alter table public.wall_messages add column if not exists image_url text;

drop policy if exists "wall_messages insert" on public.wall_messages;
create policy "wall_messages insert" on public.wall_messages for insert to anon, authenticated
  with check (
    char_length(body) between 1 and 140
    and coalesce(char_length(name), 0)    <= 20
    and coalesce(char_length(keyword), 0) <= 12
    and coalesce(char_length(mood), 0)    <= 16
    and char_length(room) <= 40
    and hidden = false
    -- 照片只能是本專案 wall-photos 儲存空間裡的檔案
    and (image_url is null or image_url like 'https://qdpklfsrgdtgbsutckib.supabase.co/storage/v1/object/public/wall-photos/%')
  );

-- 2. 照片儲存空間：公開可看；只收 jpg / png / webp，單檔上限 3MB
--    （手機端會先壓縮到長邊 1280px，一張大約 150–400KB）
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('wall-photos', 'wall-photos', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = 3145728, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

-- 3. 來賓可以上傳到 wall-photos，但不能覆蓋或刪除別人的檔案
drop policy if exists "wall photos upload" on storage.objects;
drop policy if exists "wall photos read"   on storage.objects;
create policy "wall photos upload" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'wall-photos');
create policy "wall photos read"   on storage.objects for select to anon, authenticated
  using (bucket_id = 'wall-photos');
