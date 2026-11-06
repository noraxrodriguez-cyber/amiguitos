-- Voz del bot desde la web. Solo el dueño puede enviar textos.
-- Ejecutar en el SQL Editor después de bot.sql.

create table if not exists public.config (
  clave text primary key,
  valor text not null
);
alter table public.config enable row level security;
revoke all on public.config from anon, authenticated;

-- IMPORTANTE: pon tu ID de usuario de Discord (Modo desarrollador → clic derecho en tu nombre → Copiar ID de usuario).
-- insert into public.config (clave, valor) values ('dueno_discord', 'TU_ID_DE_DISCORD')
--   on conflict (clave) do update set valor = excluded.valor;

create table if not exists public.voz_pendiente (
  id bigserial primary key,
  texto text not null check (char_length(texto) between 1 and 200),
  creado timestamptz not null default now(),
  hecho boolean not null default false
);
alter table public.voz_pendiente enable row level security;
revoke all on public.voz_pendiente from anon, authenticated;

create or replace function public.soy_dueno() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from auth.identities i
    join public.config c on c.clave = 'dueno_discord' and c.valor = i.provider_id
    where i.user_id = auth.uid() and i.provider = 'discord'
  );
$$;
revoke execute on function public.soy_dueno() from public, anon;
grant execute on function public.soy_dueno() to authenticated;

create or replace function public.enviar_voz(p_texto text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.soy_dueno() then raise exception 'Solo el dueño puede usar la voz'; end if;
  insert into public.voz_pendiente (texto) values (left(trim(p_texto), 200));
end;
$$;
revoke execute on function public.enviar_voz(text) from public, anon;
grant execute on function public.enviar_voz(text) to authenticated;
