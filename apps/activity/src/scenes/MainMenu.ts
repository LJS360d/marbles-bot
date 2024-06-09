import { Scene } from 'phaser';
import { Menu } from '../components/Menu';
export class MainMenu extends Scene {
	private menu: Menu;
	constructor() {
		super('MainMenu');
	}

	create() {
		const bg = this.add.image(
			this.cameras.main.width / 2,
			this.cameras.main.height / 2,
			'background'
		);
		const scaleX = this.cameras.main.width / bg.width + 0.2;
		const scaleY = this.cameras.main.height / bg.height + 0.2;
		const scale = Math.max(scaleX, scaleY);
		bg.setScale(scale).setScrollFactor(0);

		this.add.image(Number(this.game.config.width) * 0.5, 300, 'logo');
		this.menu = new Menu(
			this,
			[
				{
					text: 'Start Game',
					callback: () => this.scene.start('Game'),
				},
				{
					text: 'Settings',
					callback: () => this.scene.start('Settings'),
				},
			],
			this.halfWidth - 120,
			this.halfHeight
		);
	}

	update(time: number, delta: number): void {
		this.menu.update();
	}

	get width() {
		return Number(this.game.config.width);
	}
	get halfWidth() {
		return this.width * 0.5;
	}

	get height() {
		return Number(this.game.config.height);
	}
	get halfHeight() {
		return this.height * 0.5;
	}
}
