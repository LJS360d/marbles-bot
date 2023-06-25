import {
    ChatInputCommandInteraction,
    Client,
    EmbedBuilder,
    GatewayIntentBits,
    GuildTextBasedChannel,
    MessageReaction,
    User,
} from 'discord.js';

import { commands } from './Commands';
import {
    EventManager,
    loadSpawnChannels,
    spawnChannels,
} from './EventManager';
import {
    collections,
    loadAllCollections,
    MarbleCollection,
} from './MarbleCollections';
import {
    getMarbleByName,
    loadMarblesData,
} from './MarblesData';

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

const client = new Client(options);
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
                await interaction.reply('Spawning...')
                EventManager.spawnMarble(interaction.channel)
                break;
            case "collection":
                const collection = collections.get(`${interaction.user.id}-${interaction.guildId}`);

                const collectionEmbed = new EmbedBuilder()
                    .setTitle(`Your Collection ${collection ? `${collection.size} Marbles` : "is Empty"}`);
                if (collection !== undefined) {
                    const marbles = collection.getMarblesNames();
                    marbles.forEach((marble) => {
                        collectionEmbed.addFields(
                            { name: `${marble}`, value: `x${collection.getValue(marble)}` },
                        )
                    })
                }
                await interaction.reply({
                    embeds: [collectionEmbed]
                })
                break;

        }
    })
    client.on('messageReactionAdd', async (reaction: MessageReaction, user: User) => {
        if (user.bot) return; // Ignore reactions from other bots

        const embed = reaction.message.embeds[0]
        const emoji = embed.fields.at(-1).value.split(' ')[1]

        if (reaction.message.author.id === client.user.id && reaction.emoji.name == emoji) {
            // Delete the message
            reaction.message.delete();
            const marbleName = embed.title.split('`')[1]
            const marble = getMarbleByName(marbleName)

            // When instanciating a new MarbleCollection the object gets automatically 
            // added to the collections map, in the constructor
            const collection = collections.get(user.id + reaction.message.guildId) ?? new MarbleCollection(user.id, reaction.message.guildId);

            collection.add(marble.name)

            //TODO Find a less expensive way to save collections
            collection.saveCollection()


            const responseEmbed = new EmbedBuilder()
                .setColor(embed.color)
                .setDescription(`<@${user.id}> ${reaction.emoji} \n\n\`${marbleName}\` Was added to your collection.`)
                .setImage(embed.image.url)
                .setThumbnail(embed.thumbnail.url)

            await reaction.message.channel.send({
                embeds: [responseEmbed]
            });
        }
    });
} catch (error) {
    console.log(error);
}


client.login(TOKEN);
setInterval(spawnRoutine, 1000 * 60 * 10) // 10 minutes
function spawnRoutine() {
    for (const channelId of spawnChannels) {
        const channel = client.channels.cache.get(channelId) as GuildTextBasedChannel
        EventManager.spawnMarble(channel)
    }
}