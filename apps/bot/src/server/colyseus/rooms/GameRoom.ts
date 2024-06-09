import { type Client, Room } from 'colyseus';
import { GameState, Draggables } from '../schemas/GameState';
import { Logger } from 'fonzi2';

export class GameRoom extends Room<GameState> {
	readonly maxClients = 25;
	onCreate(options: any) {
		this.setState(new GameState());

		const draggableList = [
			'smile',
			'alien',
			'a',
			'b',
			'c',
			'd',
			'cross_1',
			'cross_2',
			'cross_3',
			'nought_1',
			'nought_2',
			'nought_3',
		];
		draggableList.forEach((draggable, index) => {
			const draggableObject = new Draggables();

			const offset = 500;
			const minWidth = offset;
			const maxWidth = options.screenWidth / 2 + 250;
			const minHeight = offset;
			const maxHeight = options.screenHeight / 2;

			draggableObject.x =
				Math.floor(Math.random() * (maxWidth - minWidth + 1)) + minWidth;
			draggableObject.y =
				Math.floor(Math.random() * (maxHeight - minHeight + 1)) + minHeight;
			draggableObject.imageId = draggable;

			this.state.draggables.set(draggable, draggableObject);
		});

		this.onMessage('move', (client, message) => {
			// Update image position based on data received
			const image = this.state.draggables.get(message.imageId);
			if (image) {
				image.x = message.x;
				image.y = message.y;
				this.broadcast('move', this.state.draggables);
			}
		});
	}

	onJoin(client: Client, options?: any, auth?: any) {
		Logger.info(`Client joined: ${client.sessionId}`);
	}

	onLeave(client: Client, consented: boolean) {
		Logger.info(`Client left: ${client.sessionId}`);
	}
}
