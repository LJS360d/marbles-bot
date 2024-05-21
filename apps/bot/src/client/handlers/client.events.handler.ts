import {
	EmbedBuilder,
	type ApplicationCommandData,
	type MessageReaction,
	type User,
} from 'discord.js';
import { ClientEvent, DiscordHandler, HandlerType, Logger } from 'fonzi2';
import type CollectionsService from '../../datastore/structure/collections/services/collections.service';
import type MarblesService from '../../datastore/structure/marbles/services/marbles.service';
import { BroadcastController } from '../../server/controllers/broadcast.controller';
import { HtmxController } from '../../server/controllers/htmx.controller';
import { MarblesServer } from '../../server/server';

export default class ClientEventsHandler extends DiscordHandler {
	public readonly type = HandlerType.clientEvent;

	constructor(
		private commands: ApplicationCommandData[],
		private marblesService: MarblesService,
		private collectionsService: CollectionsService
	) {
		super();
	}

	@ClientEvent('ready')
	async onReady() {
		// * Successful login
		Logger.info(`Logged in as ${this.client?.user?.tag}!`);

		const loading = Logger.loading(
			'Started refreshing application (/) commands.'
		);
		try {
			await this.client?.application?.commands.set(this.commands);
			loading.success('Successfully reloaded application (/) commands.');
			new MarblesServer(this.client, [
				new BroadcastController(),
				new HtmxController(),
			]).start();
		} catch (err: any) {
			loading.fail('Failed to reload application (/) commands.');
			Logger.error(err);
			process.exit(1);
		}
	}

	@ClientEvent('messageReactionAdd')
	async onReactionAdd(reaction: MessageReaction, user: User) {
		if (reaction.message.author?.id !== this.client.user.id) {
			// ? Only react to messages sent by bot
			return;
		}
		if (!reaction.message.guildId) {
			// ? Only react to messages sent in guilds
			return;
		}
		const embed = reaction.message.embeds.at(0);
		if (!embed) {
			// ? if without an emebed it definitely was not a marble spawn message
			return;
		}
		const emoji = embed.fields.at(-1)?.value.split(' ').at(2);
		if (reaction.emoji.name === emoji) {
			// ? Delete the message
			void reaction.message.delete();
			const marbleName = embed.title?.split('`').at(1);
			if (!marbleName) return;
			await this.collectionsService.addMarble(
				reaction.message.guildId,
				user.id,
				marbleName
			);

			const responseEmbed = new EmbedBuilder()
				.setColor(embed.color)
				.setDescription(
					`<@${user.id}> ${reaction.emoji} \n\n\`${marbleName}\` Was added to your collection.`
				)
				.setImage(embed.image?.url ?? '')
				.setThumbnail(embed.thumbnail?.url ?? '');

			await reaction.message.channel.send({
				embeds: [responseEmbed],
			});
		}
	}
}
