export class SettingsMenu extends Phaser.Scene {
	constructor() {
		super('SettingsMenu');
	}

	create() {
		this.add.image(
			this.cameras.main.width / 2,
			this.cameras.main.height / 2,
			'background'
		);
	}
}
