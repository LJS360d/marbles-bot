import Phaser from 'phaser';

export interface IconButtonConfig {
  x: number;
  y: number;
  icon: string;
  onClick: () => void;
  scale?: number;
  hoverScale?: number;
  clickScale?: number;
  duration?: number;
}

export class IconButton extends Phaser.GameObjects.Image {
  private originalScale: number;
  private hoverScale: number;
  private duration: number;
  private clickScale: number;

  constructor(
    scene: Phaser.Scene,
    {
      x,
      y,
      icon,
      onClick,
      scale = 0.7,
      hoverScale = 0.76,
      duration = 300,
      clickScale = 0.65,
    }: IconButtonConfig
  ) {
    super(scene, x, y, icon);

    this.originalScale = scale;
    this.hoverScale = hoverScale;
    this.clickScale = clickScale;
    this.duration = duration;

    this.setScale(scale)
      .setInteractive({ useHandCursor: true })
      .on('pointerover', () => this.animateScale(this.hoverScale))
      .on('pointerout', () => this.animateScale(this.originalScale))
      .on('pointerdown', () =>
        this.animateScale(this.clickScale, this.duration / 2)
      )
      .on('pointerup', () =>
        this.animateScale(this.originalScale, this.duration / 2, onClick)
      );

    scene.add.existing(this);
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
