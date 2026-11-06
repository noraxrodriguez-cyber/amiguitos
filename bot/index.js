// Pancho el Tesorero · bot de AMIGUITOS (música, voz, monedas y ranking)
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');
const { Client, GatewayIntentBits } = require('discord.js');
const { createClient } = require('@supabase/supabase-js');
const {
  joinVoiceChannel, createAudioPlayer, createAudioResource, AudioPlayerStatus,
  VoiceConnectionStatus, entersState, NoSubscriberBehavior
} = require('@discordjs/voice');

if (!process.env.DISCORD_TOKEN) { console.error('Falta DISCORD_TOKEN en .env'); process.exit(1); }

const CARPETA = path.join(__dirname, 'musica');
const EXTENSIONES = ['.mp3', '.ogg', '.wav', '.m4a'];
const TTS_CMD = process.env.TTS_CMD || 'espeak-ng';
const TTS_VOZ = process.env.TTS_VOZ || 'es';

const supabase = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_KEY
  ? createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, { auth: { persistSession: false } })
  : null;

const estados = new Map(); // guildId -> { player, conexion, canal, cola, actual, volumen }

const AYUDA = [
  '**Música**',
  '`/poner pista` · pone una pista de la carpeta musica (o la mete en cola)',
  '`/pausa` · `/seguir` · `/saltar` · `/parar` · `/cola` · `/volumen nivel`',
  '**Voz**',
  '`/entrar` · me meto en tu canal y me quedo',
  '`/salir` · me salgo del canal',
  '(La voz se manda desde la pestaña Voz de la web.)',
  '**Economía del chat**',
  '`/monedas` · tus monedas de chat · `/ranking` · top 10',
  '**Otros**',
  '`/estado` · qué estoy haciendo · `/ayuda` · esta lista'
].join('\n');

function pistas() {
  return fs.readdirSync(CARPETA).filter(f => EXTENSIONES.includes(path.extname(f).toLowerCase()));
}
const nombreItem = x => (x.tipo === 'voz' ? '🗣️ voz' : x.nombre);

function estado(guildId) {
  if (!estados.has(guildId)) {
    const player = createAudioPlayer({ behaviors: { noSubscriber: NoSubscriberBehavior.Pause } });
    const e = { player, conexion: null, canal: null, cola: [], actual: null, volumen: 0.5 };
    const pasar = () => {
      if (e.actual?.tipo === 'voz') fs.rm(e.actual.ruta, () => {});
      e.actual = null;
      siguiente(guildId);
    };
    player.on(AudioPlayerStatus.Idle, pasar);
    player.on('error', err => { console.error('Error de reproducción:', err.message); pasar(); });
    estados.set(guildId, e);
  }
  return estados.get(guildId);
}

function siguiente(guildId) {
  const e = estados.get(guildId);
  if (!e || e.actual || e.cola.length === 0) return;
  e.actual = e.cola.shift();
  const origen = e.actual.tipo === 'voz' ? e.actual.ruta : path.join(CARPETA, e.actual.nombre);
  const recurso = createAudioResource(origen, { inlineVolume: true });
  recurso.volume?.setVolume(e.volumen);
  e.player.play(recurso);
}

// Se mete en el canal y se queda. Si Discord la desconecta, vuelve a entrar.
async function unirse(guild, channelId, e) {
  e.conexion?.destroy();
  const conexion = joinVoiceChannel({ channelId, guildId: guild.id, adapterCreator: guild.voiceAdapterCreator });
  conexion.subscribe(e.player);
  e.conexion = conexion; e.canal = channelId;

  conexion.on(VoiceConnectionStatus.Disconnected, async () => {
    try {
      await Promise.race([
        entersState(conexion, VoiceConnectionStatus.Signalling, 5_000),
        entersState(conexion, VoiceConnectionStatus.Connecting, 5_000)
      ]);
    } catch {
      if (e.conexion !== conexion) return;
      conexion.destroy(); e.conexion = null;
      setTimeout(() => { if (e.canal === channelId) unirse(guild, channelId, e).catch(() => {}); }, 3_000);
    }
  });

  try { await entersState(conexion, VoiceConnectionStatus.Ready, 15_000); }
  catch (err) { conexion.destroy(); e.conexion = null; e.canal = null; throw new Error('No pude conectarme al canal de voz.'); }
  return conexion;
}

async function asegurarVoz(i, e) {
  if (e.conexion) return true;
  const voz = i.member?.voice?.channel;
  if (!voz) return false;
  await unirse(i.guild, voz.id, e);
  return true;
}

// Genera el audio con un motor local (espeak-ng por defecto). Sin shell: el texto no se interpreta.
function hablar(texto, ruta) {
  return new Promise((resolve, reject) => {
    execFile(TTS_CMD, ['-v', TTS_VOZ, '-w', ruta, '--', texto], err => {
      if (err) reject(new Error(`No pude generar la voz. Hay que instalar ${TTS_CMD} en el servidor.`));
      else resolve();
    });
  });
}

async function decirEnCanal(texto) {
  const guild = client.guilds.cache.get(process.env.GUILD_ID) || client.guilds.cache.first();
  if (!guild) return;
  const e = estado(guild.id);
  if (!e.conexion) {
    if (!process.env.VOZ_CANAL_ID) { console.error('Falta VOZ_CANAL_ID en .env para hablar sin estar en un canal'); return; }
    await unirse(guild, process.env.VOZ_CANAL_ID, e);
  }
  const ruta = path.join(os.tmpdir(), `voz-${Date.now()}.wav`);
  await hablar(texto, ruta);
  e.cola.unshift({ tipo: 'voz', ruta });
  e.player.stop(true); // corta lo que suene y pasa a la voz
  siguiente(guild.id);
}

