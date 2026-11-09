-- AMIGUITOS v2 · economía ampliada, panel de admin y arreglos
-- Ejecutar ENTERO en Supabase → SQL Editor, después de schema.sql, bot.sql, voz.sql y sonidos.sql.
-- Se puede ejecutar varias veces: no borra datos ni pisa los ajustes que haya cambiado el admin.
--
-- Reglas de este archivo:
--   · Nadie toca tablas desde la web. Todo pasa por funciones que comprueban quién eres.
--   · Las funciones que empiezan por "_" son internas y la web no puede llamarlas.
--   · Las que empiezan por "admin_" solo funcionan para el dueño (config.dueno_discord).

-- =====================================================================
-- 1. Tablas y columnas nuevas
-- =====================================================================

alter table public.perfiles
  add column if not exists banco           numeric not null default 0,
  add column if not exists cripto          numeric not null default 0,
  add column if not exists xp              int not null default 0,
  add column if not exists carcel_hasta    timestamptz not null default to_timestamp(0),
  add column if not exists candado_hasta   timestamptz not null default to_timestamp(0),
  add column if not exists baneado         boolean not null default false,
  add column if not exists ultimo_robo     timestamptz not null default to_timestamp(0),
  add column if not exists ultimo_mendigar timestamptz not null default to_timestamp(0),
  add column if not exists ultimo_diario   int not null default 0,
  add column if not exists racha           int not null default 0,
  add column if not exists cafe_dia        int not null default 0,
  add column if not exists cafe_n          int not null default 0,
  add column if not exists mote            text,
  add column if not exists mote_hasta      timestamptz not null default to_timestamp(0),
  add column if not exists creado          timestamptz not null default now();

alter table public.gobierno
  add column if not exists dia_global     int not null default 0,
  add column if not exists evento         text not null default '',
  add column if not exists evento_fin     timestamptz not null default to_timestamp(0),
  add column if not exists bote           numeric not null default 0,
  add column if not exists decreto        text not null default '',
  add column if not exists malversado_dia int not null default 0;

-- El admin puede poner la auditoría hasta 100; el gobernador sigue limitado a 30 en su función.
alter table public.gobierno drop constraint if exists gobierno_auditoria_check;
alter table public.gobierno add constraint gobierno_auditoria_check check (auditoria between 0 and 100);

alter table public.candidatos
  add column if not exists lema      text not null default '',
  add column if not exists comprados int not null default 0;

alter table public.monedas_chat
  add column if not exists gastadas int not null default 0;

-- Todos los números del juego. El admin los cambia desde la web.
create table if not exists public.ajustes (
  clave   text primary key,
  valor   numeric not null,
  defecto numeric not null,
  grupo   text not null,
  nombre  text not null,
  minimo  numeric not null default 0,
  maximo  numeric not null default 1000000
);

create table if not exists public.sectores (
  nombre text primary key check (char_length(nombre) between 1 and 30),
  base   numeric not null check (base between 0 and 100000),
  icono  text not null default '🏢'
);

create table if not exists public.noticias (
  id     bigserial primary key,
  creado timestamptz not null default now(),
  icono  text not null default '📰',
  titulo text not null,
  texto  text not null default '',
  auto   boolean not null default true,   -- true: la generó el juego; false: la escribió el admin
  fija   boolean not null default false
);

create table if not exists public.avisos (
  id      bigserial primary key,
  jugador uuid not null references public.perfiles(id) on delete cascade,
  creado  timestamptz not null default now(),
  icono   text not null default '🔔',
  texto   text not null,
  tipo    text not null default 'info',   -- 'info' o 'tarta'
  leido   boolean not null default false
);
create index if not exists avisos_jugador on public.avisos (jugador, leido, id desc);

create table if not exists public.loteria (
  dia     int not null,
  jugador uuid not null references public.perfiles(id) on delete cascade,
  boletos int not null check (boletos > 0),
  primary key (dia, jugador)
);

create table if not exists public.eventos_dia (
  dia    int primary key,
  evento text not null
);

create table if not exists public.mercado (
  id          int primary key default 1 check (id = 1),
  precio      numeric not null default 100,
  actualizado timestamptz not null default now(),
  historial   jsonb not null default '[100]'
);
insert into public.mercado (id) values (1) on conflict (id) do nothing;

alter table public.ajustes     enable row level security;
alter table public.sectores    enable row level security;
alter table public.noticias    enable row level security;
alter table public.avisos      enable row level security;
alter table public.loteria     enable row level security;
alter table public.eventos_dia enable row level security;
alter table public.mercado     enable row level security;
revoke all on public.ajustes, public.sectores, public.noticias, public.avisos,
              public.loteria, public.eventos_dia, public.mercado from anon, authenticated;

-- Valores de fábrica. Si ya existen, solo se actualizan nombre y límites, no el valor.
insert into public.ajustes (clave, valor, defecto, grupo, nombre, minimo, maximo)
select clave, valor, valor, grupo, nombre, minimo, maximo from (values
  ('saldo_inicial',     300, 'General',  'Saldo con el que empieza un jugador nuevo', 0, 100000),
  ('subsidio',           50, 'General',  'Subsidio semanal por jugador (sale del tesoro)', 0, 10000),
  ('evento_prob',        30, 'General',  'Probabilidad diaria de evento aleatorio (%)', 0, 100),
  ('canje_chat',          1, 'General',  'Monedas del juego por cada moneda de chat', 0, 1000),

  ('sueldo_min',         40, 'Trabajo',  'Sueldo mínimo por trabajar', 0, 100000),
  ('sueldo_max',         80, 'Trabajo',  'Sueldo máximo por trabajar', 0, 100000),
  ('cd_trabajo',         20, 'Trabajo',  'Espera entre trabajos (minutos)', 0, 1440),
  ('bonus_nivel',         5, 'Trabajo',  'Subida de sueldo por nivel (%)', 0, 100),
  ('cafes_dia',           3, 'Trabajo',  'Cafés que se pueden tomar al día', 0, 100),
  ('mendigar_max',       15, 'Trabajo',  'Máximo que cae al mendigar', 0, 10000),
  ('mendigar_tope',     300, 'Trabajo',  'Con más dinero que esto no puedes mendigar', 0, 1000000),
  ('cd_mendigar',         5, 'Trabajo',  'Espera entre mendigar (minutos)', 0, 1440),
  ('diario_base',        60, 'Trabajo',  'Paga diaria base', 0, 100000),
  ('diario_racha',       15, 'Trabajo',  'Extra por cada día seguido de racha', 0, 10000),
  ('diario_racha_max',    7, 'Trabajo',  'Días de racha que cuentan como máximo', 0, 365),

  ('coste_fundar',      500, 'Empresas', 'Coste de fundar una empresa', 0, 1000000),
  ('coste_nivel',       300, 'Empresas', 'Coste de subir nivel (se multiplica por el nivel)', 0, 1000000),
  ('coste_maq',         350, 'Empresas', 'Coste de la maquinaria', 0, 1000000),
  ('coste_contable',    250, 'Empresas', 'Coste de la contabilidad', 0, 1000000),
  ('coste_ilegal',      500, 'Empresas', 'Coste de la contabilidad B', 0, 1000000),
  ('nivel_max',          10, 'Empresas', 'Nivel máximo de una empresa', 1, 100),
  ('empresas_max',        5, 'Empresas', 'Empresas por jugador', 0, 50),
  ('venta_pct',          50, 'Empresas', 'Lo que recuperas al vender una empresa (%)', 0, 100),
  ('prod_pct',          100, 'Empresas', 'Producción global de las empresas (%)', 0, 1000),
  ('sabotaje_coste',    200, 'Empresas', 'Coste de un sabotaje (dinero sucio)', 0, 1000000),
  ('sabotaje_dias',       2, 'Empresas', 'Días que dura un sabotaje', 1, 30),
  ('sabotaje_riesgo',    25, 'Empresas', 'Probabilidad de que pillen al saboteador (%)', 0, 100),

  ('banco_interes',       1, 'Banco',    'Interés diario del banco (%), lo paga el tesoro', 0, 50),
  ('banco_tope',      20000, 'Banco',    'Saldo máximo que genera interés', 0, 100000000),

  ('sucio_min',         100, 'Crimen',   'Botín mínimo de un trabajo sucio', 0, 100000),
  ('sucio_max',         250, 'Crimen',   'Botín máximo de un trabajo sucio', 0, 100000),
  ('cd_sucio',           30, 'Crimen',   'Espera entre trabajos sucios (minutos)', 0, 1440),
  ('sucio_fallo',        20, 'Crimen',   'Probabilidad de que salga mal un trabajo sucio (%)', 0, 100),
  ('sucio_multa',       100, 'Crimen',   'Multa si sale mal un trabajo sucio', 0, 100000),
  ('cd_robo',            60, 'Crimen',   'Espera entre robos (minutos)', 0, 1440),
  ('robo_exito',         45, 'Crimen',   'Probabilidad de éxito al robar (%)', 0, 100),
  ('robo_pct',           15, 'Crimen',   'Parte máxima del dinero en mano que se roba (%)', 0, 100),
  ('robo_max',          500, 'Crimen',   'Botín máximo de un robo', 0, 1000000),
  ('robo_multa',        150, 'Crimen',   'Indemnización a la víctima si te pillan', 0, 100000),
  ('carcel_min',         30, 'Crimen',   'Minutos de cárcel', 0, 1440),
  ('fianza',            200, 'Crimen',   'Fianza para salir de la cárcel', 0, 1000000),
  ('lavado_dias',         5, 'Crimen',   'Días que tarda un blanqueo', 1, 60),
  ('lavado_comision',    30, 'Crimen',   'Comisión del blanqueo (%)', 0, 100),
  ('multa_pct',          20, 'Crimen',   'Multa de Hacienda sobre tu saldo si te pillan (%)', 0, 100),

  ('apuesta_max',       500, 'Casino',   'Apuesta máxima', 1, 1000000),
  ('moneda_prob',        48, 'Casino',   'Probabilidad de ganar al cara o cruz (%)', 0, 100),
  ('ruleta_premio',      20, 'Casino',   'Lo que ganas si sobrevives a la ruleta rusa (% de tu dinero en mano)', 0, 100),
  ('loteria_precio',     25, 'Casino',   'Precio del boleto de lotería', 1, 100000),
  ('loteria_casa',       10, 'Casino',   'Parte de cada boleto que se queda el tesoro (%)', 0, 100),
  ('loteria_max',        20, 'Casino',   'Boletos por jugador y día', 1, 1000),
  ('cripto_volatilidad',  6, 'Casino',   'Cuánto se mueve PanchoCoin cada 10 minutos (%)', 0, 50),
  ('cripto_comision',     2, 'Casino',   'Comisión al comprar o vender PanchoCoin (%)', 0, 50),

  ('coste_candidato',   200, 'Política', 'Coste de presentarse a gobernador', 0, 1000000),
  ('impuesto_max',       40, 'Política', 'Impuesto máximo que puede poner el gobernador (%)', 0, 100),
  ('voto_precio',       150, 'Política', 'Precio de un voto comprado (dinero sucio)', 0, 1000000),
  ('voto_riesgo',        15, 'Política', 'Probabilidad de que te pillen comprando votos (%)', 0, 100),
  ('malversar_riesgo',   35, 'Política', 'Probabilidad de que pillen al gobernador malversando (%)', 0, 100),
  ('malversar_pct',      25, 'Política', 'Parte máxima del tesoro que se puede malversar al día (%)', 0, 100),

  ('precio_cafe',        60, 'Tienda',   'Café: vuelves a trabajar ya', 0, 1000000),
  ('precio_candado',    120, 'Tienda',   'Candado: 24 h sin que te roben', 0, 1000000),
  ('precio_escudo',     300, 'Tienda',   'Abogado: 7 días con la mitad de riesgo', 0, 1000000),
  ('precio_chivatazo',  250, 'Tienda',   'Chivatazo a Hacienda', 0, 1000000),
  ('precio_mote',       150, 'Tienda',   'Ponerle un mote a alguien 24 h', 0, 1000000),
  ('precio_quitamote',  100, 'Tienda',   'Quitarte el mote', 0, 1000000),
  ('precio_tarta',       40, 'Tienda',   'Tartazo en la cara', 0, 1000000)
) as t(clave, valor, grupo, nombre, minimo, maximo)
on conflict (clave) do update
  set defecto = excluded.defecto, grupo = excluded.grupo, nombre = excluded.nombre,
      minimo = excluded.minimo, maximo = excluded.maximo;

-- base = monedas que produce al día una empresa de nivel 1, antes de impuestos.
insert into public.sectores (nombre, base, icono) values
  ('Panadería', 30, '🥖'), ('Criadero de patos', 32, '🦆'), ('Bar', 35, '🍺'), ('Kebab 24 h', 38, '🌯'),
  ('Taller', 40, '🔧'), ('Gimnasio', 42, '🏋️'), ('Tienda de memes', 45, '🐸'), ('Funeraria', 50, '⚰️'),
  ('Tecnología', 55, '💻'), ('Inmobiliaria', 65, '🏠')
