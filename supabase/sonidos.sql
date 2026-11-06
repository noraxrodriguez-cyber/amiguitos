-- Sonidos del bot desde la web. Solo el dueño. Ejecutar después de voz.sql.
create table if not exists public.sonido_pendiente (
  id bigserial primary key,
  archivo text not null check (char_length(archivo) between 1 and 80),
  creado timestamptz not null default now(),
  hecho boolean not null default false
);
alter table public.sonido_pendiente enable row level security;
revoke all on public.sonido_pendiente from anon, authenticated;

create or replace function public.pedir_sonido(p_archivo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.soy_dueno() then raise exception 'Solo el dueño puede usar los sonidos'; end if;
  insert into public.sonido_pendiente (archivo) values (left(p_archivo, 80));
end;
$$;
revoke execute on function public.pedir_sonido(text) from public, anon;
grant execute on function public.pedir_sonido(text) to authenticated;
