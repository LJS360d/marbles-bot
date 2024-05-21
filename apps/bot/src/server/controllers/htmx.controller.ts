import type { Request, Response } from 'express';
import { Get, ServerController } from 'fonzi2';

export class HtmxController extends ServerController {
	public counter = 0;

	@Get('/count')
	public count(req: Request, res: Response) {
		res.send((++this.counter).toString());
		return;
	}
}
