-- AMIGUITOS · Sim económico · esquema y lógica del servidor (Supabase / Postgres)
-- Ejecutar entero en Supabase → SQL Editor.
-- Principio: nadie modifica saldos ni impuestos directamente. Todo pasa por funciones
-- que comprueban quién eres (auth.uid()) y las reglas del juego.

-- ============ Tablas ============

create table if not exists public.perfiles (
  id                   uuid primary key references auth.users(id) on delete cascade,
  nombre               text not null default 'Jugador',
  saldo                numeric not null default 300,
  sucio                numeric not null default 0,
  ultimo_trabajo       timestamptz not null default to_timestamp(0),
  ultimo_trabajo_sucio timestamptz not null default to_timestamp(0),
  dia_procesado        int not null default 0,
  escudo_hasta         int not null default 0,
  inventario           text[] not null default '{}',
  empresas             jsonb not null default '[]',
  lavados              jsonb not null default '[]'
);

create table if not exists public.gobierno (
  id              int primary key default 1 check (id = 1),
  inicio          timestamptz not null default now(),
  tesoro          numeric not null default 1000,
  impuestos       jsonb not null default '{"renta":15,"sociedades":20,"iva":10}',
  auditoria       int not null default 10 check (auditoria between 0 and 30),
  gobernador      uuid references public.perfiles(id),
  gobernador_nombre text not null default 'Gobierno inicial',
  mes_cerrado     int not null default 0,
  cambios_mes     int not null default 0
);
insert into public.gobierno (id) values (1) on conflict (id) do nothing;

create table if not exists public.candidatos (
  mes        int not null,
  candidato  uuid not null references public.perfiles(id) on delete cascade,
  nombre     text not null default 'Candidato',
  plat       jsonb not null,
  primary key (mes, candidato)
);

create table if not exists public.votos (
  mes       int not null,
  votante   uuid not null references public.perfiles(id) on delete cascade,
  candidato uuid not null references public.perfiles(id) on delete cascade,
  primary key (mes, votante)
);

-- ============ Utilidades de tiempo y sectores ============

-- 1 día de juego = 1 día real desde el inicio de la partida
create or replace function public.dia_actual() returns int
language sql stable as $$
  select (floor(extract(epoch from (now() - inicio)) / 86400))::int + 1
  from public.gobierno where id = 1;
$$;

-- 7 días de juego = 1 mes (una semana real)
create or replace function public.mes_de(d int) returns int
language sql immutable as $$
  select ((d - 1) / 7) + 1;
$$;

create or replace function public.base_sector(s text) returns numeric
language sql immutable as $$
  select case s
    when 'Panadería' then 120
    when 'Tecnología' then 220
    when 'Bar' then 140
    when 'Tienda de memes' then 180
    when 'Taller' then 160
    else null end;
$$;

-- ============ Cierre de mes: resuelve la elección ============

create or replace function public.cerrar_mes(p_mes int) returns void
language plpgsql security definer set search_path = public as $$
declare
  g public.gobierno%rowtype;
  ganador uuid;
  plat jsonb;
  nombre text;
begin
  select * into g from public.gobierno where id = 1 for update;
  if g.mes_cerrado >= p_mes then return; end if;

  select v.candidato into ganador
  from public.votos v
  where v.mes = p_mes
  group by v.candidato
  order by count(*) desc
  limit 1;

  if ganador is not null then
    select c.plat into plat from public.candidatos c where c.mes = p_mes and c.candidato = ganador;
    select p.nombre into nombre from public.perfiles p where p.id = ganador;
    update public.gobierno
       set gobernador = ganador, gobernador_nombre = nombre, impuestos = plat
     where id = 1;
  end if;

  update public.gobierno set mes_cerrado = p_mes, cambios_mes = 0 where id = 1;
end;
$$;

-- ============ Ponerse al día: procesa los días pasados del jugador ============

create or replace function public.ponerse_al_dia() returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p public.perfiles%rowtype;
  hoy int;
  d int;
  imp jsonb;
  e jsonb;
  x jsonb;
  l jsonb;
  nuevos jsonb;
  prod numeric;
  soc numeric;
  ren numeric;
  neto numeric;
  riesgo numeric;
  monto numeric;
  dias int;
