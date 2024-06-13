import 'phaser';

interface IconConfig {
  key: string;
  x: number;
  y: number;
  scale?: number;
}
export class Icon extends Phaser.GameObjects.Image {
  constructor(scene: Phaser.Scene, { scale = 1, key, x, y }: IconConfig) {
    super(scene, x, y, key);
    this.setScale(scale);
    scene.add.existing(this);
  }
}