on conflict (nombre) do nothing;

-- El reloj global empieza hoy: no se sortean ni se cierran días anteriores a esta versión.
update public.gobierno
   set dia_global = (floor(extract(epoch from (now() - inicio)) / 86400))::int + 1
 where id = 1 and dia_global = 0;

-- =====================================================================
-- 2. Se retiran las funciones antiguas que cambian de forma
-- =====================================================================

drop function if exists public.trabajar();
drop function if exists public.trabajo_sucio();
drop function if exists public.lavar(numeric);
drop function if exists public.fundar(text, text);
drop function if exists public.mejorar(text, text);
drop function if exists public.presentarse();
drop function if exists public.votar(uuid);
drop function if exists public.comprar_oscuro(text);
drop function if exists public.cambiar_impuesto(text, numeric);
drop function if exists public.cambiar_auditoria(int);
drop function if exists public.base_sector(text);

-- =====================================================================
-- 3. Utilidades internas
-- =====================================================================

create or replace function public.aj(p_clave text) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select valor from public.ajustes where clave = p_clave), 0);
$$;

-- Número redondeado para los mensajes.
create or replace function public._n(p_x numeric) returns text
language sql immutable as $$
  select round(coalesce(p_x, 0))::bigint::text;
$$;

create or replace function public._nivel(p_xp int) returns int
language sql immutable as $$
  select least(20, floor(sqrt(greatest(p_xp, 0) / 3.0)))::int;
$$;

create or replace function public._frase(p_frases text[]) returns text
language sql volatile as $$
  select p_frases[1 + floor(random() * array_length(p_frases, 1))::int];
$$;

create or replace function public._aviso(p_jugador uuid, p_icono text, p_texto text, p_tipo text default 'info') returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.avisos (jugador, icono, texto, tipo) values (p_jugador, p_icono, left(p_texto, 300), p_tipo);
  -- Cada jugador conserva solo sus 60 avisos más recientes.
  delete from public.avisos a where a.jugador = p_jugador
     and a.id <= (select b.id from public.avisos b where b.jugador = p_jugador order by b.id desc offset 60 limit 1);
end;
$$;

create or replace function public._noticia(p_icono text, p_titulo text, p_texto text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.noticias (icono, titulo, texto, auto) values (p_icono, left(p_titulo, 80), left(p_texto, 300), true);
  delete from public.noticias n where n.auto
     and n.id <= (select b.id from public.noticias b where b.auto order by b.id desc offset 200 limit 1);
end;
$$;

-- Evento activo ahora mismo ('' si no hay).
create or replace function public.ev() returns text
language sql stable security definer set search_path = public as $$
  select case when evento_fin > now() then evento else '' end from public.gobierno where id = 1;
$$;

-- Evento que hubo un día concreto (para la producción de las empresas).
create or replace function public._evd(p_dia int) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select evento from public.eventos_dia where dia = p_dia), '');
$$;

create or replace function public._evento_info(p_clave text) returns jsonb
language sql immutable as $$
  select case p_clave
    when 'huelga'   then '{"clave":"huelga","icono":"🪧","nombre":"Huelga general","texto":"Trabajar paga la mitad."}'
    when 'fiesta'   then '{"clave":"fiesta","icono":"🎉","nombre":"Fiestas del pueblo","texto":"Trabajar paga el doble."}'
    when 'burbuja'  then '{"clave":"burbuja","icono":"📈","nombre":"Burbuja","texto":"Las empresas producen el doble."}'
    when 'crisis'   then '{"clave":"crisis","icono":"📉","nombre":"Crisis","texto":"Las empresas producen la mitad."}'
    when 'redada'   then '{"clave":"redada","icono":"🚓","nombre":"Redada","texto":"Robos y trabajos sucios fallan el doble y Hacienda audita el doble."}'
    when 'amnistia' then '{"clave":"amnistia","icono":"🕊️","nombre":"Amnistía fiscal","texto":"Hoy no hay auditorías: blanquear es seguro."}'
    when 'apagon'   then '{"clave":"apagon","icono":"🔌","nombre":"Apagón","texto":"El casino y la bolsa están cerrados."}'
    else null end::jsonb;
$$;

create or replace function public._poner_evento(p_clave text, p_horas numeric) returns void
language plpgsql security definer set search_path = public as $$
declare v_info jsonb := public._evento_info(p_clave);
begin
  if v_info is null then raise exception 'Evento desconocido'; end if;
  update public.gobierno set evento = p_clave, evento_fin = now() + make_interval(secs => p_horas * 3600) where id = 1;
  insert into public.eventos_dia (dia, evento) values (public.dia_actual(), p_clave)
    on conflict (dia) do update set evento = excluded.evento;
  perform public._noticia(v_info->>'icono', v_info->>'nombre', v_info->>'texto');
end;
$$;

-- Crea el perfil si no existe (por si alguien entró antes de que existiera el disparador).
create or replace function public._asegurar_perfil() returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Inicia sesión para jugar'; end if;
  insert into public.perfiles (id, nombre, saldo, dia_procesado)
  select u.id,
         left(coalesce(nullif(u.raw_user_meta_data->'custom_claims'->>'global_name', ''),
                       nullif(u.raw_user_meta_data->>'full_name', ''),
                       nullif(u.raw_user_meta_data->>'name', ''), 'Jugador'), 30),
         public.aj('saldo_inicial'), greatest(0, public.dia_actual() - 1)
    from auth.users u where u.id = v_uid
  on conflict (id) do nothing;
end;
$$;

-- Un jugador nuevo empieza en el día de hoy: no cobra subsidios de semanas en las que no estaba.
create or replace function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    insert into public.perfiles (id, nombre, saldo, dia_procesado)
    values (new.id,
            left(coalesce(nullif(new.raw_user_meta_data->'custom_claims'->>'global_name', ''),
                          nullif(new.raw_user_meta_data->>'full_name', ''),
                          nullif(new.raw_user_meta_data->>'name', ''), 'Jugador'), 30),
            public.aj('saldo_inicial'), greatest(0, public.dia_actual() - 1))
    on conflict (id) do nothing;
  exception when others then
    null; -- nunca se bloquea el inicio de sesión; _asegurar_perfil lo crea después
  end;
  return new;
end;
$$;

-- Cobra p_base (más IVA si toca) del saldo limpio o del sucio. El IVA va al tesoro.
create or replace function public._pagar(p_uid uuid, p_base numeric, p_iva boolean, p_sucio boolean default false) returns numeric
language plpgsql security definer set search_path = public as $$
declare v_iva numeric := 0; v_total numeric; v_tengo numeric;
begin
  if p_iva then select (impuestos->>'iva')::numeric into v_iva from public.gobierno where id = 1; end if;
  v_total := round(p_base * (1 + coalesce(v_iva, 0) / 100));
  select case when p_sucio then sucio else saldo end into v_tengo from public.perfiles where id = p_uid;
  if v_tengo < v_total then
    raise exception 'Te faltan % monedas (cuesta % en dinero %)', public._n(v_total - v_tengo), public._n(v_total),
      case when p_sucio then 'sucio' else 'limpio' end;
  end if;
  if p_sucio then update public.perfiles set sucio = sucio - v_total where id = p_uid;
  else update public.perfiles set saldo = saldo - v_total where id = p_uid; end if;
  update public.gobierno set tesoro = tesoro + (v_total - p_base) where id = 1;
  return v_total;
end;
$$;

create or replace function public._admin() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.soy_dueno() then raise exception 'Solo el admin puede hacer esto'; end if;
end;
$$;

-- =====================================================================
-- 4. Reloj global: lotería, elecciones y eventos
-- =====================================================================

create or replace function public._sortear(p_dia int) returns void
language plpgsql security definer set search_path = public as $$
declare v_total int; v_pozo numeric; v_r numeric; v_acc int := 0; v_gan uuid; v_nom text; f record;
begin
  select coalesce(sum(boletos), 0) into v_total from public.loteria where dia <= p_dia;
  if v_total = 0 then return; end if;
  select bote into v_pozo from public.gobierno where id = 1;
  v_r := random() * v_total;
  for f in select jugador, sum(boletos)::int as boletos from public.loteria where dia <= p_dia group by jugador order by jugador loop
    v_acc := v_acc + f.boletos;
    v_gan := f.jugador;
    exit when v_r < v_acc;
  end loop;
  update public.perfiles set saldo = saldo + v_pozo where id = v_gan returning nombre into v_nom;
  update public.gobierno set bote = 0 where id = 1;
  delete from public.loteria where dia <= p_dia;
  perform public._aviso(v_gan, '🎟️', 'Te ha tocado la lotería: ' || public._n(v_pozo) || ' monedas.');
  perform public._noticia('🎟️', v_nom || ' gana la lotería', 'Se lleva un bote de ' || public._n(v_pozo) || ' monedas con ' || v_total || ' boletos vendidos.');
end;
$$;

-- Cuenta los votos (reales y comprados) y nombra gobernador. Si empatan, a suertes.
create or replace function public._resolver(p_mes int) returns void
language plpgsql security definer set search_path = public as $$
declare v_gan uuid; v_plat jsonb; v_nom text; v_votos int;
begin
  select c.candidato, c.plat, t.n into v_gan, v_plat, v_votos
    from public.candidatos c
    cross join lateral (select (c.comprados + (select count(*) from public.votos v
                                               where v.mes = c.mes and v.candidato = c.candidato))::int as n) t
   where c.mes = p_mes and t.n > 0
   order by t.n desc, random()
   limit 1;
  if v_gan is null then return; end if;
  select nombre into v_nom from public.perfiles where id = v_gan;
  update public.gobierno
     set gobernador = v_gan, gobernador_nombre = v_nom, impuestos = v_plat, cambios_mes = 0, decreto = ''
   where id = 1;
  perform public._noticia('👑', v_nom || ' gana las elecciones',
    format('Con %s votos. Impuestos nuevos: renta %s, sociedades %s, IVA %s.', v_votos, v_plat->>'renta', v_plat->>'sociedades', v_plat->>'iva'));
  perform public._aviso(v_gan, '👑', 'Has ganado las elecciones. Eres el nuevo gobernador.');
end;
$$;

create or replace function public.cerrar_mes(p_mes int) returns void
language plpgsql security definer set search_path = public as $$
declare g public.gobierno%rowtype;
begin
  select * into g from public.gobierno where id = 1 for update;
  if g.mes_cerrado >= p_mes then return; end if;
  perform public._resolver(p_mes);
  update public.gobierno set mes_cerrado = p_mes, cambios_mes = 0 where id = 1;
end;
$$;

create or replace function public.tick_global() returns void
language plpgsql security definer set search_path = public as $$
declare
  g public.gobierno%rowtype;
  v_hoy int := public.dia_actual();
  v_d int;
  v_claves text[] := array['huelga', 'fiesta', 'burbuja', 'crisis', 'redada', 'amnistia', 'apagon'];
begin
  if (select dia_global from public.gobierno where id = 1) >= v_hoy then return; end if;
  select * into g from public.gobierno where id = 1 for update;
  if g.dia_global >= v_hoy then return; end if;

  for v_d in greatest(g.dia_global + 1, v_hoy - 60) .. v_hoy loop
    perform public._sortear(v_d - 1);
    if v_d > 1 and public.mes_de(v_d) > public.mes_de(v_d - 1) then
      perform public.cerrar_mes(public.mes_de(v_d) - 1);
    end if;
  end loop;

  -- Evento del día: si sigue uno activo se apunta también para hoy; si no, puede salir uno nuevo.
  if g.evento_fin > now() and g.evento <> '' then
    insert into public.eventos_dia (dia, evento) values (v_hoy, g.evento) on conflict (dia) do nothing;
  elsif random() * 100 < public.aj('evento_prob') then
    perform public._poner_evento(public._frase(v_claves), 24);
  end if;

  delete from public.eventos_dia where dia < v_hoy - 90;
  update public.gobierno set dia_global = v_hoy where id = 1;
end;
$$;

-- =====================================================================
-- 5. Ponerse al día: lo que pasó mientras el jugador no miraba
-- =====================================================================

create or replace function public.ponerse_al_dia() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  p public.perfiles%rowtype;
  v_hoy int; v_d int; v_imp jsonb; v_aud int; v_evt text;
  e jsonb; l jsonb; v_nuevos jsonb;
  v_prod numeric; v_soc numeric; v_ren numeric; v_neto numeric; v_extra numeric;
  v_riesgo numeric; v_monto numeric; v_dias int; v_int numeric; v_sub numeric; v_multa numeric;
  r_emp numeric := 0; r_negro numeric := 0; r_int numeric := 0; r_lav numeric := 0; r_pill numeric := 0; r_sub numeric := 0;
  v_txt text := '';