begin
  if uid is null then raise exception 'Inicia sesión para jugar'; end if;
  select * into p from public.perfiles where id = uid for update;
  if not found then raise exception 'No tienes perfil'; end if;

  hoy := public.dia_actual();
  if p.dia_procesado >= hoy - 1 then return; end if;

  for d in (p.dia_procesado + 1) .. (hoy - 1) loop
    -- Cambio de mes: se cierra el anterior y cobras subsidio
    if d > 1 and public.mes_de(d) > public.mes_de(d - 1) then
      perform public.cerrar_mes(public.mes_de(d) - 1);
      update public.gobierno set tesoro = tesoro - 50 where id = 1 and tesoro >= 50;
      if found then p.saldo := p.saldo + 50; end if;
    end if;

    select impuestos into imp from public.gobierno where id = 1;

    -- Producción diaria de cada empresa
    for e in select value from jsonb_array_elements(p.empresas) loop
      prod := public.base_sector(e->>'sector') / 30 * (e->>'nivel')::int * 0.9
              * case when (e->>'maq')::boolean then 1.25 else 1 end
              * case when (e->>'ilegal')::boolean then 1.4 else 1 end;
      soc := greatest(0, (imp->>'sociedades')::numeric - case when (e->>'contable')::boolean then 5 else 0 end);
      ren := (imp->>'renta')::numeric;
      neto := prod * (1 - soc / 100) * (1 - ren / 100);
      p.saldo := p.saldo + neto;
      update public.gobierno set tesoro = tesoro + (prod - neto) where id = 1;
    end loop;

    -- Blanqueos en curso: riesgo de auditoría según el gobernador
    select auditoria / 100.0 * 0.5 * case when p.escudo_hasta > d then 0.5 else 1 end
      into riesgo from public.gobierno where id = 1;

    nuevos := '[]'::jsonb;
    for l in select value from jsonb_array_elements(p.lavados) loop
      monto := (l->>'monto')::numeric;
      dias := (l->>'dias')::int;
      if random() < riesgo then
        -- Te pillan: se confisca el dinero y pagas multa del 20 %
        update public.gobierno set tesoro = tesoro + monto + p.saldo * 0.2 where id = 1;
        p.saldo := p.saldo * 0.8;
      elsif dias - 1 <= 0 then
        -- Blanqueo completado: 70 % limpio, 30 % comisión
        p.saldo := p.saldo + monto * 0.7;
        update public.gobierno set tesoro = tesoro + monto * 0.3 where id = 1;
      else
        nuevos := nuevos || jsonb_build_array(jsonb_build_object('monto', monto, 'dias', dias - 1));
      end if;
    end loop;
    p.lavados := nuevos;
  end loop;

  update public.perfiles
     set saldo = p.saldo, sucio = p.sucio, lavados = p.lavados, empresas = p.empresas, dia_procesado = hoy - 1
   where id = uid;
end;
$$;

-- ============ Acciones del jugador ============

create or replace function public.trabajar() returns numeric
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p public.perfiles%rowtype;
  ren numeric;
  bruto numeric;
  neto numeric;
begin
  perform public.ponerse_al_dia();
  select * into p from public.perfiles where id = uid for update;
  if now() - p.ultimo_trabajo < interval '20 minutes' then
    raise exception 'Espera antes de volver a trabajar';
  end if;
  select (impuestos->>'renta')::numeric into ren from public.gobierno where id = 1;
  bruto := 40 + floor(random() * 41);
  neto := bruto * (1 - ren / 100);
  update public.gobierno set tesoro = tesoro + (bruto - neto) where id = 1;
  update public.perfiles set saldo = saldo + neto, ultimo_trabajo = now() where id = uid;
  return neto;
end;
$$;

create or replace function public.trabajo_sucio() returns numeric
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p public.perfiles%rowtype;
  ganado numeric := 0;
