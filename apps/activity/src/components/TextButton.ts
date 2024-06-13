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
  scale?: number;
  hoverScale?: number;
  clickScale?: number;
  duration?: number;
  style?: Phaser.Types.GameObjects.Text.TextStyle;
}

export class TextButton extends Phaser.GameObjects.Text {
  private originalScale: number;
  private hoverScale: number;
  private duration: number;
  private clickScale: number;

  constructor(
    scene: Phaser.Scene,
    {
      x,
      y,
      text,
      onClick,
      scale = 0.7,
      hoverScale = 0.8,
      duration = 300,
      clickScale = 0.65,
      style = defaultTextButtonStyle,
    }: TextButtonConfig
  ) {
    super(scene, x, y, text, style);

    this.originalScale = scale;
    this.hoverScale = hoverScale;
    this.clickScale = clickScale;
    this.duration = duration;

    this.setScale(scale)
      .setInteractive({ useHandCursor: true })
      .on('pointerover', () => this.onHover())
      .on('pointerout', () => this.onOut())
      .on('pointerdown', () => this.onDown())
      .on('pointerup', () => this.onUp(onClick));

    scene.add.existing(this);
  }

  public onHover() {
    this.animateScale(this.hoverScale);
  }

  public onOut() {
    this.animateScale(this.hoverScale);
  }

  public onDown() {
    this.animateScale(this.clickScale, this.duration / 2);
  }

  public onUp(onClick: () => void) {
    this.animateScale(this.originalScale, this.duration / 2, onClick);
  }

  private animateScale(
    targetScale: number,
    duration = this.duration,
    onComplete?: () => void
  ) {
    this.scene.tweens.add({
      targets: this,
      scale: targetScale,
      duration: duration,
      ease: 'Power2',
      onComplete: onComplete ? () => onComplete() : undefined,
    });
  }
}