begin
  if v_uid is null then raise exception 'Inicia sesión para jugar'; end if;
  select * into p from public.perfiles where id = v_uid for update;
  if not found then return; end if;

  v_hoy := public.dia_actual();
  if p.dia_procesado >= v_hoy - 1 then return; end if;
  if p.baneado then
    update public.perfiles set dia_procesado = v_hoy - 1 where id = v_uid;
    return;
  end if;

  select impuestos, auditoria into v_imp, v_aud from public.gobierno where id = 1;

  for v_d in greatest(p.dia_procesado + 1, v_hoy - 60) .. (v_hoy - 1) loop
    v_evt := public._evd(v_d);

    -- Cambio de semana: subsidio, si el tesoro puede pagarlo
    if v_d > 1 and public.mes_de(v_d) > public.mes_de(v_d - 1) then
      v_sub := public.aj('subsidio');
      if v_sub > 0 then
        update public.gobierno set tesoro = tesoro - v_sub where id = 1 and tesoro >= v_sub;
        if found then p.saldo := p.saldo + v_sub; r_sub := r_sub + v_sub; end if;
      end if;
    end if;

    -- Producción diaria de cada empresa (las saboteadas no producen)
    for e in select value from jsonb_array_elements(p.empresas) loop
      continue when coalesce((e->>'sab')::int, 0) >= v_d;
      v_prod := coalesce((select s.base from public.sectores s where s.nombre = e->>'sector'), 30)
                * (e->>'nivel')::int
                * case when (e->>'maq')::boolean then 1.25 else 1 end
                * public.aj('prod_pct') / 100
                * case v_evt when 'burbuja' then 2 when 'crisis' then 0.5 else 1 end;
      v_soc := greatest(0, (v_imp->>'sociedades')::numeric - case when (e->>'contable')::boolean then 5 else 0 end);
      v_ren := (v_imp->>'renta')::numeric;
      v_neto := v_prod * (1 - v_soc / 100) * (1 - v_ren / 100);
      p.saldo := p.saldo + v_neto;
      r_emp := r_emp + v_neto;
      update public.gobierno set tesoro = tesoro + (v_prod - v_neto) where id = 1;
      -- Contabilidad B: un 40 % extra que no paga impuestos, pero es dinero sucio
      if (e->>'ilegal')::boolean then
        v_extra := v_prod * 0.4;
        p.sucio := p.sucio + v_extra;
        r_negro := r_negro + v_extra;
      end if;
    end loop;

    -- Intereses del banco: los paga el tesoro, si le queda
    v_int := least(p.banco, public.aj('banco_tope')) * public.aj('banco_interes') / 100;
    if v_int > 0 then
      update public.gobierno set tesoro = tesoro - v_int where id = 1 and tesoro >= v_int;
      if found then p.banco := p.banco + v_int; r_int := r_int + v_int; end if;
    end if;

    -- Blanqueos en curso: riesgo de auditoría según el gobernador
    v_riesgo := v_aud / 100.0 * 0.5
                * case when p.escudo_hasta > v_d then 0.5 else 1 end
                * case v_evt when 'redada' then 2 when 'amnistia' then 0 else 1 end;
    v_nuevos := '[]'::jsonb;
    for l in select value from jsonb_array_elements(p.lavados) loop
      v_monto := (l->>'monto')::numeric;
      v_dias := (l->>'dias')::int;
      if random() < v_riesgo then
        v_multa := p.saldo * public.aj('multa_pct') / 100;
        update public.gobierno set tesoro = tesoro + v_monto + v_multa where id = 1;
        p.saldo := p.saldo - v_multa;
        r_pill := r_pill + v_monto + v_multa;
      elsif v_dias - 1 <= 0 then
        p.saldo := p.saldo + v_monto * (1 - public.aj('lavado_comision') / 100);
        r_lav := r_lav + v_monto * (1 - public.aj('lavado_comision') / 100);
        update public.gobierno set tesoro = tesoro + v_monto * public.aj('lavado_comision') / 100 where id = 1;
      else
        v_nuevos := v_nuevos || jsonb_build_array(jsonb_build_object('monto', v_monto, 'dias', v_dias - 1));
      end if;
    end loop;
    p.lavados := v_nuevos;
  end loop;

  update public.perfiles
     set saldo = round(p.saldo, 2), sucio = round(p.sucio, 2), banco = round(p.banco, 2),
         lavados = p.lavados, dia_procesado = v_hoy - 1
   where id = v_uid;

  if r_emp  > 0 then v_txt := v_txt || ' Tus empresas han dado ' || public._n(r_emp) || '.'; end if;
  if r_negro > 0 then v_txt := v_txt || ' La contabilidad B, ' || public._n(r_negro) || ' en sucio.'; end if;
  if r_int  >= 1 then v_txt := v_txt || ' El banco te paga ' || public._n(r_int) || ' de intereses.'; end if;
  if r_sub  > 0 then v_txt := v_txt || ' Cobras ' || public._n(r_sub) || ' de subsidio.'; end if;
  if r_lav  > 0 then v_txt := v_txt || ' Blanqueo terminado: ' || public._n(r_lav) || ' limpias.'; end if;
  if r_pill > 0 then v_txt := v_txt || ' Hacienda te ha pillado blanqueando: pierdes ' || public._n(r_pill) || '.'; end if;
  if v_txt <> '' then
    perform public._aviso(v_uid, case when r_pill > 0 then '🚨' else '🌅' end, 'Mientras no estabas:' || v_txt);
  end if;
end;
$$;

-- Puerta de entrada de todas las acciones: pone todo al día y devuelve tu perfil bloqueado.
-- Con p_libre = true falla si estás en la cárcel.
create or replace function public._entrar(p_libre boolean default false) returns public.perfiles
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype;
begin
  perform public._asegurar_perfil();
  perform public.tick_global();
  perform public.ponerse_al_dia();
  select * into p from public.perfiles where id = auth.uid() for update;
  if not found then raise exception 'No tienes perfil. Sal y vuelve a entrar.'; end if;
  if p.baneado then raise exception 'Estás expulsado del juego. Habla con el admin.'; end if;
  if p_libre and p.carcel_hasta > now() then
    raise exception 'Estás en la cárcel. Te quedan % min: paga la fianza o espera.',
      ceil(extract(epoch from (p.carcel_hasta - now())) / 60)::int;
  end if;
  return p;
end;
$$;

-- Jugador objetivo de una acción, bloqueado.
create or replace function public._objetivo(p_a uuid) returns public.perfiles
language plpgsql security definer set search_path = public as $$
declare v public.perfiles%rowtype;
begin
  if p_a is null then raise exception 'Elige a alguien'; end if;
  if p_a = auth.uid() then raise exception 'No puedes hacértelo a ti mismo'; end if;
  select * into v from public.perfiles where id = p_a for update;
  if not found or v.baneado then raise exception 'Ese jugador no existe'; end if;
  return v;
end;
$$;

-- =====================================================================
-- 6. Trabajo
-- =====================================================================

create or replace function public.trabajar() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p public.perfiles%rowtype;
  v_cd int := public.aj('cd_trabajo')::int;
  v_ren numeric; v_bruto numeric; v_neto numeric; v_niv int; v_niv2 int; v_evt text := public.ev();
begin
  p := public._entrar(true);
  if now() - p.ultimo_trabajo < make_interval(mins => v_cd) then
    raise exception 'Aún estás cansado. Te quedan % min.',
      ceil(extract(epoch from (p.ultimo_trabajo + make_interval(mins => v_cd) - now())) / 60)::int;
  end if;
  v_niv := public._nivel(p.xp);
  v_niv2 := public._nivel(p.xp + 1);
  select (impuestos->>'renta')::numeric into v_ren from public.gobierno where id = 1;
  v_bruto := (public.aj('sueldo_min') + floor(random() * (greatest(public.aj('sueldo_max') - public.aj('sueldo_min'), 0) + 1)))
             * (1 + v_niv * public.aj('bonus_nivel') / 100)
             * case v_evt when 'huelga' then 0.5 when 'fiesta' then 2 else 1 end;
  v_bruto := round(v_bruto);
  v_neto := round(v_bruto * (1 - v_ren / 100));
  update public.gobierno set tesoro = tesoro + (v_bruto - v_neto) where id = 1;
  update public.perfiles set saldo = saldo + v_neto, ultimo_trabajo = now(), xp = xp + 1 where id = p.id;
  return jsonb_build_object('ok', true, 'ganado', v_neto, 'sube', v_niv2 > v_niv,
    'msg', public._frase(array[
      'Has fichado, has mirado el móvil y has vuelto a casa.',
      'Ocho horas de reuniones que podían ser un correo.',
      'Has arreglado la impresora. Eres el héroe de la oficina.',
      'Tu jefe te ha dado una palmadita. Y algo de dinero.',
      'Has hecho como que trabajabas con mucha convicción.',
      'Turno doble repartiendo folletos bajo la lluvia.'])
      || ' Cobras ' || public._n(v_neto) || ' 🪙 (Hacienda se queda ' || public._n(v_bruto - v_neto) || ').'
      || case when v_niv2 > v_niv then ' ¡Subes a nivel ' || v_niv2 || '!' else '' end);
end;
$$;

create or replace function public.mendigar() returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_cd int := public.aj('cd_mendigar')::int; v_g numeric;
begin
  p := public._entrar(true);
  if p.saldo + p.banco > public.aj('mendigar_tope') then raise exception 'Con ese dinero no das ninguna pena'; end if;
  if now() - p.ultimo_mendigar < make_interval(mins => v_cd) then
    raise exception 'La gente ya te ha visto. Espera % min.',
      ceil(extract(epoch from (p.ultimo_mendigar + make_interval(mins => v_cd) - now())) / 60)::int;
  end if;
  v_g := case when random() < 0.15 then 0 else 1 + floor(random() * greatest(public.aj('mendigar_max'), 1)) end;
  update public.perfiles set saldo = saldo + v_g, ultimo_mendigar = now() where id = p.id;
  return jsonb_build_object('ok', v_g > 0, 'ganado', v_g, 'msg',
    case when v_g = 0 then public._frase(array[
        'Te han dado un chicle usado. No cuenta como moneda.',
        'Una señora te ha dicho que te pongas a trabajar.',
        'Te han tirado una moneda de chocolate. Derretida.'])
      else public._frase(array[
        'Un turista se ha apiadado de ti.',
        'Has tocado la flauta fatal, pero alguien ha pagado para que pares.',
        'Te han confundido con una estatua humana.']) || ' +' || public._n(v_g) || ' 🪙'
    end);
end;
$$;

create or replace function public.diario() returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_hoy int := public.dia_actual(); v_racha int; v_premio numeric;
begin
  p := public._entrar(false);
  if p.ultimo_diario >= v_hoy then raise exception 'Ya has cobrado la paga de hoy. Vuelve mañana.'; end if;
  v_racha := case when p.ultimo_diario = v_hoy - 1 then p.racha + 1 else 1 end;
  v_premio := public.aj('diario_base') + public.aj('diario_racha') * least(v_racha - 1, public.aj('diario_racha_max'));
  update public.perfiles set saldo = saldo + v_premio, ultimo_diario = v_hoy, racha = v_racha where id = p.id;
  return jsonb_build_object('ok', true, 'ganado', v_premio, 'racha', v_racha,
    'msg', 'Paga diaria: +' || public._n(v_premio) || ' 🪙. Racha de ' || v_racha || case when v_racha = 1 then ' día.' else ' días.' end);
end;
$$;

-- =====================================================================
-- 7. Banco y transferencias
-- =====================================================================

