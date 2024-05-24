import { EmbedBuilder, type ChatInputCommandInteraction } from 'discord.js';
import {
	Command,
	DiscordHandler,
	HandlerType,
	paginateInteraction,
} from 'fonzi2';
import type CollectionsService from '../../datastore/structure/collections/services/collections.service';
import type MarblesService from '../../datastore/structure/marbles/services/marbles.service';
import type TeamsService from '../../datastore/structure/teams/services/teams.service';
import { spawnMarble } from '../../utils/marbles.utils';
import { ensureAdminInteraction } from '../../utils/permission.utils';
import CountingSet from '../../datastore/structure/counting.set';
import { chunkArray } from '../../utils/pagination.utils';

export class CommonCommandsHandler extends DiscordHandler {
	public readonly type = HandlerType.commandInteraction;

	constructor(
		private version: string,
		private marblesService: MarblesService,
		private teamsService: TeamsService,
		private collectionsService: CollectionsService
	) {
		super();
	}

	@Command({ name: 'version', description: 'returns the application version' })
	public async onVersion(interaction: ChatInputCommandInteraction<'cached'>) {
		await interaction.reply(this.version);
	}

	@Command({
		name: 'spawn',
		description: 'forces a marble spawn (requires admin)',
	})
	public async onTest(interaction: ChatInputCommandInteraction<'cached'>) {
		if (!ensureAdminInteraction(interaction)) return;
		const marble = await this.marblesService.getOneRandom();
		void spawnMarble(interaction.channel!, marble);
		await interaction.reply({ content: 'Spawning...', ephemeral: true });
	}

	@Command({
		name: 'collection',
		description: 'shows your collection',
	})
	public async onCollection(
		interaction: ChatInputCommandInteraction<'cached'>
	) {
		const collectionDoc = await this.collectionsService.getOne(
			interaction.guildId,
			interaction.user.id
		);
		if (!collectionDoc) {
			void interaction.reply({
				content: 'Your collection could not be found',
			});
			return;
		}
		const collection = CountingSet.fromJson(collectionDoc.marbles);
		if (collection.size < 1) {
			const emptyCollectionEmbed = new EmbedBuilder()
				.setTitle('Your collection is empty!')
				.setColor('Gold')
				.setDescription('Type in the chat and collect some marbles')
				.setThumbnail(this.client.user.avatarURL());
			await interaction.reply({
				embeds: [emptyCollectionEmbed],
			});
			return;
		}
		const title = `Your collection: ${collection.size} unique marble${
			collection.size > 1 ? 's' : ''
		}`;
		const collectionFields = collection.toJson().map(([marble, count]) => ({
			name: marble,
			value: `×${count}`,
			inline: true,
		}));

		const embeds = chunkArray(collectionFields, 15).map((fields) =>
			new EmbedBuilder()
				.setTitle(title)
				.setColor('Gold')
				.setThumbnail(this.client.user.avatarURL())
				.addFields({ name: '\t', value: '\t' })
				.addFields(fields)
		);
		await paginateInteraction(interaction, embeds);
	}
}
