// Pancho el Tesorero · bot de música para AMIGUITOS
const fs = require('fs');
const path = require('path');
const { Client, GatewayIntentBits } = require('discord.js');
const { createClient } = require('@supabase/supabase-js');
const {
  joinVoiceChannel, createAudioPlayer, createAudioResource, AudioPlayerStatus,
  VoiceConnectionStatus, entersState, NoSubscriberBehavior, getVoiceConnection
} = require('@discordjs/voice');

if (!process.env.DISCORD_TOKEN) { console.error('Falta DISCORD_TOKEN en el archivo .env'); process.exit(1); }

const CARPETA = path.join(__dirname, 'musica');
const EXTENSIONES = ['.mp3', '.ogg', '.wav', '.m4a'];
const colas = new Map(); // guildId -> { player, cola: [], actual }

function pistas() {
  return fs.readdirSync(CARPETA).filter(f => EXTENSIONES.includes(path.extname(f).toLowerCase()));
}

function estado(guildId) {
  if (!colas.has(guildId)) {
    const player = createAudioPlayer({ behaviors: { noSubscriber: NoSubscriberBehavior.Pause } });
    const e = { player, cola: [], actual: null };
    const pasar = () => { e.actual = null; siguiente(guildId); };
    player.on(AudioPlayerStatus.Idle, pasar);
    player.on('error', err => { console.error('Error de reproducción:', err.message); pasar(); });
    colas.set(guildId, e);
  }
  return colas.get(guildId);
}

function siguiente(guildId) {
  const e = colas.get(guildId);
  if (!e || e.actual || e.cola.length === 0) return;
  e.actual = e.cola.shift();
  e.player.play(createAudioResource(path.join(CARPETA, e.actual)));
}

const supabase = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_KEY
  ? createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, { auth: { persistSession: false } })
  : null;

const client = new Client({
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildVoiceStates, GatewayIntentBits.GuildMessages]
});
client.once('ready', () => console.log('Conectado como ' + client.user.tag));

client.on('interactionCreate', async i => {
  if (i.isAutocomplete() && i.commandName === 'poner') {
    const texto = i.options.getFocused().toLowerCase();
    return i.respond(pistas().filter(p => p.toLowerCase().includes(texto)).slice(0, 25).map(p => ({ name: p, value: p })));
  }
  if (!i.isChatInputCommand()) return;

  const e = estado(i.guildId);
  const voz = i.member?.voice?.channel;

  if (i.commandName === 'poner') {
    if (!voz) return i.reply({ content: 'Entra primero en un canal de voz.', ephemeral: true });
    const pista = i.options.getString('pista');
    if (!pistas().includes(pista)) return i.reply({ content: 'Esa pista no está en la carpeta musica.', ephemeral: true });

    if (!getVoiceConnection(i.guildId)) {
      await i.deferReply();
      const conexion = joinVoiceChannel({ channelId: voz.id, guildId: i.guildId, adapterCreator: i.guild.voiceAdapterCreator });
      conexion.subscribe(e.player);
      try { await entersState(conexion, VoiceConnectionStatus.Ready, 15_000); }
      catch { conexion.destroy(); return i.editReply('No pude conectarme al canal de voz.'); }
      e.cola.push(pista); siguiente(i.guildId);
      return i.editReply(e.actual === pista ? `▶️ Sonando: **${pista}**` : `🎶 En cola: **${pista}**`);
    }
    e.cola.push(pista); siguiente(i.guildId);
    return i.reply(e.actual === pista ? `▶️ Sonando: **${pista}**` : `🎶 En cola: **${pista}**`);
  }

  if (i.commandName === 'pausa') { e.player.pause(); return i.reply('⏸️ Pausado.'); }
  if (i.commandName === 'seguir') { e.player.unpause(); return i.reply('▶️ Sigue.'); }
  if (i.commandName === 'saltar') { e.player.stop(); return i.reply('⏭️ Saltada.'); }
  if (i.commandName === 'cola') {
    const lineas = [e.actual ? `▶️ Ahora: **${e.actual}**` : 'Nada sonando.', ...e.cola.map((p, n) => `${n + 1}. ${p}`)];
    return i.reply(lineas.join('\n'));
  }
  if (i.commandName === 'parar') {
    e.cola = []; e.actual = null; e.player.stop(true);
    getVoiceConnection(i.guildId)?.destroy();
    return i.reply('⏹️ Parado. Me voy del canal.');
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
