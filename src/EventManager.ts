import {
    ChatInputCommandInteraction,
    EmbedBuilder,
    GuildTextBasedChannel,
} from 'discord.js';
import {
    readFileSync,
    writeFileSync,
} from 'fs';

import {
    getRandomEmoji,
    getRandomSpawnMessage,
} from './Emojis';
import {
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
            .setTitle(`${(rarity.name == 'Uncommon' || rarity.name == 'Epic') ? 'An' : 'A'} ${rarity.name} \`${marble.name}\` ${getRandomSpawnMessage()}!`)
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

    static async toggleSpawn(interaction: ChatInputCommandInteraction) {
        if (!spawnChannels.has(interaction.channelId)) {
            spawnChannels.add(interaction.channelId);
            await interaction.reply(`Marbles will now spawn in **${interaction.channel.name}**`);

        }
        else {
            spawnChannels.delete(interaction.channelId);
            await interaction.reply(`Marbles will **no longer** spawn in **${interaction.channel.name}**`);

        }
        writeFileSync('./data/spawnChannels.json', JSON.stringify(Array.from(spawnChannels)));
    }
}

export function loadSpawnChannels() {
    const data = readFileSync('./data/spawnChannels.json', 'utf-8');
    JSON.parse(data).forEach((channel: string) => {
        spawnChannels.add(channel);
    });
}

