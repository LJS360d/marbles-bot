import { monitor, type MonitorOptions } from '@colyseus/monitor';
import { WebSocketTransport } from '@colyseus/ws-transport';
import { Server } from 'colyseus';
import type { Client } from 'discord.js';
import express from 'express';
import { Fonzi2Server, Logger, type ServerController } from 'fonzi2';
import { resolve } from 'node:path';
import { GameRoom } from './colyseus/rooms/GameRoom';

export class MarblesServer extends Fonzi2Server {
	public readonly colyseus: Server;
	constructor(client: Client<true>, controllers: ServerController[]) {
		super(client, controllers);
		this.app.use(express.static(resolve(process.cwd(), 'public')));

		this.colyseus = new Server({
			transport: new WebSocketTransport({
				server: this.httpServer,
			}),
		});
	}

	override start(): void {
		this.httpServer.on('request', (req, res) => {
			Logger.trace(`[${req.method}] ${req.url} ${res.statusCode}`);
		});
		this.colyseus
			.define('game', GameRoom)
			// filterBy allows us to call joinOrCreate and then hold one game per channel
			// https://discuss.colyseus.io/topic/345/is-it-possible-to-run-joinorcreatebyid/3
			.filterBy(['channelId']);
		this.app.use(
			'/colyseus',
			monitor(this.colyseus as Partial<MonitorOptions>)
		);
		super.start();
	}

	/* override dashboard(req: Request, res: Response) {
		const props = {
			client: this.client,
			inviteLink: env.INVITE_LINK,
			version: env.VERSION,
			userInfo: this.getSessionUserInfo(req),
			startTime: this.startTime,
			guilds: this.client.guilds.cache,
		};
		return res.render('default/dashboard', props);
	} */
}
