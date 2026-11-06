// Registra los comandos en tu servidor. Ejecuta: npm run registrar
const { REST, Routes, SlashCommandBuilder } = require('discord.js');

if (!process.env.DISCORD_TOKEN || !process.env.CLIENT_ID || !process.env.GUILD_ID) {
  console.error('Faltan DISCORD_TOKEN, CLIENT_ID o GUILD_ID en .env'); process.exit(1);
}

const comandos = [
  new SlashCommandBuilder().setName('poner').setDescription('Pone una pista de la carpeta musica en tu canal de voz')
    .addStringOption(o => o.setName('pista').setDescription('Nombre de la pista').setRequired(true).setAutocomplete(true)),
  new SlashCommandBuilder().setName('pausa').setDescription('Pausa la música'),
  new SlashCommandBuilder().setName('seguir').setDescription('Sigue con la música pausada'),
  new SlashCommandBuilder().setName('saltar').setDescription('Salta a la siguiente pista'),
  new SlashCommandBuilder().setName('cola').setDescription('Muestra la cola de reproducción'),
  new SlashCommandBuilder().setName('parar').setDescription('Para la música y saca al bot del canal'),
].map(c => c.toJSON());

const rest = new REST().setToken(process.env.DISCORD_TOKEN);
rest.put(Routes.applicationGuildCommands(process.env.CLIENT_ID, process.env.GUILD_ID), { body: comandos })
  .then(() => console.log('Comandos registrados en tu servidor.'))
  .catch(err => console.error(err));
