import type { Client } from 'discord.js';
import express from 'express';
import { Fonzi2Server, Logger, type ServerController } from 'fonzi2';
import { resolve } from 'node:path';

export class MarblesServer extends Fonzi2Server {
  constructor(client: Client<true>, controllers: ServerController[]) {
    super(client, controllers);
    this.app.use(express.static(resolve(process.cwd(), 'public')));
  }

  override start(): void {
    this.httpServer.on('request', (req, res) => {
      Logger.trace(`[${req.method}] ${req.url} ${res.statusCode}`);
    });
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
