import type { Message } from 'discord.js';
import { DiscordHandler, HandlerType, MessageEvent } from 'fonzi2';
import type GuildsService from '../../datastore/structure/guilds/services/guilds.service';
import type MarblesService from '../../datastore/structure/marbles/services/marbles.service';
import { areTimestampsAtLeast15MinutesApart } from '../../utils/datetime.utils';
import { spawnMarble } from '../../utils/marbles.utils';
import { getRandom } from '../../utils/random.utils';

export class MessageHandler extends DiscordHandler {
	public readonly type = HandlerType.messageEvent;

	constructor(
		private marblesService: MarblesService,
		private guildsService: GuildsService
	) {
		super();
	}

	@MessageEvent('GuildText')
	async onMessage(message: Message<true>) {
		if (message.author.bot) return;
		const latestSpawnTime = this.guildsService.getLatestSpawn(message.guildId);
		const now = new Date().getTime();
		if (!areTimestampsAtLeast15MinutesApart(latestSpawnTime, now)) return;
		const doSpawn = getRandom(1, 100) <= 25;
		if (doSpawn) {
			const marble = await this.marblesService.getOneRandom();
			void spawnMarble(message.channel, marble);
			this.guildsService.setLatestSpawn(message.guildId);
		}
	}
}
