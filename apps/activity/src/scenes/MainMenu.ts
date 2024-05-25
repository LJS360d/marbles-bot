import { Scene } from 'phaser';
import { defaultTextStyle } from '../utils/text/text.style';
export class MainMenu extends Scene {
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

		this.add
			.text(this.halfWidth, this.halfHeight + 50, 'Main Menu', defaultTextStyle)
			.setOrigin(0.5);
		const settingsButton = this.add
			.text(this.halfWidth, this.halfHeight + 100, 'Settings', defaultTextStyle)
			.setOrigin(0.5)
			.setInteractive()
			.on('pointerdown', () => this.scene.start('SettingsMenu'));
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