// Revisa cada 2 s si la web ha enviado algún texto para decir.
async function vigilarVoz() {
  if (!supabase) return;
  try {
    const { data } = await supabase.from('voz_pendiente').select('id, texto').eq('hecho', false).order('id').limit(1);
    const orden = data?.[0];
    if (orden) {
      await supabase.from('voz_pendiente').update({ hecho: true }).eq('id', orden.id);
      await decirEnCanal(orden.texto);
    }
  } catch (err) { console.error('Voz:', err.message); }
  setTimeout(vigilarVoz, 2000);
}

async function ejecutar(cmd, i, e) {
  switch (cmd) {
    case 'ayuda': return AYUDA;

    case 'entrar': {
      const voz = i.member?.voice?.channel;
      if (!voz) return 'Entra primero en un canal de voz.';
      if (e.conexion && e.canal === voz.id) return 'Ya estoy aquí. No me muevo.';
      await unirse(i.guild, voz.id, e);
      return `🔊 Me he metido en **${voz.name}**. Me quedo hasta que uses /salir.`;
    }

    case 'salir': {
      if (!e.conexion) return 'No estoy en ningún canal.';
      e.cola = []; e.player.stop(true); e.actual = null;
      e.conexion.destroy(); e.conexion = null; e.canal = null;
      return '👋 Me salgo del canal.';
    }

    case 'poner': {
      if (!(await asegurarVoz(i, e))) return 'Entra primero en un canal de voz.';
      const pista = i.options.getString('pista');
      if (!pistas().includes(pista)) return 'Esa pista no está en la carpeta musica.';
      e.cola.push({ tipo: 'musica', nombre: pista });
      siguiente(i.guildId);
      return e.actual?.nombre === pista ? `▶️ Sonando: **${pista}**` : `🎶 En cola: **${pista}**`;
    }

    case 'pausa': e.player.pause(); return '⏸️ Pausado.';
    case 'seguir': e.player.unpause(); return '▶️ Sigo.';
    case 'saltar': e.player.stop(); return '⏭️ Saltada.';
    case 'parar': e.cola = []; e.player.stop(true); e.actual = null; return '⏹️ Música parada. Sigo en el canal.';

    case 'cola': {
      const lineas = [e.actual ? `▶️ Ahora: **${nombreItem(e.actual)}**` : 'Nada sonando.',
        ...e.cola.map((x, n) => `${n + 1}. ${nombreItem(x)}`)];
      return lineas.join('\n');
    }

    case 'volumen': {
      e.volumen = i.options.getInteger('nivel') / 100;
      e.player.state.resource?.volume?.setVolume(e.volumen);
      return `🔈 Volumen al ${Math.round(e.volumen * 100)} %.`;
    }

    case 'estado': {
      const canal = e.canal ? i.guild.channels.cache.get(e.canal)?.name : null;
      return [
        `Canal: ${canal ? '**' + canal + '**' : 'ninguno'}`,
        `Sonando: ${e.actual ? nombreItem(e.actual) : 'nada'}`,
        `En cola: ${e.cola.length}`,
        `Volumen: ${Math.round(e.volumen * 100)} %`,
        `Motor de voz: ${TTS_CMD} (${TTS_VOZ})`
      ].join('\n');
    }

    case 'monedas': {
      if (!supabase) return 'Falta configurar Supabase en el bot.';
      const { data, error } = await supabase.from('monedas_chat').select('monedas').eq('discord_id', i.user.id).maybeSingle();
      if (error) throw error;
      return `💬 Tienes **${data?.monedas ?? 0}** monedas de chat.`;
    }

    case 'ranking': {
      if (!supabase) return 'Falta configurar Supabase en el bot.';
      const { data, error } = await supabase.from('ranking_chat').select('nombre, monedas')
        .order('monedas', { ascending: false }).limit(10);
      if (error) throw error;
      return (data || []).map((r, n) => `${['🥇', '🥈', '🥉'][n] || (n + 1) + '.'} ${r.nombre} · ${r.monedas}`).join('\n')
        || 'Nadie ha escrito todavía.';
    }

    default: return 'Comando no reconocido.';
  }
}

const client = new Client({
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildVoiceStates, GatewayIntentBits.GuildMessages]
});
client.once('ready', () => { console.log('Conectado como ' + client.user.tag); vigilarVoz(); });

client.on('interactionCreate', async i => {
  if (i.isAutocomplete() && i.commandName === 'poner') {
    const texto = i.options.getFocused().toLowerCase();
    return i.respond(pistas().filter(p => p.toLowerCase().includes(texto)).slice(0, 25).map(p => ({ name: p, value: p })));
  }
  if (!i.isChatInputCommand()) return;
  const e = estado(i.guildId);
  try {
    await i.deferReply();
    await i.editReply(await ejecutar(i.commandName, i, e));
  } catch (err) {
    console.error(i.commandName, err.message);
    await i.editReply('⚠️ ' + (err.message || 'Algo salió mal.')).catch(() => {});
  }
});

// Una moneda por mensaje en el servidor (no cuenta bots ni otros servidores).
client.on('messageCreate', async m => {
  if (m.author.bot || !m.guildId || !supabase) return;
  if (process.env.GUILD_ID && m.guildId !== process.env.GUILD_ID) return;
  const nombre = m.member?.displayName || m.author.username;
  const { error } = await supabase.rpc('sumar_moneda', { p_discord_id: m.author.id, p_nombre: nombre });
  if (error) console.error('Error sumando moneda:', error.message);
});

client.login(process.env.DISCORD_TOKEN);
