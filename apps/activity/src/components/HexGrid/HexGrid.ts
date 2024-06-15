import { Theme } from '../../theme';
import { HexGridMap, HexGridMaps } from './Maps';
export interface HexGridConfig {
  x: number;
  y: number;
  size?: number;
  cellDimension?: number;
  orientation?: 'x' | 'y';
  cellSpacing?: number;
  staggerindex?: 'even' | 'odd';
  map?: HexGridMap;
  onClick?: (i: number) => void;
  onDoubleClick?: (i: number) => void;
}
export class HexGrid extends Phaser.GameObjects.GameObject {
  x: number;
  y: number;
  size: number;
  cellDimension: number;
  orientation: 'x' | 'y';
  cellSpacing: number;
  staggerindex: 'even' | 'odd';
  map?: HexGridMap;
  onClick?: (i: number) => void;
  onDoubleClick?: (i: number) => void;
  constructor(
    scene: Phaser.Scene,
    {
      x,
      y,
      size = 18, // 18
      cellDimension = 28,
      orientation = 'y',
      staggerindex = 'even',
      cellSpacing = 3,
      map = HexGridMap.pillars,
      onClick,
      onDoubleClick,
    }: HexGridConfig
  ) {
    super(scene, 'hex-grid');
    this.x = x;
    this.y = y;
    this.size = size;
    this.cellDimension = cellDimension;
    this.orientation = orientation;
    this.cellSpacing = cellSpacing;
    this.staggerindex = staggerindex;
    this.map = map;
    this.onClick = onClick;
    this.onDoubleClick = onDoubleClick;
    this.create();
  }

  create() {
    const gameObjects = Array.from({ length: this.size ** 2 }, (_, i) => {
      const polygon = this.scene.add.polygon(
        0,
        0,
        this.getHexagonPoints(this.orientation, this.cellDimension)
      );
      if (this.isWall(i, this.size, this.map)) {
        polygon.setFillStyle(Theme.hexColors.black);
        return polygon;
      }
      let lastTime = this.scene.time.now;
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
          this.onClick?.(i);
          polygon.setFillStyle(Theme.hexColors.error, 0.8);
          polygon.postFX.clear();
          const clickDelay = this.scene.time.now - lastTime;
          lastTime = this.scene.time.now;
          if (clickDelay < 350) {
            this.onDoubleClick?.(i);
          }
        });
      return polygon;
    });
    this.scene.rexUIGridAlign.hexagon(gameObjects, {
      width: this.size,
      height: this.size,
      cellWidth: this.cellDimension + this.cellSpacing,
      cellHeight: this.cellDimension + this.cellSpacing,
      staggeraxis: this.orientation,
      staggerindex: this.staggerindex,
      position: Phaser.Display.Align.CENTER,
      x: this.x,
      y: this.y,
    });
  }

  dispose() {
    this.emit('removedfromscene');
  }

  private getHexagonPoints(orientation: 'x' | 'y', w: number) {
    return orientation === 'y'
      ? flatTopHexagonPoints(w)
      : pointyTopHexagonPoints(w);
  }

  private isWall(i: number, size: number, map: HexGridMap = HexGridMap.blank) {
    const mapPattern = HexGridMaps.get(map)?.(i, size) ?? false;
    const outerRing =
      i % size === 0 ||
      i % size === size - 1 ||
      i < size ||
      i > size * size - size;
    return outerRing || mapPattern;
  }
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
