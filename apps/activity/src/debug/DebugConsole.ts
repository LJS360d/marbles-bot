export class DebugConsole extends Phaser.GameObjects.Container {
	constructor(scene: Phaser.Scene) {
		super(scene, 0, 0);
		const background = scene.add.rectangle(
			0,
			0,
			scene.cameras.main.width,
			200,
			0x000000,
			0.8
		);
		background.setOrigin(0, 0);
		this.add(background);

		// Add text to the debug console
		const text = scene.add.text(10, 10, 'Debug Console', {
			fontSize: '16px',
			color: '#ffffff',
		});
		this.add(text);

		// Initially hide the debug console
		// Add the debug console to the scene
		scene.add.existing(this);
	}
}
