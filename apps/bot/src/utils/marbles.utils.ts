import { EmbedBuilder, type GuildTextBasedChannel } from 'discord.js';
import Container from 'typedi';
import type { MarbleDocumentFields } from '../datastore/structure/marbles/models/marble.model';
import type { TeamDocumentFields } from '../datastore/structure/teams/models/team.model';
import TeamsService from '../datastore/structure/teams/services/teams.service';
import { getRandomDiscordColor } from './random.utils';
import {
	getMarbleSpawnDescription,
	getMarbleSpawnTitle,
	getRandomEmoji,
} from './text.utils';

const imageUnavailable =
	'https://raw.githubusercontent.com/LJS360d/marbles-bot/master/public/assets/image_unavailable.png';

const blankTeam: TeamDocumentFields = {
	coach: 'None',
	color: 'Unknown',
	logo: imageUnavailable,
	manager: 'None',
	members: [],
	name: 'None',
};

const blankMarble: MarbleDocumentFields = {
	color: 'Unknown',
	competition: '',
	extra: 'Clearly we are missing some data for this marble',
	image: imageUnavailable,
	name: 'Blank',
	position: '',
	team: '',
};

export async function spawnMarble(
	channel: GuildTextBasedChannel,
	marble: MarbleDocumentFields
) {
	const team =
		(await Container.get(TeamsService).getMarbleTeam(marble)) ?? blankTeam;

	const embed = new EmbedBuilder()
		.setColor(getRandomDiscordColor())
		.setTitle(getMarbleSpawnTitle(marble.name))
		.setDescription(getMarbleSpawnDescription(marble))
		.setThumbnail(team.logo)
		.addFields(
			{ name: 'Team', value: `\`${team.name}\`` },
			{ name: 'Manager', value: team.manager, inline: true },
			{ name: 'Coach', value: team.coach, inline: true },
			{ name: 'Collect', value: `React with ${getRandomEmoji()} to collect` }
		)
		.setImage(marble.image || blankMarble.image);
	return await channel.send({
		embeds: [embed],
	});
}
