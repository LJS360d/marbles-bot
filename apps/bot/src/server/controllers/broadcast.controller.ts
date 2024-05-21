import type { Request, Response } from 'express';
import { Get, ServerController } from 'fonzi2';

export class BroadcastController extends ServerController {
	@Get('/routes')
	async routes(req: Request, res: Response) {
		res.send(this.app._router.stack.map((r) => r.route));
	}
}
