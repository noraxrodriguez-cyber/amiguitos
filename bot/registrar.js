// Registra los comandos en tu servidor. Ejecuta: npm run registrar
const { REST, Routes, SlashCommandBuilder } = require('discord.js');

if (!process.env.DISCORD_TOKEN || !process.env.CLIENT_ID || !process.env.GUILD_ID) {
  console.error('Faltan DISCORD_TOKEN, CLIENT_ID o GUILD_ID en .env'); process.exit(1);
}

const comandos = [
  new SlashCommandBuilder().setName('ayuda').setDescription('Lista de comandos del bot'),
  new SlashCommandBuilder().setName('entrar').setDescription('Me meto en tu canal de voz y me quedo'),
  new SlashCommandBuilder().setName('salir').setDescription('Me salgo del canal de voz'),
  new SlashCommandBuilder().setName('poner').setDescription('Pone una pista de la carpeta musica')
    .addStringOption(o => o.setName('pista').setDescription('Nombre de la pista').setRequired(true).setAutocomplete(true)),
  new SlashCommandBuilder().setName('decir').setDescription('Digo un texto en voz alta en el canal')
    .addStringOption(o => o.setName('texto').setDescription('Lo que tengo que decir (máx. 200)').setRequired(true))
    .addBooleanOption(o => o.setName('interrumpir').setDescription('Cortar lo que suene ahora (por defecto sí)')),
  new SlashCommandBuilder().setName('pausa').setDescription('Pausa la música'),
  new SlashCommandBuilder().setName('seguir').setDescription('Sigue con la música pausada'),
  new SlashCommandBuilder().setName('saltar').setDescription('Salta a la siguiente pista'),
  new SlashCommandBuilder().setName('parar').setDescription('Para la música (me quedo en el canal)'),
  new SlashCommandBuilder().setName('cola').setDescription('Muestra la cola de reproducción'),
  new SlashCommandBuilder().setName('volumen').setDescription('Cambia el volumen de la música')
    .addIntegerOption(o => o.setName('nivel').setDescription('De 0 a 100').setRequired(true).setMinValue(0).setMaxValue(100)),
  new SlashCommandBuilder().setName('estado').setDescription('Qué está haciendo el bot ahora'),
  new SlashCommandBuilder().setName('monedas').setDescription('Tus monedas de chat'),
  new SlashCommandBuilder().setName('ranking').setDescription('Top 10 de monedas de chat'),
].map(c => c.toJSON());

const rest = new REST().setToken(process.env.DISCORD_TOKEN);
rest.put(Routes.applicationGuildCommands(process.env.CLIENT_ID, process.env.GUILD_ID), { body: comandos })
  .then(() => console.log(`Comandos registrados (${comandos.length}).`))
  .catch(err => console.error(err));
