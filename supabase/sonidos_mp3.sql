-- Subida de mp3 de sonidos (solo el dueño). Ejecutar después de sonidos.sql.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sonidos', 'sonidos', false, 2097152, array['audio/mpeg'])
on conflict (id) do update
  set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy "dueno lee sonidos" on storage.objects for select to authenticated
  using (bucket_id = 'sonidos' and public.soy_dueno());
create policy "dueno sube sonidos" on storage.objects for insert to authenticated
  with check (bucket_id = 'sonidos' and public.soy_dueno());
create policy "dueno cambia sonidos" on storage.objects for update to authenticated
  using (bucket_id = 'sonidos' and public.soy_dueno())
  with check (bucket_id = 'sonidos' and public.soy_dueno());
create policy "dueno borra sonidos" on storage.objects for delete to authenticated
  using (bucket_id = 'sonidos' and public.soy_dueno());
