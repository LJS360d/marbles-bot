import {
    ChatInputCommandInteraction,
    EmbedBuilder,
    GuildTextBasedChannel,
    MessageReaction,
    PermissionsBitField,
    User,
} from 'discord.js';
import {
    readFileSync,
    writeFileSync,
} from 'fs';

import {
    getRandomEmoji,
    getRandomSpawnMessage,
} from './Emojis';
import { client } from './main';
import {
    collections,
    MarbleCollection,
} from './MarbleCollections';
import {
    getMarbleByName,
    getRandomMarble,
    getRandomRarity,
    getTeamByMarble,
} from './MarblesData';

export const spawnChannels: Set<string> = new Set<string>();
export class EventManager {
    constructor() { }

    static async spawnMarble(channel: GuildTextBasedChannel) {
        const marble = getRandomMarble()
        const team = getTeamByMarble(marble)
        const rarity = getRandomRarity()

        const embed = new EmbedBuilder()
            .setColor(rarity.color)
            .setTitle(`${(["a", "e", "i", "o", "u"].includes(rarity.name[0].toLowerCase())) ? 'An' : 'A'} ${rarity.name} \`${marble.name}\` ${getRandomSpawnMessage()}!`)
            .setDescription(team.color)
            .setThumbnail(team.logo)
            .addFields(
                { name: 'Team', value: `\`${team.name}\`` },
                { name: 'Manager', value: team.manager, inline: true },
                { name: 'Coach', value: team.coach, inline: true },
                { name: 'React', value: `With ${getRandomEmoji()} to collect` },
            )
            .setImage(marble.image)
        await channel.send({
            embeds: [embed]
        });


    }

    static async showCollection(interaction: ChatInputCommandInteraction) {
        const collection = collections.get(`${interaction.user.id}-${interaction.guildId}`);
        const title = `Your collection${(collection) ? `: ${collection.size} unique ${((collection.size === 1) ? "Marble" : "Marbles")}` : "is Empty"}`
        const collectionEmbed = new EmbedBuilder()
            .setTitle(title);
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
    }

    static async toggleSpawn(interaction: ChatInputCommandInteraction) {
        if (!spawnChannels.has(interaction.channelId)) {
            spawnChannels.add(interaction.channelId);
            await interaction.reply(`Marbles will now spawn in **#${interaction.channel.name}**`);

        }
        else {
            spawnChannels.delete(interaction.channelId);
            await interaction.reply(`Marbles will **no longer** spawn in **#${interaction.channel.name}**`);

        }
        writeFileSync('./data/spawnChannels.json', JSON.stringify(Array.from(spawnChannels)));
    }

    static async reactionAdded(reaction: MessageReaction, user: User) {
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
            const collection = collections.get(`${user.id}-${reaction.message.guildId}`) ?? new MarbleCollection(user.id, reaction.message.guildId);

            collection.add(marble.name)
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
    }

    static async checkAdmin(interaction: ChatInputCommandInteraction) {
        if (!(interaction.member.permissions as Readonly<PermissionsBitField>).has('Administrator')) {
            await interaction.reply({ content: 'You are not authorized to use this command.', ephemeral: true });
            return false;
        } return true;
    }
}
export function loadSpawnChannels() {
    const data = readFileSync('./data/spawnChannels.json', 'utf-8');
    JSON.parse(data).forEach((channel: string) => {
        spawnChannels.add(channel);
    });
}
