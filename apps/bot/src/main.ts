import { Client } from 'discord.js';
import { Logger, getRegisteredCommands } from 'fonzi2';
import Container from 'typedi';
import { MarblesClient } from './client/client';
import ClientEventsHandler from './client/handlers/client.events.handler';
import { CommonCommandsHandler } from './client/handlers/common.commands.handler';
import { MessageHandler } from './client/handlers/message.handler';
import { connectMongo } from './datastore/database/mongodb.connector';
import initDatastore from './datastore/init';
import CollectionsService from './datastore/structure/collections/services/collections.service';
import GuildsService from './datastore/structure/guilds/services/guilds.service';
import MarblesService from './datastore/structure/marbles/services/marbles.service';
import TeamsService from './datastore/structure/teams/services/teams.service';
import env from './env';
import options from './options';

async function main() {
	const db = await connectMongo(env.MONGODB_URI, 'marbles');
	await initDatastore();
	const client = new MarblesClient(env.TOKEN, options, [
		new MessageHandler(
			Container.get(MarblesService),
			Container.get(GuildsService)
		),
		new CommonCommandsHandler(
			env.VERSION,
			Container.get(MarblesService),
			Container.get(TeamsService),
			Container.get(CollectionsService)
		),
		new ClientEventsHandler(
			getRegisteredCommands(),
			Container.get(MarblesService),
			Container.get(CollectionsService)
		),
	]);
	Container.set(Client, client);

	process.on('uncaughtException', (err: any) => {
		Logger.error(
			`${err.name} - ${err.message}\n${err.stack || 'No stack trace available'}`
		);
	});

	process.on('unhandledRejection', (reason: any) => {
		if (reason?.status === 429) return;
		if (reason?.response?.status === 429) return;
		Logger.error(reason);
	});

	['SIGINT', 'SIGTERM', 'SIGQUIT'].forEach((signal) => {
		process.on(signal, async () => {
			Logger.warn(
				`Received ${signal} signal, closing &u${db?.name}$ database connection`
			);
			await db?.close();
		});
	});
}

void main();
