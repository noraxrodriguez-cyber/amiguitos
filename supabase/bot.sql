-- Monedas por escribir en el chat de Discord. Sistema aparte de la economía.
-- Ejecutar en el SQL Editor después de schema.sql.

create table if not exists public.monedas_chat (
  discord_id text primary key,
  nombre text not null,
  monedas int not null default 0,
  ultimo timestamptz not null default 'epoch'
);
alter table public.monedas_chat enable row level security;
revoke all on public.monedas_chat from anon, authenticated;

-- Lo llama el bot con la clave secreta. Enfriamiento de 5 s para evitar spam.
create or replace function public.sumar_moneda(p_discord_id text, p_nombre text)
returns int
language plpgsql security definer set search_path = public as $$
declare total int;
begin
  insert into public.monedas_chat (discord_id, nombre, monedas, ultimo)
  values (p_discord_id, left(p_nombre, 30), 1, now())
  on conflict (discord_id) do update
    set nombre = excluded.nombre,
        monedas = public.monedas_chat.monedas + 1,
        ultimo = now()
    where public.monedas_chat.ultimo < now() - interval '5 seconds'
  returning monedas into total;
  return total; -- null si estaba en enfriamiento
end;
$$;
revoke execute on function public.sumar_moneda(text, text) from public, anon, authenticated;
grant execute on function public.sumar_moneda(text, text) to service_role;

-- Tus monedas de chat, según tu cuenta de Discord.
create or replace function public.mis_monedas_chat() returns int
language sql stable security definer set search_path = public as $$
  select coalesce((
    select m.monedas from public.monedas_chat m
    join auth.identities i on i.provider_id = m.discord_id
    where i.user_id = auth.uid() and i.provider = 'discord'
  ), 0);
$$;
revoke execute on function public.mis_monedas_chat() from public, anon;
grant execute on function public.mis_monedas_chat() to authenticated;

-- Ranking público: solo nombre y monedas, sin ids de Discord.
create or replace view public.ranking_chat as
  select nombre, monedas from public.monedas_chat order by monedas desc limit 50;
revoke all on public.ranking_chat from anon, authenticated;
grant select on public.ranking_chat to authenticated;