begin
  perform public.ponerse_al_dia();
  select * into p from public.perfiles where id = uid for update;
  if now() - p.ultimo_trabajo_sucio < interval '30 minutes' then
    raise exception 'Espera antes de otro trabajo sucio';
  end if;
  if random() < 0.2 then
    update public.perfiles set saldo = greatest(0, saldo - 100),
           ultimo_trabajo_sucio = now() where id = uid;
    update public.gobierno set tesoro = tesoro + least(100, p.saldo) where id = 1;
  else
    ganado := 100 + floor(random() * 151);
    update public.perfiles set sucio = sucio + ganado, ultimo_trabajo_sucio = now() where id = uid;
  end if;
  return ganado;
end;
$$;

create or replace function public.lavar(monto numeric) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p public.perfiles%rowtype;
begin
  perform public.ponerse_al_dia();
  select * into p from public.perfiles where id = uid for update;
  if monto is null or monto <= 0 then raise exception 'Cantidad no válida'; end if;
  if monto > p.sucio then raise exception 'No tienes tanto dinero sucio'; end if;
  update public.perfiles
     set sucio = sucio - monto,
         lavados = lavados || jsonb_build_array(jsonb_build_object('monto', monto, 'dias', 5))
   where id = uid;
end;
$$;

create or replace function public.fundar(p_nombre text, p_sector text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p public.perfiles%rowtype;
begin
  perform public.ponerse_al_dia();
  select * into p from public.perfiles where id = uid for update;
  if public.base_sector(p_sector) is null then raise exception 'Sector no válido'; end if;
  if p.saldo < 500 then raise exception 'Necesitas 500 monedas para fundar'; end if;
  update public.perfiles
     set saldo = saldo - 500,
         empresas = empresas || jsonb_build_array(jsonb_build_object(
           'id', gen_random_uuid()::text, 'nombre', left(p_nombre, 30), 'sector', p_sector,
           'nivel', 1, 'maq', false, 'contable', false, 'ilegal', false))
   where id = uid;
end;
$$;

-- tipo: 'nivel' (300 × nivel), 'maq' (350), 'contable' (250), 'ilegal' (500)
create or replace function public.mejorar(p_empresa text, p_tipo text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p public.perfiles%rowtype;
  e jsonb;
  x jsonb;
  coste numeric;
  nuevos jsonb := '[]'::jsonb;
  encontrada boolean := false;
begin
  perform public.ponerse_al_dia();
  select * into p from public.perfiles where id = uid for update;
  for e in select value from jsonb_array_elements(p.empresas) loop
    x := e;
    if e->>'id' = p_empresa then
      encontrada := true;
      if p_tipo = 'nivel' then
        coste := 300 * (e->>'nivel')::int;
        x := jsonb_set(e, '{nivel}', to_jsonb((e->>'nivel')::int + 1));
      elsif p_tipo in ('maq', 'contable', 'ilegal') then
        if (e->>p_tipo)::boolean then raise exception 'Ya la tiene'; end if;
        coste := case p_tipo when 'maq' then 350 when 'contable' then 250 else 500 end;
        x := jsonb_set(e, array[p_tipo], 'true');
      else
        raise exception 'Mejora desconocida';
      end if;
      if p.saldo < coste then raise exception 'No tienes % monedas', coste; end if;
      p.saldo := p.saldo - coste;
    end if;
    nuevos := nuevos || jsonb_build_array(x);
  end loop;
  if not encontrada then raise exception 'No tienes esa empresa'; end if;
  update public.perfiles set saldo = p.saldo, empresas = nuevos where id = uid;
end;
$$;

create or replace function public.presentarse() returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  mes_actual int;
  p public.perfiles%rowtype;
begin
  perform public.ponerse_al_dia();
  select * into p from public.perfiles where id = uid for update;
  mes_actual := public.mes_de(public.dia_actual());
  if p.saldo < 200 then raise exception 'Presentarse cuesta 200 monedas'; end if;
  insert into public.candidatos (mes, candidato, nombre, plat)
  select mes_actual, uid, p.nombre, g.impuestos
  from public.gobierno g, public.perfiles p
  where g.id = 1 and p.id = uid
  on conflict do nothing;
  if found then
    update public.perfiles set saldo = saldo - 200 where id = uid;
    update public.gobierno set tesoro = tesoro + 200 where id = 1;
  else
    raise exception 'Ya te has presentado este mes';
  end if;
end;
$$;

create or replace function public.votar(p_candidato uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  mes_actual int;
begin
  perform public.ponerse_al_dia();
  mes_actual := public.mes_de(public.dia_actual());
  if not exists (select 1 from public.candidatos where mes = mes_actual and candidato = p_candidato) then
    raise exception 'Esa persona no es candidata este mes';
  end if;
  if exists (select 1 from public.votos where mes = mes_actual and votante = uid) then
    raise exception 'Ya has votado este mes';
  end if;
  insert into public.votos (mes, votante, candidato) values (mes_actual, uid, p_candidato);
end;
$$;

create or replace function public.comprar_oscuro(p_item text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p public.perfiles%rowtype;
begin
  perform public.ponerse_al_dia();
  select * into p from public.perfiles where id = uid for update;
  if p_item = 'escudo' then
    if p.saldo < 300 then raise exception 'Cuesta 300 monedas'; end if;
    update public.perfiles set saldo = saldo - 300,
           escudo_hasta = public.dia_actual() + 7 where id = uid;
    update public.gobierno set tesoro = tesoro + 300 where id = 1;
  else
    raise exception 'Artículo no disponible';
  end if;
end;
$$;

-- ============ Gobierno (solo el gobernador) ============

create or replace function public.cambiar_impuesto(p_tipo text, p_valor numeric) returns void
language plpgsql security definer set search_path = public as $$
declare
  g public.gobierno%rowtype;
begin
  select * into g from public.gobierno where id = 1 for update;
  if g.gobernador is distinct from auth.uid() then raise exception 'Solo el gobernador puede cambiar impuestos'; end if;
  if g.cambios_mes >= 1 then raise exception 'Solo un cambio de impuestos al mes'; end if;
  if p_tipo not in ('renta', 'sociedades', 'iva') then raise exception 'Impuesto no válido'; end if;
  if p_valor < 0 or p_valor > 40 then raise exception 'Entre 0 y 40 por ciento'; end if;
  update public.gobierno
     set impuestos = jsonb_set(impuestos, array[p_tipo], to_jsonb(p_valor)),
         cambios_mes = cambios_mes + 1
   where id = 1;
end;
$$;

create or replace function public.cambiar_auditoria(p_valor int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if (select gobernador from public.gobierno where id = 1) is distinct from auth.uid() then
    raise exception 'Solo el gobernador puede auditar';
  end if;
  if p_valor < 0 or p_valor > 30 then raise exception 'Entre 0 y 30 por ciento'; end if;
  update public.gobierno set auditoria = p_valor where id = 1;
end;
$$;

-- ============ Perfil automático al entrar con Discord ============

create or replace function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (id, nombre)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Jugador'))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario after insert on auth.users
  for each row execute function public.crear_perfil();

-- ============ Permisos (RLS) ============

alter table public.perfiles enable row level security;
alter table public.gobierno enable row level security;
alter table public.candidatos enable row level security;
alter table public.votos enable row level security;

-- Cada jugador ve SU perfil completo (con su dinero sucio)
create policy "ver mi perfil" on public.perfiles for select to authenticated using (id = auth.uid());
-- El estado del gobierno y los candidatos son públicos para jugadores
create policy "ver gobierno" on public.gobierno for select to authenticated using (true);
create policy "ver candidatos" on public.candidatos for select to authenticated using (true);
-- Los votos NO se ven hasta el cierre (voto secreto): sin política de lectura.

-- Ranking público: solo nombre y saldo, sin dinero sucio
create or replace view public.ranking as
  select nombre, saldo from public.perfiles order by saldo desc limit 20;
grant select on public.ranking to authenticated, anon;

-- Nadie escribe tablas directamente: solo las funciones de arriba
revoke all on public.perfiles, public.gobierno, public.candidatos, public.votos from anon, authenticated;
grant select on public.gobierno, public.candidatos to authenticated;
grant select on public.perfiles to authenticated;

grant execute on function
  public.ponerse_al_dia, public.trabajar, public.trabajo_sucio, public.lavar,
  public.fundar, public.mejorar, public.presentarse, public.votar,
  public.comprar_oscuro, public.cambiar_impuesto, public.cambiar_auditoria, public.dia_actual
  to authenticated;