create or replace function public.depositar(p_monto numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_m numeric := round(p_monto);
begin
  p := public._entrar(false);
  if v_m is null or v_m < 1 then raise exception 'Cantidad no válida'; end if;
  if v_m > p.saldo then raise exception 'No llevas tanto encima'; end if;
  update public.perfiles set saldo = saldo - v_m, banco = banco + v_m where id = p.id;
  return jsonb_build_object('ok', true, 'msg', 'Ingresas ' || public._n(v_m) || ' 🪙 en el banco. Ahí no te lo roban.');
end;
$$;

create or replace function public.retirar(p_monto numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_m numeric := round(p_monto);
begin
  p := public._entrar(false);
  if v_m is null or v_m < 1 then raise exception 'Cantidad no válida'; end if;
  if v_m > p.banco then raise exception 'No tienes tanto en el banco'; end if;
  update public.perfiles set saldo = saldo + v_m, banco = banco - v_m where id = p.id;
  return jsonb_build_object('ok', true, 'msg', 'Sacas ' || public._n(v_m) || ' 🪙 del banco.');
end;
$$;

create or replace function public.transferir(p_a uuid, p_monto numeric, p_nota text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v public.perfiles%rowtype; v_m numeric := round(p_monto);
begin
  p := public._entrar(false);
  v := public._objetivo(p_a);
  if v_m is null or v_m < 1 then raise exception 'Cantidad no válida'; end if;
  if v_m > p.saldo then raise exception 'No llevas tanto encima'; end if;
  update public.perfiles set saldo = saldo - v_m where id = p.id;
  update public.perfiles set saldo = saldo + v_m where id = v.id;
  perform public._aviso(v.id, '💸', p.nombre || ' te ha enviado ' || public._n(v_m) || ' monedas.'
    || case when coalesce(trim(p_nota), '') <> '' then ' «' || left(trim(p_nota), 80) || '»' else '' end);
  return jsonb_build_object('ok', true, 'msg', 'Enviadas ' || public._n(v_m) || ' 🪙 a ' || v.nombre || '.');
end;
$$;

-- =====================================================================
-- 8. Crimen
-- =====================================================================

create or replace function public.trabajo_sucio() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p public.perfiles%rowtype; v_cd int := public.aj('cd_sucio')::int;
  v_g numeric; v_multa numeric; v_redada boolean := public.ev() = 'redada';
begin
  p := public._entrar(true);
  if now() - p.ultimo_trabajo_sucio < make_interval(mins => v_cd) then
    raise exception 'Hay que dejar que se enfríe la cosa. Te quedan % min.',
      ceil(extract(epoch from (p.ultimo_trabajo_sucio + make_interval(mins => v_cd) - now())) / 60)::int;
  end if;
  if random() * 100 < public.aj('sucio_fallo') * (case when v_redada then 2 else 1 end) then
    v_multa := least(p.saldo, public.aj('sucio_multa'));
    update public.perfiles set saldo = saldo - v_multa, ultimo_trabajo_sucio = now() where id = p.id;
    update public.gobierno set tesoro = tesoro + v_multa where id = 1;
    return jsonb_build_object('ok', false, 'msg', public._frase(array[
      'Tu compinche era policía.', 'Te has dejado el DNI en la escena.', 'El perro del vecino te ha delatado.'])
      || ' Multa de ' || public._n(v_multa) || ' 🪙.');
  end if;
  v_g := public.aj('sucio_min') + floor(random() * (greatest(public.aj('sucio_max') - public.aj('sucio_min'), 0) + 1));
  update public.perfiles set sucio = sucio + v_g, ultimo_trabajo_sucio = now(), xp = xp + 1 where id = p.id;
  return jsonb_build_object('ok', true, 'ganado', v_g, 'msg', public._frase(array[
    'Has vendido relojes «de marca» en la playa.', 'Has revendido entradas de un concierto que no existe.',
    'Un camión ha «perdido» unas cajas y tú estabas cerca.', 'Has cobrado por aparcar coches en un descampado público.'])
    || ' +' || public._n(v_g) || ' 💰 sucias.');
end;
$$;

create or replace function public.robar(p_a uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p public.perfiles%rowtype; v public.perfiles%rowtype;
  v_cd int := public.aj('cd_robo')::int; v_bot numeric; v_multa numeric; v_min int;
begin
  p := public._entrar(true);
  v := public._objetivo(p_a);
  if now() - p.ultimo_robo < make_interval(mins => v_cd) then
    raise exception 'Aún te tiemblan las manos. Espera % min.',
      ceil(extract(epoch from (p.ultimo_robo + make_interval(mins => v_cd) - now())) / 60)::int;
  end if;
  if v.saldo < 50 then raise exception '% no lleva casi nada encima. No merece la pena.', v.nombre; end if;
  update public.perfiles set ultimo_robo = now() where id = p.id;

  if v.candado_hasta > now() then
    perform public._aviso(v.id, '🔒', p.nombre || ' ha intentado robarte, pero tu candado ha aguantado.');
    return jsonb_build_object('ok', false, 'msg', v.nombre || ' tiene candado. Te vas con las manos vacías.');
  end if;

  if random() * 100 < public.aj('robo_exito') * (case when public.ev() = 'redada' then 0.5 else 1 end) then
    v_bot := greatest(1, least(public.aj('robo_max'), floor(v.saldo * public.aj('robo_pct') / 100 * (0.4 + random() * 0.6))));
    update public.perfiles set saldo = saldo - v_bot where id = v.id;
    update public.perfiles set sucio = sucio + v_bot, xp = xp + 1 where id = p.id;
    perform public._aviso(v.id, '🦹', p.nombre || ' te ha robado ' || public._n(v_bot) || ' monedas. Guarda el dinero en el banco.');
    if v_bot >= 100 then
      perform public._noticia('🦹', 'Atraco a ' || v.nombre, p.nombre || ' le ha levantado ' || public._n(v_bot) || ' monedas.');
    end if;
    return jsonb_build_object('ok', true, 'ganado', v_bot,
      'msg', 'Le has robado ' || public._n(v_bot) || ' 💰 a ' || v.nombre || '. Es dinero sucio.');
  end if;

  v_multa := least(p.saldo, public.aj('robo_multa'));
  v_min := public.aj('carcel_min')::int;
  update public.perfiles set saldo = saldo - v_multa, carcel_hasta = now() + make_interval(mins => v_min) where id = p.id;
  update public.perfiles set saldo = saldo + v_multa where id = v.id;
  perform public._aviso(v.id, '🚓', p.nombre || ' ha intentado robarte y le han pillado. Te llevas ' || public._n(v_multa) || ' de indemnización.');
  perform public._noticia('🚓', p.nombre || ', a la cárcel', 'Le han pillado intentando robar a ' || v.nombre || '.');
  return jsonb_build_object('ok', false, 'carcel', true,
    'msg', 'Te han pillado. Pagas ' || public._n(v_multa) || ' 🪙 a ' || v.nombre || ' y pasas ' || v_min || ' min en la cárcel.');
end;
$$;

create or replace function public.fianza() returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_f numeric := public.aj('fianza');
begin
  p := public._entrar(false);
  if p.carcel_hasta <= now() then raise exception 'No estás en la cárcel'; end if;
  if p.saldo >= v_f then
    update public.perfiles set saldo = saldo - v_f, carcel_hasta = now() where id = p.id;
  elsif p.banco >= v_f then
    update public.perfiles set banco = banco - v_f, carcel_hasta = now() where id = p.id;
  else
    raise exception 'La fianza son % monedas y no las tienes', public._n(v_f);
  end if;
  update public.gobierno set tesoro = tesoro + v_f where id = 1;
  return jsonb_build_object('ok', true, 'msg', 'Pagas ' || public._n(v_f) || ' 🪙 de fianza. Estás libre.');
end;
$$;

create or replace function public.lavar(p_monto numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_m numeric := round(p_monto); v_dias int := public.aj('lavado_dias')::int;
begin
  p := public._entrar(true);
  if v_m is null or v_m < 1 then raise exception 'Cantidad no válida'; end if;
  if v_m > p.sucio then raise exception 'No tienes tanto dinero sucio'; end if;
  if jsonb_array_length(p.lavados) >= 10 then raise exception 'Demasiados blanqueos a la vez. Espera a que termine alguno.'; end if;
  update public.perfiles
     set sucio = sucio - v_m,
         lavados = lavados || jsonb_build_array(jsonb_build_object('monto', v_m, 'dias', v_dias))
   where id = p.id;
  return jsonb_build_object('ok', true, 'msg', 'Blanqueo en marcha: ' || public._n(v_m) || ' 💰 durante ' || v_dias || ' días. Cruza los dedos.');
end;
$$;

-- Deja sin producir unos días una empresa al azar de otro jugador.
create or replace function public.sabotear(p_a uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p public.perfiles%rowtype; v public.perfiles%rowtype;
  v_hoy int := public.dia_actual(); v_hasta int; v_idx int; v_n int; v_emp jsonb; v_min int;
begin
  p := public._entrar(true);
  v := public._objetivo(p_a);
  v_n := jsonb_array_length(v.empresas);
  if v_n = 0 then raise exception '% no tiene empresas que sabotear', v.nombre; end if;
  perform public._pagar(p.id, public.aj('sabotaje_coste'), false, true);
  v_idx := floor(random() * v_n)::int;
  v_emp := v.empresas->v_idx;
  v_hasta := v_hoy + public.aj('sabotaje_dias')::int - 1;
  update public.perfiles set empresas = jsonb_set(empresas, array[v_idx::text, 'sab'], to_jsonb(v_hasta)) where id = v.id;

  if random() * 100 < public.aj('sabotaje_riesgo') then
    v_min := public.aj('carcel_min')::int;
    update public.perfiles set carcel_hasta = now() + make_interval(mins => v_min) where id = p.id;
    perform public._aviso(v.id, '🧨', p.nombre || ' ha saboteado tu empresa ' || (v_emp->>'nombre') || '. Le han pillado.');
    perform public._noticia('🧨', 'Sabotaje en ' || (v_emp->>'nombre'), p.nombre || ' ha sido detenido con las manos en la masa.');
    return jsonb_build_object('ok', true, 'carcel', true,
      'msg', 'Has saboteado ' || (v_emp->>'nombre') || ', pero te han visto. ' || v_min || ' min de cárcel.');
  end if;
  perform public._aviso(v.id, '🧨', 'Alguien ha saboteado tu empresa ' || (v_emp->>'nombre') || '. No produce hasta el día ' || (v_hasta + 1) || '.');
  return jsonb_build_object('ok', true, 'msg', 'Has saboteado ' || (v_emp->>'nombre') || ' de ' || v.nombre || '. Nadie te ha visto.');
end;
$$;

-- =====================================================================
-- 9. Empresas
-- =====================================================================

create or replace function public.fundar(p_nombre text, p_sector text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_nom text := left(trim(coalesce(p_nombre, '')), 30); v_pagado numeric;
begin
  p := public._entrar(true);
  if v_nom = '' then raise exception 'Ponle un nombre a la empresa'; end if;
  if not exists (select 1 from public.sectores where nombre = p_sector) then raise exception 'Sector no válido'; end if;
  if jsonb_array_length(p.empresas) >= public.aj('empresas_max') then
    raise exception 'Ya tienes el máximo de empresas (%)', public._n(public.aj('empresas_max'));
  end if;
  v_pagado := public._pagar(p.id, public.aj('coste_fundar'), true);
  update public.perfiles
     set empresas = empresas || jsonb_build_array(jsonb_build_object(
           'id', gen_random_uuid()::text, 'nombre', v_nom, 'sector', p_sector,
           'nivel', 1, 'maq', false, 'contable', false, 'ilegal', false, 'sab', 0))
   where id = p.id;
  return jsonb_build_object('ok', true, 'msg', 'Has fundado ' || v_nom || ' por ' || public._n(v_pagado) || ' 🪙 (IVA incluido).');
end;
$$;

-- tipo: 'nivel', 'maq', 'contable' o 'ilegal'
create or replace function public.mejorar(p_empresa text, p_tipo text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p public.perfiles%rowtype; e jsonb; x jsonb; v_coste numeric; v_pagado numeric;
  v_nuevos jsonb := '[]'::jsonb; v_ok boolean := false;
begin
  p := public._entrar(true);
  for e in select value from jsonb_array_elements(p.empresas) loop
    x := e;
    if e->>'id' = p_empresa then
      v_ok := true;
      if p_tipo = 'nivel' then
        if (e->>'nivel')::int >= public.aj('nivel_max') then raise exception 'Ya está al nivel máximo'; end if;
        v_coste := public.aj('coste_nivel') * (e->>'nivel')::int;
        x := jsonb_set(e, '{nivel}', to_jsonb((e->>'nivel')::int + 1));
      elsif p_tipo in ('maq', 'contable', 'ilegal') then
        if coalesce((e->>p_tipo)::boolean, false) then raise exception 'Ya la tiene'; end if;
        v_coste := public.aj('coste_' || p_tipo);
        x := jsonb_set(e, array[p_tipo], 'true');
      else
        raise exception 'Mejora desconocida';
      end if;
    end if;
    v_nuevos := v_nuevos || jsonb_build_array(x);
  end loop;
  if not v_ok then raise exception 'No tienes esa empresa'; end if;
  v_pagado := public._pagar(p.id, v_coste, true);
  update public.perfiles set empresas = v_nuevos where id = p.id;
  return jsonb_build_object('ok', true, 'msg', 'Mejora comprada por ' || public._n(v_pagado) || ' 🪙.');
end;
$$;

create or replace function public.vender_empresa(p_empresa text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p public.perfiles%rowtype; e jsonb; v_nuevos jsonb := '[]'::jsonb; v_inv numeric; v_cobro numeric; v_nom text; v_niv int;
begin
  p := public._entrar(true);
  for e in select value from jsonb_array_elements(p.empresas) loop
    if e->>'id' = p_empresa and v_nom is null then
      v_nom := e->>'nombre';
      v_niv := (e->>'nivel')::int;
      v_inv := public.aj('coste_fundar') + public.aj('coste_nivel') * v_niv * (v_niv - 1) / 2
             + case when (e->>'maq')::boolean then public.aj('coste_maq') else 0 end
             + case when (e->>'contable')::boolean then public.aj('coste_contable') else 0 end
             + case when (e->>'ilegal')::boolean then public.aj('coste_ilegal') else 0 end;
    else
      v_nuevos := v_nuevos || jsonb_build_array(e);
    end if;
  end loop;
  if v_nom is null then raise exception 'No tienes esa empresa'; end if;
  v_cobro := round(v_inv * public.aj('venta_pct') / 100);
  update public.perfiles set empresas = v_nuevos, saldo = saldo + v_cobro where id = p.id;
  return jsonb_build_object('ok', true, 'msg', 'Has vendido ' || v_nom || ' por ' || public._n(v_cobro) || ' 🪙.');
end;
$$;

-- =====================================================================
-- 10. Tienda
-- =====================================================================

create or replace function public.comprar(p_item text, p_a uuid default null, p_texto text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p public.perfiles%rowtype; v public.perfiles%rowtype;
  v_hoy int := public.dia_actual(); v_txt text := left(trim(coalesce(p_texto, '')), 80);
  v_conf numeric; v_lav numeric; v_medio numeric; v_premio numeric;
begin
  p := public._entrar(p_item not in ('escudo', 'quitamote'));

  if p_item = 'cafe' then
    if p.cafe_dia = v_hoy and p.cafe_n >= public.aj('cafes_dia') then raise exception 'Demasiado café por hoy. Te va a dar algo.'; end if;
    perform public._pagar(p.id, public.aj('precio_cafe'), true);
    update public.perfiles set ultimo_trabajo = to_timestamp(0), cafe_dia = v_hoy,
           cafe_n = case when cafe_dia = v_hoy then cafe_n + 1 else 1 end where id = p.id;
    return jsonb_build_object('ok', true, 'msg', '☕ Café doble. Puedes volver a trabajar ya.');

  elsif p_item = 'candado' then
    perform public._pagar(p.id, public.aj('precio_candado'), true);
    update public.perfiles set candado_hasta = greatest(candado_hasta, now()) + interval '24 hours' where id = p.id;
    return jsonb_build_object('ok', true, 'msg', '🔒 Candado puesto. 24 horas sin que te roben.');

  elsif p_item = 'escudo' then
    perform public._pagar(p.id, public.aj('precio_escudo'), true);
    update public.perfiles set escudo_hasta = greatest(escudo_hasta, v_hoy) + 7 where id = p.id;
    return jsonb_build_object('ok', true, 'msg', '⚖️ Abogado contratado. 7 días con la mitad de riesgo de auditoría.');

  elsif p_item = 'quitamote' then
    if p.mote is null or p.mote_hasta <= now() then raise exception 'No tienes ningún mote'; end if;
    perform public._pagar(p.id, public.aj('precio_quitamote'), true);
    update public.perfiles set mote = null, mote_hasta = to_timestamp(0) where id = p.id;
    return jsonb_build_object('ok', true, 'msg', 'Mote borrado. Recuperas la dignidad.');

  elsif p_item = 'mote' then
    v := public._objetivo(p_a);
    if char_length(v_txt) < 2 then raise exception 'Escribe el mote'; end if;
    perform public._pagar(p.id, public.aj('precio_mote'), true);
    update public.perfiles set mote = left(v_txt, 24), mote_hasta = now() + interval '24 hours' where id = v.id;
    perform public._aviso(v.id, '🏷️', p.nombre || ' te ha puesto el mote «' || left(v_txt, 24) || '» durante 24 horas.');
    return jsonb_build_object('ok', true, 'msg', '🏷️ ' || v.nombre || ' ahora es «' || left(v_txt, 24) || '» durante 24 horas.');

  elsif p_item = 'tarta' then
    v := public._objetivo(p_a);
    perform public._pagar(p.id, public.aj('precio_tarta'), true);
    perform public._aviso(v.id, '🥧', p.nombre || ' te ha estampado una tarta en la cara.'
      || case when v_txt <> '' then ' «' || v_txt || '»' else '' end, 'tarta');
    return jsonb_build_object('ok', true, 'msg', '🥧 Tartazo enviado a ' || v.nombre || '. Lo verá en cuanto entre.');

  elsif p_item = 'chivatazo' then
    v := public._objetivo(p_a);
    perform public._pagar(p.id, public.aj('precio_chivatazo'), true);
    if v.escudo_hasta > v_hoy and random() < 0.5 then
      perform public._aviso(v.id, '⚖️', 'Tu abogado ha tumbado una denuncia anónima a Hacienda.');
      return jsonb_build_object('ok', false, 'msg', 'Su abogado ha tumbado la denuncia. Dinero tirado.');
    end if;
    select coalesce(sum((value->>'monto')::numeric), 0) into v_lav from jsonb_array_elements(v.lavados);
    v_medio := round(v.sucio * 0.5);
    v_conf := v_lav + v_medio;
    if v_conf < 1 then
      perform public._aviso(v.id, '🕵️', 'Alguien te ha denunciado a Hacienda, pero estabas limpio.');
      return jsonb_build_object('ok', false, 'msg', v.nombre || ' estaba limpio. Has pagado para nada.');
    end if;
    v_premio := round(v_conf * 0.1);
    update public.perfiles set lavados = '[]'::jsonb, sucio = sucio - v_medio where id = v.id;
    update public.perfiles set saldo = saldo + v_premio where id = p.id;
    update public.gobierno set tesoro = tesoro + v_conf - v_premio where id = 1;
    perform public._aviso(v.id, '🕵️', 'Alguien te ha denunciado. Hacienda te confisca ' || public._n(v_conf) || ' monedas sucias.');
    perform public._noticia('🕵️', 'Golpe de Hacienda', 'Una denuncia anónima destapa ' || public._n(v_conf) || ' monedas sucias de ' || v.nombre || '.');
    return jsonb_build_object('ok', true, 'msg', 'Hacienda le ha quitado ' || public._n(v_conf) || ' a ' || v.nombre || '. Te llevas ' || public._n(v_premio) || ' 🪙 de recompensa.');
  end if;

  raise exception 'Artículo no disponible';
end;
$$;

-- =====================================================================
-- 11. Casino y PanchoCoin
-- =====================================================================

create or replace function public._apuesta(p public.perfiles, p_apuesta numeric) returns numeric
language plpgsql security definer set search_path = public as $$
declare v_a numeric := round(p_apuesta);
begin
  if public.ev() = 'apagon' then raise exception 'Hay apagón: el casino está cerrado'; end if;
  if v_a is null or v_a < 1 then raise exception 'Apuesta no válida'; end if;
  if v_a > public.aj('apuesta_max') then raise exception 'La apuesta máxima es %', public._n(public.aj('apuesta_max')); end if;
  if v_a > p.saldo then raise exception 'No llevas tanto encima'; end if;
  return v_a;
end;
$$;

create or replace function public.moneda(p_apuesta numeric, p_cara boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_a numeric; v_gana boolean; v_sale boolean;
begin
  p := public._entrar(true);
  v_a := public._apuesta(p, p_apuesta);
  v_gana := random() * 100 < public.aj('moneda_prob');
  v_sale := case when v_gana then p_cara else not p_cara end;
  update public.perfiles set saldo = saldo + case when v_gana then v_a else -v_a end where id = p.id;
  update public.gobierno set tesoro = greatest(0, tesoro + case when v_gana then -v_a else v_a end) where id = 1;
  return jsonb_build_object('ok', v_gana, 'cara', v_sale, 'ganado', case when v_gana then v_a else -v_a end,
    'msg', 'Sale ' || case when v_sale then 'cara' else 'cruz' end || '. '
      || case when v_gana then 'Ganas ' || public._n(v_a) || ' 🪙.' else 'Pierdes ' || public._n(v_a) || ' 🪙.' end);
end;
$$;

create or replace function public.tragaperras(p_apuesta numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p public.perfiles%rowtype; v_a numeric; v_mult numeric := 0; v_premio numeric;
  v_s text[] := array['🍒','🍒','🍒','🍒','🍒','🍋','🍋','🍋','🍋','🔔','🔔','🔔','💎','💎','7️⃣'];
  r1 text; r2 text; r3 text;
begin
  p := public._entrar(true);
  v_a := public._apuesta(p, p_apuesta);
  r1 := public._frase(v_s); r2 := public._frase(v_s); r3 := public._frase(v_s);
  if r1 = r2 and r2 = r3 then
    v_mult := case r1 when '🍒' then 3 when '🍋' then 5 when '🔔' then 10 when '💎' then 25 else 80 end;
  elsif r1 = r2 or r2 = r3 or r1 = r3 then
    v_mult := 1;
  end if;
  v_premio := v_a * v_mult;
  update public.perfiles set saldo = saldo - v_a + v_premio where id = p.id;
  update public.gobierno set tesoro = greatest(0, tesoro + v_a - v_premio) where id = 1;
  if v_mult >= 25 then
    perform public._noticia('🎰', p.nombre || ' revienta la tragaperras', 'Premio de ' || public._n(v_premio) || ' monedas con ' || r1 || r2 || r3 || '.');
  end if;
  return jsonb_build_object('ok', v_mult > 1, 'rodillos', jsonb_build_array(r1, r2, r3), 'ganado', v_premio - v_a,
    'msg', case when v_mult = 0 then 'Nada. Pierdes ' || public._n(v_a) || ' 🪙.'
                when v_mult = 1 then 'Pareja: recuperas la apuesta.'
                else '¡Trío! Ganas ' || public._n(v_premio) || ' 🪙.' end);
end;
$$;

-- 5 de cada 6 veces ganas un porcentaje de lo que llevas encima; 1 de cada 6 lo pierdes todo.
create or replace function public.ruleta_rusa() returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_g numeric;
begin
  p := public._entrar(true);
  if public.ev() = 'apagon' then raise exception 'Hay apagón: el casino está cerrado'; end if;
  if p.saldo < 50 then raise exception 'Necesitas llevar al menos 50 monedas encima'; end if;
  if random() < 1.0 / 6 then
    update public.perfiles set saldo = 0 where id = p.id;
    update public.gobierno set tesoro = tesoro + p.saldo where id = 1;
    perform public._noticia('💀', p.nombre || ' pierde a la ruleta rusa', 'Llevaba ' || public._n(p.saldo) || ' monedas encima. Ya no.');
    return jsonb_build_object('ok', false, 'ganado', -p.saldo, 'msg', '💥 Bang. Pierdes las ' || public._n(p.saldo) || ' 🪙 que llevabas encima.');
  end if;
  v_g := round(least(p.saldo * public.aj('ruleta_premio') / 100, public.aj('apuesta_max') * 2));
  update public.perfiles set saldo = saldo + v_g where id = p.id;
  return jsonb_build_object('ok', true, 'ganado', v_g, 'msg', 'Clic. Sigues vivo y ganas ' || public._n(v_g) || ' 🪙.');
end;
$$;

create or replace function public.loteria_comprar(p_n int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p public.perfiles%rowtype; v_hoy int := public.dia_actual(); v_tengo int;
  v_precio numeric := public.aj('loteria_precio'); v_coste numeric; v_casa numeric;
begin
  p := public._entrar(true);
  if p_n is null or p_n < 1 then raise exception 'Cantidad no válida'; end if;
  select coalesce(sum(boletos), 0) into v_tengo from public.loteria where jugador = p.id and dia = v_hoy;
  if v_tengo + p_n > public.aj('loteria_max') then
    raise exception 'Máximo % boletos al día. Llevas %.', public._n(public.aj('loteria_max')), v_tengo;
  end if;
  v_coste := v_precio * p_n;
  perform public._pagar(p.id, v_coste, false);
  v_casa := v_coste * public.aj('loteria_casa') / 100;
  update public.gobierno set bote = bote + v_coste - v_casa, tesoro = tesoro + v_casa where id = 1;
  insert into public.loteria (dia, jugador, boletos) values (v_hoy, p.id, p_n)
    on conflict (dia, jugador) do update set boletos = public.loteria.boletos + excluded.boletos;
  return jsonb_build_object('ok', true, 'msg', '🎟️ ' || p_n || case when p_n = 1 then ' boleto comprado.' else ' boletos comprados.' end || ' El sorteo es al cambiar de día.');
end;
$$;

-- El precio de PanchoCoin se mueve solo cada 10 minutos, con algún susto de vez en cuando.
create or replace function public._mercado_tick() returns void
language plpgsql security definer set search_path = public as $$
declare
  m public.mercado%rowtype; v_n int; v_real int; i int; v_p numeric; v_h jsonb;
  v_vol numeric := public.aj('cripto_volatilidad');
begin
  select * into m from public.mercado where id = 1;
  if now() - m.actualizado < interval '10 minutes' then return; end if;
  select * into m from public.mercado where id = 1 for update;
  v_real := floor(extract(epoch from (now() - m.actualizado)) / 600)::int;
  if v_real < 1 then return; end if;
  v_n := least(v_real, 144);
  v_p := m.precio; v_h := m.historial;
  for i in 1 .. v_n loop
    v_p := v_p * (1 + ((random() - 0.5) * 2 * v_vol + ln(100 / v_p) * 1.5) / 100);
    if random() < 0.03 then v_p := v_p * case when random() < 0.5 then 1.3 else 0.75 end; end if;
    v_p := least(greatest(v_p, 1), 100000);
    v_h := v_h || to_jsonb(round(v_p, 2));
  end loop;
  if jsonb_array_length(v_h) > 72 then
    select jsonb_agg(s.x order by s.o) into v_h
      from (select t.x, t.o from jsonb_array_elements(v_h) with ordinality t(x, o) order by t.o desc limit 72) s;
  end if;
  update public.mercado
     set precio = round(v_p, 2), historial = v_h,
         actualizado = case when v_real > 144 then now() else m.actualizado + v_n * interval '10 minutes' end
   where id = 1;
end;
$$;

create or replace function public.cripto_comprar(p_gasto numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_g numeric := round(p_gasto); v_precio numeric; v_com numeric; v_u numeric;
begin
  p := public._entrar(true);
  if public.ev() = 'apagon' then raise exception 'Hay apagón: la bolsa está cerrada'; end if;
  if v_g is null or v_g < 1 then raise exception 'Cantidad no válida'; end if;
  if v_g > p.saldo then raise exception 'No llevas tanto encima'; end if;
  perform public._mercado_tick();
  select precio into v_precio from public.mercado where id = 1;
  v_com := v_g * public.aj('cripto_comision') / 100;
  v_u := round((v_g - v_com) / v_precio, 4);
  if v_u <= 0 then raise exception 'Con eso no te llega ni para una fracción'; end if;
  update public.perfiles set saldo = saldo - v_g, cripto = cripto + v_u where id = p.id;
  update public.gobierno set tesoro = tesoro + v_com where id = 1;
  return jsonb_build_object('ok', true, 'msg', 'Compras ' || v_u || ' PanchoCoin a ' || v_precio || '. A la luna.');
end;
$$;

create or replace function public.cripto_vender(p_unidades numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_u numeric := round(p_unidades, 4); v_precio numeric; v_bruto numeric; v_com numeric;
begin
  p := public._entrar(true);
  if public.ev() = 'apagon' then raise exception 'Hay apagón: la bolsa está cerrada'; end if;
  if v_u is null or v_u <= 0 then raise exception 'Cantidad no válida'; end if;
  if v_u > p.cripto then raise exception 'No tienes tantos PanchoCoin'; end if;
  perform public._mercado_tick();
  select precio into v_precio from public.mercado where id = 1;
  v_bruto := v_u * v_precio;
  v_com := v_bruto * public.aj('cripto_comision') / 100;
  update public.perfiles set saldo = saldo + round(v_bruto - v_com), cripto = cripto - v_u where id = p.id;
  update public.gobierno set tesoro = tesoro + v_com where id = 1;
  return jsonb_build_object('ok', true, 'msg', 'Vendes ' || v_u || ' PanchoCoin por ' || public._n(v_bruto - v_com) || ' 🪙.');
end;
$$;

-- =====================================================================
-- 12. Política
-- =====================================================================

create or replace function public.presentarse(p_renta numeric, p_sociedades numeric, p_iva numeric, p_lema text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_mes int := public.mes_de(public.dia_actual()); v_max numeric := public.aj('impuesto_max'); v_coste numeric := public.aj('coste_candidato');
begin
  p := public._entrar(false);
  if exists (select 1 from public.candidatos where mes = v_mes and candidato = p.id) then
    raise exception 'Ya te has presentado esta semana';
  end if;
  if p_renta is null or p_sociedades is null or p_iva is null
     or least(p_renta, p_sociedades, p_iva) < 0 or greatest(p_renta, p_sociedades, p_iva) > v_max then
    raise exception 'Los impuestos de tu programa tienen que estar entre 0 y %', public._n(v_max);
  end if;
  perform public._pagar(p.id, v_coste, false);
  update public.gobierno set tesoro = tesoro + v_coste where id = 1;
  insert into public.candidatos (mes, candidato, nombre, plat, lema)
  values (v_mes, p.id, p.nombre,
          jsonb_build_object('renta', round(p_renta), 'sociedades', round(p_sociedades), 'iva', round(p_iva)),
          left(trim(coalesce(p_lema, '')), 80));
  perform public._noticia('🗳️', p.nombre || ' se presenta a gobernador',
    case when trim(coalesce(p_lema, '')) <> '' then '«' || left(trim(p_lema), 80) || '»' else 'Sin lema. Ni falta que hace.' end);
  return jsonb_build_object('ok', true, 'msg', 'Candidatura registrada. Ahora a pedir el voto.');
end;
$$;

create or replace function public.votar(p_candidato uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_mes int := public.mes_de(public.dia_actual());
begin
  p := public._entrar(false);
  if not exists (select 1 from public.candidatos where mes = v_mes and candidato = p_candidato) then
    raise exception 'Esa persona no es candidata esta semana';
  end if;
  if exists (select 1 from public.votos where mes = v_mes and votante = p.id) then
    raise exception 'Ya has votado esta semana';
  end if;
  insert into public.votos (mes, votante, candidato) values (v_mes, p.id, p_candidato);
  return jsonb_build_object('ok', true, 'msg', 'Voto registrado. Es secreto.');
end;
$$;

create or replace function public.comprar_votos(p_candidato uuid, p_n int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_mes int := public.mes_de(public.dia_actual()); v_multa numeric;
begin
  p := public._entrar(true);
  if p_n is null or p_n < 1 or p_n > 10 then raise exception 'Entre 1 y 10 votos cada vez'; end if;
  if not exists (select 1 from public.candidatos where mes = v_mes and candidato = p_candidato) then
    raise exception 'Esa persona no es candidata esta semana';
  end if;
  perform public._pagar(p.id, public.aj('voto_precio') * p_n, false, true);
  if random() * 100 < public.aj('voto_riesgo') * (case when public.ev() = 'redada' then 2 else 1 end) then
    select saldo * public.aj('multa_pct') / 100 into v_multa from public.perfiles where id = p.id;
    v_multa := round(v_multa);
    update public.perfiles set saldo = saldo - v_multa where id = p.id;
    update public.gobierno set tesoro = tesoro + v_multa where id = 1;
    perform public._noticia('🗳️', 'Escándalo electoral', p.nombre || ' ha sido pillado comprando votos.');
    return jsonb_build_object('ok', false, 'msg', 'Te han pillado. Pierdes el dinero y pagas ' || public._n(v_multa) || ' 🪙 de multa.');
  end if;
  update public.candidatos set comprados = comprados + p_n where mes = v_mes and candidato = p_candidato;
  return jsonb_build_object('ok', true, 'msg', p_n || case when p_n = 1 then ' voto comprado.' else ' votos comprados.' end || ' Nadie se ha enterado.');
end;
$$;

-- El gobernador cambia los tres impuestos de una vez, una sola vez por semana.
create or replace function public.gob_impuestos(p_renta numeric, p_sociedades numeric, p_iva numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; g public.gobierno%rowtype; v_max numeric := public.aj('impuesto_max');
begin
  p := public._entrar(false);
  select * into g from public.gobierno where id = 1 for update;
  if g.gobernador is distinct from p.id then raise exception 'Solo el gobernador puede cambiar impuestos'; end if;
  if g.cambios_mes >= 1 then raise exception 'Ya has cambiado los impuestos esta semana'; end if;
  if p_renta is null or p_sociedades is null or p_iva is null
     or least(p_renta, p_sociedades, p_iva) < 0 or greatest(p_renta, p_sociedades, p_iva) > v_max then
    raise exception 'Cada impuesto tiene que estar entre 0 y %', public._n(v_max);
  end if;
  update public.gobierno
     set impuestos = jsonb_build_object('renta', round(p_renta), 'sociedades', round(p_sociedades), 'iva', round(p_iva)),
         cambios_mes = cambios_mes + 1
   where id = 1;
  perform public._noticia('🏛️', 'Cambian los impuestos',
    format('%s fija renta %s, sociedades %s e IVA %s.', p.nombre, round(p_renta), round(p_sociedades), round(p_iva)));
  return jsonb_build_object('ok', true, 'msg', 'Impuestos cambiados. Hasta la semana que viene no puedes tocarlos.');
end;
$$;

create or replace function public.gob_auditoria(p_valor int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype;
begin
  p := public._entrar(false);
  if (select gobernador from public.gobierno where id = 1) is distinct from p.id then
    raise exception 'Solo el gobernador puede fijar la auditoría';
  end if;
  if p_valor is null or p_valor < 0 or p_valor > 30 then raise exception 'Entre 0 y 30'; end if;
  update public.gobierno set auditoria = p_valor where id = 1;
  return jsonb_build_object('ok', true, 'msg', 'Auditoría fijada.');
end;
$$;

create or replace function public.gob_decreto(p_texto text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_t text := left(trim(coalesce(p_texto, '')), 140);
begin
  p := public._entrar(false);
  if (select gobernador from public.gobierno where id = 1) is distinct from p.id then
    raise exception 'Solo el gobernador puede publicar decretos';
  end if;
  update public.gobierno set decreto = v_t where id = 1;
  if v_t <> '' then perform public._noticia('📜', 'Decreto del gobernador ' || p.nombre, v_t); end if;
  return jsonb_build_object('ok', true, 'msg', case when v_t = '' then 'Decreto retirado.' else 'Decreto publicado.' end);
end;
$$;

-- Reparte dinero del tesoro entre todos los jugadores.
create or replace function public.gob_paga_extra(p_monto numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; g public.gobierno%rowtype; v_m numeric := round(p_monto); v_n int;
begin
  p := public._entrar(false);
  select * into g from public.gobierno where id = 1 for update;
  if g.gobernador is distinct from p.id then raise exception 'Solo el gobernador puede repartir el tesoro'; end if;
  if v_m is null or v_m < 1 then raise exception 'Cantidad no válida'; end if;
  select count(*) into v_n from public.perfiles where not baneado;
  if v_m * v_n > g.tesoro then raise exception 'El tesoro no da para tanto (hay %)', public._n(g.tesoro); end if;
  update public.perfiles set saldo = saldo + v_m where not baneado;
  update public.gobierno set tesoro = tesoro - v_m * v_n where id = 1;
  perform public._noticia('💶', 'Paga extra', p.nombre || ' reparte ' || public._n(v_m) || ' monedas a cada jugador a cuenta del tesoro.');
  return jsonb_build_object('ok', true, 'msg', 'Has repartido ' || public._n(v_m) || ' 🪙 a ' || v_n || ' jugadores.');
end;
$$;

-- El gobernador mete la mano en la caja. Si le pillan, pierde el cargo y va a la cárcel.
create or replace function public.gob_malversar(p_monto numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; g public.gobierno%rowtype; v_m numeric := round(p_monto); v_hoy int := public.dia_actual(); v_tope numeric;
begin
  p := public._entrar(true);
  select * into g from public.gobierno where id = 1 for update;
  if g.gobernador is distinct from p.id then raise exception 'Solo el gobernador puede meter la mano en la caja'; end if;
  if g.malversado_dia >= v_hoy then raise exception 'Ya has metido la mano hoy. No abuses.'; end if;
  v_tope := floor(g.tesoro * public.aj('malversar_pct') / 100);
  if v_m is null or v_m < 1 then raise exception 'Cantidad no válida'; end if;
  if v_m > v_tope then raise exception 'Como mucho puedes llevarte % hoy', public._n(v_tope); end if;
  update public.gobierno set malversado_dia = v_hoy where id = 1;
  if random() * 100 < public.aj('malversar_riesgo') then
    update public.gobierno set gobernador = null, gobernador_nombre = 'Vacante (escándalo)', decreto = '' where id = 1;
    update public.perfiles set carcel_hasta = now() + interval '2 hours' where id = p.id;
    perform public._noticia('🚨', 'Cae el gobernador ' || p.nombre, 'Le han pillado intentando llevarse ' || public._n(v_m) || ' monedas del tesoro. Destituido y a la cárcel.');
    return jsonb_build_object('ok', false, 'carcel', true, 'msg', 'Te han pillado. Pierdes el cargo y pasas 2 horas en la cárcel.');
  end if;
  update public.gobierno set tesoro = tesoro - v_m where id = 1;
  update public.perfiles set sucio = sucio + v_m where id = p.id;
  return jsonb_build_object('ok', true, 'msg', 'Te llevas ' || public._n(v_m) || ' 💰 del tesoro. Es dinero sucio.');
end;
$$;

-- =====================================================================
-- 13. Chat, avisos y estado completo para la web
-- =====================================================================

create or replace function public.canjear_chat(p_n int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfiles%rowtype; v_did text; v_libres int; v_g numeric;
begin
  p := public._entrar(false);
  if p_n is null or p_n < 1 then raise exception 'Cantidad no válida'; end if;
  select i.provider_id into v_did from auth.identities i where i.user_id = p.id and i.provider = 'discord' limit 1;
  select m.monedas - m.gastadas into v_libres from public.monedas_chat m where m.discord_id = v_did for update;
  if coalesce(v_libres, 0) < p_n then raise exception 'Solo tienes % monedas de chat sin gastar', coalesce(v_libres, 0); end if;
  v_g := p_n * public.aj('canje_chat');
  update public.monedas_chat set gastadas = gastadas + p_n where discord_id = v_did;
  update public.perfiles set saldo = saldo + v_g where id = p.id;
  return jsonb_build_object('ok', true, 'msg', 'Canjeas ' || p_n || ' 💬 por ' || public._n(v_g) || ' 🪙.');
end;
$$;

-- Monedas de chat que te quedan por gastar.
create or replace function public.mis_monedas_chat() returns int
language sql stable security definer set search_path = public as $$
  select coalesce((
    select m.monedas - m.gastadas from public.monedas_chat m
    join auth.identities i on i.provider_id = m.discord_id
    where i.user_id = auth.uid() and i.provider = 'discord'
  ), 0);
$$;

create or replace function public.avisos_leidos() returns void
language sql security definer set search_path = public as $$
  update public.avisos set leido = true where jugador = auth.uid() and not leido;
$$;

-- Todo lo que necesita la web, en una sola llamada.
create or replace function public.estado() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); p public.perfiles%rowtype; g public.gobierno%rowtype; v_hoy int; v_mes int;
begin
  perform public._asegurar_perfil();
  perform public.tick_global();
  perform public.ponerse_al_dia();
  perform public._mercado_tick();
  select * into p from public.perfiles where id = v_uid;
  select * into g from public.gobierno where id = 1;
  v_hoy := public.dia_actual();
  v_mes := public.mes_de(v_hoy);

  return jsonb_build_object(
    'ahora', now(), 'dia', v_hoy, 'mes', v_mes, 'dia_semana', ((v_hoy - 1) % 7) + 1,
    'cambio_dia', g.inicio + make_interval(days => v_hoy),
    'dueno', public.soy_dueno(),
    'yo', to_jsonb(p) || jsonb_build_object(
      'nivel', public._nivel(p.xp),
      'en_carcel', p.carcel_hasta > now(),
      'mote', case when p.mote_hasta > now() then p.mote end,
      'cafes_hoy', case when p.cafe_dia = v_hoy then p.cafe_n else 0 end,
      'diario_listo', p.ultimo_diario < v_hoy),
    'chat', coalesce((select jsonb_build_object('total', m.monedas, 'libres', m.monedas - m.gastadas)
               from public.monedas_chat m join auth.identities i on i.provider_id = m.discord_id
              where i.user_id = v_uid and i.provider = 'discord' limit 1), '{"total":0,"libres":0}'::jsonb),
    'gob', jsonb_build_object('tesoro', round(g.tesoro), 'impuestos', g.impuestos, 'auditoria', g.auditoria,
      'gobernador', g.gobernador, 'nombre', g.gobernador_nombre, 'cambios', g.cambios_mes,
      'decreto', g.decreto, 'bote', round(g.bote), 'malversado_hoy', g.malversado_dia >= v_hoy),
    'evento', case when g.evento_fin > now() and g.evento <> ''
                   then public._evento_info(g.evento) || jsonb_build_object('fin', g.evento_fin) end,
    'aj', (select jsonb_object_agg(a.clave, a.valor) from public.ajustes a),
    'sectores', (select coalesce(jsonb_agg(jsonb_build_object('nombre', s.nombre, 'base', s.base, 'icono', s.icono) order by s.base, s.nombre), '[]'::jsonb) from public.sectores s),
    'candidatos', (select coalesce(jsonb_agg(jsonb_build_object('id', c.candidato, 'nombre', c.nombre, 'lema', c.lema, 'plat', c.plat) order by c.nombre), '[]'::jsonb)
                     from public.candidatos c where c.mes = v_mes),
    'mi_voto', (select v.candidato from public.votos v where v.mes = v_mes and v.votante = v_uid),
    'jugadores', (select coalesce(jsonb_agg(s.j order by (s.j->>'rico')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object('id', q.id, 'nombre', q.nombre,
                 'mote', case when q.mote_hasta > now() then q.mote end,
                 'rico', round(q.saldo + q.banco), 'mano', round(q.saldo), 'nivel', public._nivel(q.xp),
                 'empresas', jsonb_array_length(q.empresas), 'carcel', q.carcel_hasta > now()) as j
          from public.perfiles q where not q.baneado) s),
    'noticias', (select coalesce(jsonb_agg(to_jsonb(n) order by n.fija desc, n.id desc), '[]'::jsonb)
                   from (select * from public.noticias order by fija desc, id desc limit 40) n),
    'avisos', (select coalesce(jsonb_agg(to_jsonb(a) - 'jugador' order by a.id desc), '[]'::jsonb)
                 from (select * from public.avisos where jugador = v_uid order by id desc limit 30) a),
    'mercado', (select jsonb_build_object('precio', m.precio, 'historial', m.historial) from public.mercado m where m.id = 1),
    'loteria', jsonb_build_object(
      'mios', coalesce((select sum(l.boletos) from public.loteria l where l.jugador = v_uid), 0),
      'total', coalesce((select sum(l.boletos) from public.loteria l), 0))
  );
end;
$$;

-- =====================================================================
-- 14. Panel de admin (solo el dueño)
-- =====================================================================

create or replace function public.admin_estado() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._admin();
  return jsonb_build_object(
    'jugadores', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', q.id, 'nombre', q.nombre, 'saldo', round(q.saldo), 'sucio', round(q.sucio), 'banco', round(q.banco),
        'cripto', q.cripto, 'xp', q.xp, 'nivel', public._nivel(q.xp), 'baneado', q.baneado,
        'carcel_hasta', q.carcel_hasta, 'en_carcel', q.carcel_hasta > now(),
        'mote', case when q.mote_hasta > now() then q.mote end,
        'empresas', jsonb_array_length(q.empresas), 'lavados', jsonb_array_length(q.lavados), 'creado', q.creado
      ) order by q.nombre), '[]'::jsonb) from public.perfiles q),
    'ajustes', (select coalesce(jsonb_agg(to_jsonb(a) order by a.grupo, a.clave), '[]'::jsonb) from public.ajustes a),
    'sectores', (select coalesce(jsonb_agg(to_jsonb(s) order by s.base, s.nombre), '[]'::jsonb) from public.sectores s),
    'gobierno', (select to_jsonb(g) from public.gobierno g where g.id = 1),
    'chat', (select coalesce(jsonb_agg(to_jsonb(m) order by m.monedas desc), '[]'::jsonb) from public.monedas_chat m),
    'noticias', (select coalesce(jsonb_agg(to_jsonb(n) order by n.id desc), '[]'::jsonb)
                   from (select * from public.noticias order by id desc limit 60) n),
    'eventos', jsonb_build_array(public._evento_info('huelga'), public._evento_info('fiesta'), public._evento_info('burbuja'),
      public._evento_info('crisis'), public._evento_info('redada'), public._evento_info('amnistia'), public._evento_info('apagon'))
  );
end;
$$;

create or replace function public.admin_ajuste(p_clave text, p_valor numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.ajustes%rowtype;
begin
  perform public._admin();
  select * into a from public.ajustes where clave = p_clave;
  if not found then raise exception 'Ese ajuste no existe'; end if;
  if p_valor is null or p_valor < a.minimo or p_valor > a.maximo then
    raise exception 'El valor tiene que estar entre % y %', a.minimo, a.maximo;
  end if;
  update public.ajustes set valor = p_valor where clave = p_clave;
  return jsonb_build_object('ok', true, 'msg', a.nombre || ': ' || p_valor);
end;
$$;

create or replace function public.admin_ajustes_reset() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._admin();
  update public.ajustes set valor = defecto where valor is distinct from defecto;
  return jsonb_build_object('ok', true, 'msg', 'Todos los ajustes vuelven a su valor de fábrica.');
end;
$$;

create or replace function public.admin_sector(p_nombre text, p_base numeric, p_icono text default '🏢') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nom text := left(trim(coalesce(p_nombre, '')), 30);
begin
  perform public._admin();
  if v_nom = '' then raise exception 'Falta el nombre'; end if;
  if p_base is null or p_base < 0 or p_base > 100000 then raise exception 'La base tiene que estar entre 0 y 100000'; end if;
  insert into public.sectores (nombre, base, icono) values (v_nom, p_base, coalesce(nullif(left(trim(p_icono), 8), ''), '🏢'))
    on conflict (nombre) do update set base = excluded.base, icono = excluded.icono;
  return jsonb_build_object('ok', true, 'msg', 'Sector guardado: ' || v_nom);
end;
$$;

create or replace function public.admin_sector_borrar(p_nombre text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._admin();
  delete from public.sectores where nombre = p_nombre;
  return jsonb_build_object('ok', true, 'msg', 'Sector borrado. Las empresas que ya lo tenían producen con base 30.');
end;
$$;

-- p_campo: saldo, sucio, banco, cripto o xp. Con p_sumar = true suma (o resta) en vez de fijar.
create or replace function public.admin_dinero(p_jugador uuid, p_campo text, p_valor numeric, p_sumar boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nom text;
begin
  perform public._admin();
  if p_campo not in ('saldo', 'sucio', 'banco', 'cripto', 'xp') then raise exception 'Campo no válido'; end if;
  if p_valor is null then raise exception 'Falta el valor'; end if;
  execute format('update public.perfiles set %1$I = greatest(0, case when $2 then %1$I + $1 else $1 end)::%2$s where id = $3 returning nombre',
                 p_campo, case when p_campo = 'xp' then 'int' else 'numeric' end)
    into v_nom using p_valor, p_sumar, p_jugador;
  if v_nom is null then raise exception 'Ese jugador no existe'; end if;
  return jsonb_build_object('ok', true, 'msg', v_nom || ': ' || p_campo || case when p_sumar then ' ajustado en ' else ' fijado a ' end || p_valor);
end;
$$;

-- Da (o quita, con número negativo) dinero limpio a todo el mundo.
create or replace function public.admin_lluvia(p_monto numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  perform public._admin();
  if p_monto is null or p_monto = 0 then raise exception 'Cantidad no válida'; end if;
  update public.perfiles set saldo = greatest(0, saldo + p_monto) where not baneado;
  get diagnostics v_n = row_count;
  if p_monto > 0 then
    perform public._noticia('🌧️', 'Lluvia de monedas', 'Caen ' || public._n(p_monto) || ' monedas del cielo para cada jugador.');
  else
    perform public._noticia('🧾', 'Impuesto revolucionario', 'A cada jugador le desaparecen ' || public._n(-p_monto) || ' monedas. Nadie sabe nada.');
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Hecho para ' || v_n || ' jugadores.');
end;
$$;

create or replace function public.admin_carcel(p_jugador uuid, p_minutos int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nom text;
begin
  perform public._admin();
  update public.perfiles set carcel_hasta = case when coalesce(p_minutos, 0) <= 0 then now() else now() + make_interval(mins => p_minutos) end
   where id = p_jugador returning nombre into v_nom;
  if v_nom is null then raise exception 'Ese jugador no existe'; end if;
  if coalesce(p_minutos, 0) > 0 then
    perform public._aviso(p_jugador, '🚓', 'El admin te ha metido ' || p_minutos || ' min en la cárcel. Algo habrás hecho.');
  end if;
  return jsonb_build_object('ok', true, 'msg', v_nom || case when coalesce(p_minutos, 0) <= 0 then ' sale libre.' else ' entra en la cárcel ' || p_minutos || ' min.' end);
end;
$$;

create or replace function public.admin_ban(p_jugador uuid, p_ban boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nom text;
begin
  perform public._admin();
  if p_jugador = auth.uid() and p_ban then raise exception 'No te puedes expulsar a ti mismo'; end if;
  update public.perfiles set baneado = coalesce(p_ban, false) where id = p_jugador returning nombre into v_nom;
  if v_nom is null then raise exception 'Ese jugador no existe'; end if;
  return jsonb_build_object('ok', true, 'msg', v_nom || case when p_ban then ' queda fuera del juego.' else ' vuelve al juego.' end);
end;
$$;

create or replace function public.admin_mote(p_jugador uuid, p_mote text, p_horas int default 24) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nom text; v_m text := left(trim(coalesce(p_mote, '')), 24);
begin
  perform public._admin();
  update public.perfiles
     set mote = nullif(v_m, ''),
         mote_hasta = case when v_m = '' then to_timestamp(0) else now() + make_interval(hours => greatest(coalesce(p_horas, 24), 1)) end
   where id = p_jugador returning nombre into v_nom;
  if v_nom is null then raise exception 'Ese jugador no existe'; end if;
  return jsonb_build_object('ok', true, 'msg', v_nom || case when v_m = '' then ' se queda sin mote.' else ' ahora es «' || v_m || '».' end);
end;
$$;

create or replace function public.admin_renombrar(p_jugador uuid, p_nombre text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_n text := left(trim(coalesce(p_nombre, '')), 30);
begin
  perform public._admin();
  if v_n = '' then raise exception 'Falta el nombre'; end if;
  update public.perfiles set nombre = v_n where id = p_jugador;
  if not found then raise exception 'Ese jugador no existe'; end if;
  update public.gobierno set gobernador_nombre = v_n where id = 1 and gobernador = p_jugador;
  update public.candidatos set nombre = v_n where candidato = p_jugador;
  return jsonb_build_object('ok', true, 'msg', 'Ahora se llama ' || v_n || '.');
end;
$$;

create or replace function public.admin_esperas(p_jugador uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nom text;
begin
  perform public._admin();
  update public.perfiles
     set ultimo_trabajo = to_timestamp(0), ultimo_trabajo_sucio = to_timestamp(0), ultimo_robo = to_timestamp(0),
         ultimo_mendigar = to_timestamp(0), ultimo_diario = 0, cafe_n = 0
   where id = p_jugador returning nombre into v_nom;
  if v_nom is null then raise exception 'Ese jugador no existe'; end if;
  return jsonb_build_object('ok', true, 'msg', 'Esperas de ' || v_nom || ' a cero.');
end;
$$;

create or replace function public.admin_reset_jugador(p_jugador uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nom text;
begin
  perform public._admin();
  update public.perfiles
     set saldo = public.aj('saldo_inicial'), sucio = 0, banco = 0, cripto = 0, xp = 0,
         empresas = '[]', lavados = '[]', inventario = '{}', escudo_hasta = 0,
         carcel_hasta = to_timestamp(0), candado_hasta = to_timestamp(0), mote = null, mote_hasta = to_timestamp(0),
         ultimo_trabajo = to_timestamp(0), ultimo_trabajo_sucio = to_timestamp(0), ultimo_robo = to_timestamp(0),
         ultimo_mendigar = to_timestamp(0), ultimo_diario = 0, racha = 0, cafe_n = 0,
         dia_procesado = greatest(0, public.dia_actual() - 1)
   where id = p_jugador returning nombre into v_nom;
  if v_nom is null then raise exception 'Ese jugador no existe'; end if;
  delete from public.loteria where jugador = p_jugador;
  return jsonb_build_object('ok', true, 'msg', v_nom || ' empieza de cero.');
end;
$$;

-- Los parámetros a null se dejan como están.
create or replace function public.admin_gobierno(p_tesoro numeric default null, p_renta numeric default null, p_sociedades numeric default null,
  p_iva numeric default null, p_auditoria int default null, p_bote numeric default null, p_decreto text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._admin();
  if least(p_tesoro, p_renta, p_sociedades, p_iva, p_auditoria, p_bote) < 0
     or greatest(p_renta, p_sociedades, p_iva, p_auditoria) > 100 then
    raise exception 'Valores fuera de rango (impuestos y auditoría, de 0 a 100)';
  end if;
  update public.gobierno
     set tesoro = coalesce(round(p_tesoro), tesoro),
         bote = coalesce(round(p_bote), bote),
         auditoria = coalesce(p_auditoria, auditoria),
         decreto = coalesce(left(trim(p_decreto), 140), decreto),
         impuestos = jsonb_build_object(
           'renta', coalesce(round(p_renta), (impuestos->>'renta')::numeric),
           'sociedades', coalesce(round(p_sociedades), (impuestos->>'sociedades')::numeric),
           'iva', coalesce(round(p_iva), (impuestos->>'iva')::numeric)),
         cambios_mes = 0, malversado_dia = 0
   where id = 1;
  return jsonb_build_object('ok', true, 'msg', 'Gobierno actualizado.');
end;
$$;

-- Nombra gobernador a dedo (o deja el cargo vacante con null).
create or replace function public.admin_gobernador(p_jugador uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nom text;
begin
  perform public._admin();
  if p_jugador is null then
    update public.gobierno set gobernador = null, gobernador_nombre = 'Vacante', decreto = '' where id = 1;
    perform public._noticia('🏛️', 'El cargo de gobernador queda vacante', 'Orden directa de arriba.');
    return jsonb_build_object('ok', true, 'msg', 'Cargo vacante.');
  end if;
  select nombre into v_nom from public.perfiles where id = p_jugador;
  if v_nom is null then raise exception 'Ese jugador no existe'; end if;
  update public.gobierno set gobernador = p_jugador, gobernador_nombre = v_nom, cambios_mes = 0, decreto = '' where id = 1;
  perform public._noticia('🪖', 'Golpe de Estado', v_nom || ' es el nuevo gobernador por decisión del admin.');
  perform public._aviso(p_jugador, '👑', 'El admin te ha nombrado gobernador.');
  return jsonb_build_object('ok', true, 'msg', v_nom || ' es el nuevo gobernador.');
end;
$$;

-- Cuenta los votos ya y deja la semana lista para otra ronda de candidatos.
create or replace function public.admin_elecciones() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_mes int := public.mes_de(public.dia_actual());
begin
  perform public._admin();
  perform 1 from public.gobierno where id = 1 for update;
  perform public._resolver(v_mes);
  delete from public.votos where mes = v_mes;
  delete from public.candidatos where mes = v_mes;
  return jsonb_build_object('ok', true, 'msg', 'Elecciones resueltas. Si alguien tenía votos, ya es gobernador.');
end;
$$;

-- p_clave vacía termina el evento actual.
create or replace function public.admin_evento(p_clave text, p_horas numeric default 24) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._admin();
  if coalesce(p_clave, '') = '' then
    update public.gobierno set evento = '', evento_fin = to_timestamp(0) where id = 1;
    delete from public.eventos_dia where dia = public.dia_actual();
    return jsonb_build_object('ok', true, 'msg', 'Evento terminado.');
  end if;
  if p_horas is null or p_horas <= 0 or p_horas > 720 then raise exception 'Duración entre 1 y 720 horas'; end if;
  perform public._poner_evento(p_clave, p_horas);
  return jsonb_build_object('ok', true, 'msg', 'Evento en marcha: ' || (public._evento_info(p_clave)->>'nombre'));
end;
$$;

create or replace function public.admin_noticia(p_icono text, p_titulo text, p_texto text, p_fija boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._admin();
  if trim(coalesce(p_titulo, '')) = '' then raise exception 'Falta el titular'; end if;
  insert into public.noticias (icono, titulo, texto, auto, fija)
  values (coalesce(nullif(left(trim(p_icono), 8), ''), '📰'), left(trim(p_titulo), 80), left(trim(coalesce(p_texto, '')), 300), false, coalesce(p_fija, false));
  return jsonb_build_object('ok', true, 'msg', 'Noticia publicada.');
end;
$$;

-- Con p_id null borra todas las noticias automáticas.
create or replace function public.admin_noticia_borrar(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._admin();
  if p_id is null then delete from public.noticias where auto;
  else delete from public.noticias where id = p_id; end if;
  return jsonb_build_object('ok', true, 'msg', 'Borrado.');
end;
$$;

-- Mensaje a un jugador (o a todos con p_jugador null). p_tipo 'tarta' sale a pantalla completa.
create or replace function public.admin_aviso(p_jugador uuid, p_texto text, p_tipo text default 'info') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_t text := left(trim(coalesce(p_texto, '')), 200); f record; v_n int := 0;
begin
  perform public._admin();
  if v_t = '' then raise exception 'Escribe el mensaje'; end if;
  if p_tipo not in ('info', 'tarta') then raise exception 'Tipo no válido'; end if;
  for f in select id from public.perfiles where (p_jugador is null or id = p_jugador) and not baneado loop
    perform public._aviso(f.id, case when p_tipo = 'tarta' then '🥧' else '📣' end, v_t, p_tipo);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'msg', 'Enviado a ' || v_n || case when v_n = 1 then ' jugador.' else ' jugadores.' end);
end;
$$;

-- Adelanta el reloj del juego p_dias días.
create or replace function public.admin_dia(p_dias int) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._admin();
  if p_dias is null or p_dias < 1 or p_dias > 30 then raise exception 'Entre 1 y 30 días'; end if;
  update public.gobierno set inicio = inicio - make_interval(days => p_dias) where id = 1;
  perform public.tick_global();
  return jsonb_build_object('ok', true, 'msg', 'Ahora es el día ' || public.dia_actual() || '.');
end;
$$;

create or replace function public.admin_cripto(p_precio numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._admin();
  if p_precio is null or p_precio < 1 or p_precio > 100000 then raise exception 'Precio entre 1 y 100000'; end if;
  update public.mercado set precio = round(p_precio, 2), historial = historial || to_jsonb(round(p_precio, 2)), actualizado = now() where id = 1;
  return jsonb_build_object('ok', true, 'msg', 'PanchoCoin ahora vale ' || round(p_precio, 2) || '.');
end;
$$;

create or replace function public.admin_chat(p_discord_id text, p_monedas int) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._admin();
  if p_monedas is null or p_monedas < 0 then raise exception 'Cantidad no válida'; end if;
  update public.monedas_chat set monedas = p_monedas, gastadas = least(gastadas, p_monedas) where discord_id = p_discord_id;
  if not found then raise exception 'Ese usuario no tiene monedas de chat'; end if;
  return jsonb_build_object('ok', true, 'msg', 'Monedas de chat fijadas a ' || p_monedas || '.');
end;
$$;

-- Borra toda la partida. Hay que escribir la palabra exacta para confirmar.
create or replace function public.admin_reset_todo(p_confirmar text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._admin();
  if p_confirmar is distinct from 'BORRAR TODO' then raise exception 'Escribe BORRAR TODO para confirmar'; end if;
  delete from public.votos where true;
  delete from public.candidatos where true;
  delete from public.loteria where true;
  delete from public.avisos where true;
  delete from public.noticias where auto;
  delete from public.eventos_dia where true;
  update public.gobierno
     set inicio = now(), tesoro = 1000, impuestos = '{"renta":15,"sociedades":20,"iva":10}', auditoria = 10,
         gobernador = null, gobernador_nombre = 'Gobierno inicial', mes_cerrado = 0, cambios_mes = 0,
         dia_global = 1, evento = '', evento_fin = to_timestamp(0), bote = 0, decreto = '', malversado_dia = 0
   where id = 1;
  update public.mercado set precio = 100, historial = '[100]', actualizado = now() where id = 1;
  update public.perfiles
     set saldo = public.aj('saldo_inicial'), sucio = 0, banco = 0, cripto = 0, xp = 0,
         empresas = '[]', lavados = '[]', inventario = '{}', escudo_hasta = 0, dia_procesado = 0,
         carcel_hasta = to_timestamp(0), candado_hasta = to_timestamp(0), mote = null, mote_hasta = to_timestamp(0),
         ultimo_trabajo = to_timestamp(0), ultimo_trabajo_sucio = to_timestamp(0), ultimo_robo = to_timestamp(0),
         ultimo_mendigar = to_timestamp(0), ultimo_diario = 0, racha = 0, cafe_n = 0, cafe_dia = 0
   where true;
  perform public._noticia('🌍', 'Empieza una partida nueva', 'Todo el mundo vuelve a la casilla de salida.');
  return jsonb_build_object('ok', true, 'msg', 'Partida reiniciada.');
end;
$$;

-- =====================================================================
-- 15. Permisos
-- =====================================================================

-- El ranking público incluye ahora el dinero del banco.
create or replace view public.ranking as
  select nombre, round(saldo + banco) as saldo from public.perfiles where not baneado order by saldo + banco desc limit 20;
grant select on public.ranking to authenticated, anon;

do $$
declare
  f record;
  -- Lo único que puede llamar la web. Todo lo demás queda cerrado.
  v_cliente text[] := array[
    'estado', 'ponerse_al_dia', 'dia_actual', 'soy_dueno', 'mis_monedas_chat', 'avisos_leidos',
    'trabajar', 'mendigar', 'diario', 'depositar', 'retirar', 'transferir',
    'trabajo_sucio', 'robar', 'fianza', 'lavar', 'sabotear',
    'fundar', 'mejorar', 'vender_empresa', 'comprar',
    'moneda', 'tragaperras', 'ruleta_rusa', 'loteria_comprar', 'cripto_comprar', 'cripto_vender',
    'presentarse', 'votar', 'comprar_votos', 'gob_impuestos', 'gob_auditoria', 'gob_decreto', 'gob_paga_extra', 'gob_malversar',
    'canjear_chat', 'enviar_voz', 'pedir_sonido',
    'admin_estado', 'admin_ajuste', 'admin_ajustes_reset', 'admin_sector', 'admin_sector_borrar', 'admin_dinero', 'admin_lluvia',
    'admin_carcel', 'admin_ban', 'admin_mote', 'admin_renombrar', 'admin_esperas', 'admin_reset_jugador', 'admin_gobierno',
    'admin_gobernador', 'admin_elecciones', 'admin_evento', 'admin_noticia', 'admin_noticia_borrar', 'admin_aviso',
    'admin_dia', 'admin_cripto', 'admin_chat', 'admin_reset_todo'];
begin
  for f in
    select p.oid::regprocedure as firma, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')  -- no tocar extensiones
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.firma);
    if f.proname = any (v_cliente) then
      execute format('grant execute on function %s to authenticated', f.firma);
    end if;
  end loop;
end;
$$;

-- El bot entra con la clave secreta (service_role) y solo necesita esto.
grant usage on schema public to service_role;
grant select, insert, update, delete on public.voz_pendiente, public.sonido_pendiente, public.monedas_chat to service_role;
grant usage, select on all sequences in schema public to service_role;
grant select on public.ranking_chat to service_role;
grant execute on function public.sumar_moneda(text, text) to service_role;

-- Avisa a la API de Supabase de que hay funciones nuevas.
notify pgrst, 'reload schema';
