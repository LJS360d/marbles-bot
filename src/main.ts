import {
    ChatInputCommandInteraction,
    Client,
    GatewayIntentBits,
    GuildTextBasedChannel,
    Message,
    MessageReaction,
    User,
} from 'discord.js';

import { startAdminServer } from './AdminServer';
import { commands } from './Commands';
import {
    EventManager,
    loadSpawnChannels,
    spawnChannels,
} from './EventManager';
import { loadAllCollections } from './MarbleCollections';
import { loadMarblesData } from './MarblesData';

// IMPORTANT !!!
loadMarblesData()

require('dotenv').config();

const TOKEN = process.env['TOKEN'];
const options = {
    intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMembers,
        GatewayIntentBits.GuildScheduledEvents,
        // GatewayIntentBits.GuildInvites,
        // GatewayIntentBits.GuildPresences,
        // GatewayIntentBits.GuildVoiceStates,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.GuildMessageReactions,
        GatewayIntentBits.GuildMessageTyping,
        // GatewayIntentBits.DirectMessages,
        // GatewayIntentBits.DirectMessageReactions,
        // GatewayIntentBits.DirectMessageTyping,
        GatewayIntentBits.MessageContent,
    ],
}

export const client = new Client(options);
try {
    client.on('ready', () => {
        refreshCommands().then(() => { console.log('Successfully reloaded application (/) commands.') })
        console.log(`Logged in as ${client.user!.tag}!`);
        //Loading Routines
        loadAllCollections()
        loadSpawnChannels()
        async function refreshCommands(): Promise<void> {
            try {
                console.log('Started refreshing application (/) commands.');
                await client.application?.commands.set(commands);
            } catch (error) { console.error(error) }
        }
    })
    client.on('interactionCreate', async function (interaction: ChatInputCommandInteraction) {
        switch (interaction.commandName) {
            case 'togglespawn':
                EventManager.toggleSpawn(interaction)
                break;
            case 'spawn':
                if (EventManager.checkAdmin(interaction)) {
                    await interaction.reply('Spawning...')
                    EventManager.spawnMarble(interaction.channel)
                }
                break;
            case "collection":
                EventManager.showCollection(interaction);
                break;

        }
    })
    client.on('messageReactionAdd', async (reaction: MessageReaction, user: User) => {
        EventManager.reactionAdded(reaction, user);
    });
    client.on('messageCreate', (message: Message) => {
        if (message.author.id === client.user.id) return;
        const onePercent = Math.floor(Math.random() * 100)
        if (onePercent === 1) {
            EventManager.spawnMarble(message.channel as GuildTextBasedChannel)
        }

    })
} catch (error) {
    console.log(error);
}


client.login(TOKEN);
export let remainingTime = 1000 * 60 * 30; // 30 minutes
setInterval(spawnRoutine, remainingTime)
setInterval(() => { remainingTime -= 1000; }, 1000)
startAdminServer()
function spawnRoutine() {
    for (const channelId of spawnChannels) {
        const channel = client.channels.cache.get(channelId) as GuildTextBasedChannel
        EventManager.spawnMarble(channel)
    }
    remainingTime = 1000 * 60 * 30;
}