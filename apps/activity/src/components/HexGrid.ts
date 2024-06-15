import { FX } from 'phaser';
import { Theme } from '../theme';
export interface HexGridConfig {
  x: number;
  y: number;
  size?: number;
  cellDimension?: number;
  orientation?: 'x' | 'y';
  cellSpacing?: number;
  staggeraxis?: 'x' | 'y';
  staggerindex?: 'even' | 'odd';
}
export class HexGrid extends Phaser.GameObjects.GameObject {
  constructor(
    scene: Phaser.Scene,
    {
      x,
      y,
      size = 18,
      cellDimension = 30,
      orientation = 'y',
      staggerindex = 'even',
      cellSpacing = 3,
    }: HexGridConfig
  ) {
    super(scene, 'hex-grid');
    const gameObjects = Array.from({ length: size ** 2 }, (_, i) => {
      const polygon = scene.add.polygon(
        0,
        0,
        this.getHexagonPoints(orientation, cellDimension)
      );
      if (isWall(i, size)) {
        polygon.setFillStyle(Theme.hexColors.black);
        return polygon;
      }
      polygon
        .setFillStyle(Theme.hexColors.white)
        .setStrokeStyle(2, Theme.hexColors.black, 1)
        .setInteractive({ useHandCursor: true })
        .on('pointerover', () =>
          polygon.setFillStyle(Theme.hexColors.error, 0.8)
        )
        .on('pointerout', () => polygon.setFillStyle(Theme.hexColors.white, 1))
        .on('pointerdown', () => {
          polygon.setFillStyle(Theme.hexColors.error);
          polygon.postFX.addGlow(Theme.hexColors.error, 1, 10);
        })
        .on('pointerup', () => {
          polygon.setFillStyle(Theme.hexColors.error, 0.8);
          polygon.postFX.clear();
        });
      return polygon;
    });
    scene.rexUIGridAlign.hexagon(gameObjects, {
      width: size,
      height: size,
      cellWidth: cellDimension + cellSpacing,
      cellHeight: cellDimension + cellSpacing,
      staggeraxis: orientation,
      staggerindex,
      position: Phaser.Display.Align.CENTER,
      x,
      y,
    });
  }

  private getHexagonPoints(orientation: 'x' | 'y', w: number) {
    return orientation === 'y'
      ? flatTopHexagonPoints(w)
      : pointyTopHexagonPoints(w);
  }
}

function isWall(i: number, size: number) {
  return (
    i % (size - 3) === 0 ||
    i % (size - 5) === 5 ||
    i % (size - 7) === 7 ||
    i % size === 0 ||
    i % size === size - 1 ||
    i < size ||
    i > size * size - size
  );
}

function pointyTopHexagonPoints(w: number) {
  return [
    { x: w, y: 0 },
    { x: w + w * 0.5, y: w / 4 },
    { x: w + w * 0.5, y: w * (3 / 4) },
    { x: w, y: w },
    { x: w * 0.5, y: w * (3 / 4) },
    { x: w * 0.5, y: w / 4 },
  ];
}

function flatTopHexagonPoints(w: number) {
  return [
    { x: w / 4, y: 0 },
    { x: w * (3 / 4), y: 0 },
    { x: w, y: w * 0.5 },
    { x: w * (3 / 4), y: w },
    { x: w / 4, y: w },
    { x: 0, y: w * 0.5 },
  ];
}
