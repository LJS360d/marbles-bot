import { HexGrid } from '../components/HexGrid/HexGrid';
import { HexGridMap, HexGridMapsIterator } from '../components/HexGrid/Maps';
import { TextButton } from '../components/TextButton';
import { BaseScene } from './common/base.scene';

export const SettingsMenuKey = 'settings-menu';
export class SettingsMenu extends BaseScene {
  selectedMap: HexGridMap;
  hexGrid: HexGrid;
  constructor() {
    super(SettingsMenuKey);
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

    this.selectedMap = HexGridMap.pillars;
    Array.from(HexGridMapsIterator).forEach((map, i) => {
      new TextButton(this, {
        x: this.halfWidth,
        y: 50 + i * 50,
        text: map,
        onClick: () => {
          this.selectedMap = map;
          this.hexGrid?.dispose();
          this.hexGrid = new HexGrid(this, {
            x: 0,
            y: 50,
            map: this.selectedMap,
          });
        },
      });
    });
  }
}
