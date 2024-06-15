import { HexGrid } from '../components/HexGrid/HexGrid';
import { HexGridMap, HexGridMaps } from '../components/HexGrid/Maps';
import { TextButton } from '../components/TextButton';
import { BaseScene } from '../scenes/common/base.scene';

export const MapBuilderKey = 'map-builder';
export class MapBuilder extends BaseScene {
  hexGrid: HexGrid;
  walls: number[] = [];
  constructor() {
    super(MapBuilderKey);
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
    this.createHexGrid();
    HexGridMaps.set(HexGridMap.blank, (i) => this.walls.includes(i));
    new TextButton(this, {
      onClick: this.reset.bind(this),
      text: 'Reset',
      x: this.halfWidth,
      y: this.halfHeight - 100,
    });
    new TextButton(this, {
      onClick: this.logResult.bind(this),
      text: 'Estratto conto',
      x: this.halfWidth,
      y: this.halfHeight,
    });
  }

  logResult() {
    console.log(this.walls);
  }

  reset() {
    this.hexGrid.dispose();
    this.walls = [];
    this.createHexGrid();
  }

  createHexGrid() {
    this.hexGrid = new HexGrid(this, {
      x: 0,
      y: 50,
      map: HexGridMap.blank,
      onClick: this.onHexClick.bind(this),
      onDoubleClick: this.onHexDoubleClick.bind(this),
    });
  }

  onHexClick(i: number) {
    this.hexGrid.dispose();
    this.walls.push(i);
    this.createHexGrid();
  }
  onHexDoubleClick(i: number) {
    this.hexGrid.dispose();
    this.walls = this.walls.filter((v) => v !== i);
    this.createHexGrid();
    this.hexGrid.update();
  }
}
