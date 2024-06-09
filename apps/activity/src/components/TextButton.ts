import Phaser from 'phaser';

export const defaultTextButtonStyle: Phaser.Types.GameObjects.Text.TextStyle = {
	fontFamily: 'Arial Black',
	fontSize: '38px',
	color: '#ffffff',
	stroke: '#000000',
	strokeThickness: 8,
	align: 'left',
};

export interface TextButtonConfig {
	x: number;
	y: number;
	text: string;
	onClick: () => void;
	style?: Phaser.Types.GameObjects.Text.TextStyle;
	hoverScale?: number;
}

export class TextButton extends Phaser.GameObjects.Text {
	private originalScale: number;
	private hoverScale: number;
	private arrow: Phaser.GameObjects.Text;

	constructor(scene: Phaser.Scene, config: TextButtonConfig) {
		super(
			scene,
			config.x,
			config.y,
			config.text,
			config.style ?? defaultTextButtonStyle
		);
		scene.add.existing(this);

		this.originalScale = this.scale;
		this.hoverScale = config.hoverScale ?? 1.02;

		this.setInteractive({ useHandCursor: true })
			.on('pointerover', () => this.onHover())
			.on('pointerout', () => this.onOut())
			.on('pointerdown', () => config.onClick());
		this.arrow = scene.add
			.text(this.x, this.y, '>', { fontSize: 38, color: '#ffffff' })
			.setVisible(false);
	}

	onHover() {
		const bounds = this.getBounds();
		this.arrow.setPosition(
			bounds.left - this.arrow.width - 10,
			bounds.top + bounds.height / 2 - this.arrow.height / 2
		);
		this.arrow.setVisible(true);
	}

	onOut() {
		this.arrow.setVisible(false);
	}
}
