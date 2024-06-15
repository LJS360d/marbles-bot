import { HexGrid } from '../components/HexGrid/HexGrid';
import { IconButton } from '../components/IconButton';
import { Menu } from '../components/Menu';
import { MapBuilderKey } from '../debug/MapBuilder';
import { logout } from '../utils/auth.utils';
import { SettingsMenuKey } from './SettingsMenu';
import { BaseScene } from './common/base.scene';
export class MainMenu extends BaseScene {
  private menu: Menu;
  constructor() {
    super('MainMenu');
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
    new HexGrid(this, {
      x: 0,
      y: 50,
    });
    new IconButton(this, {
      x: this.width * 0.985,
      y: this.height * 0.055,
      icon: 'exit',
      onClick: async () => {
        await logout();
        this.scene.start('Login');
      },
    });

    this.add.image(Number(this.game.config.width) * 0.5, 300, 'logo');
    this.menu = new Menu(
      this,
      [
        {
          text: 'Start Game',
          callback: () => this.scene.start('Game'),
        },
        {
          text: 'Settings',
          callback: () => this.scene.start(SettingsMenuKey),
        },
        {
          text: 'MapBuilder',
          callback: () => this.scene.start(MapBuilderKey),
        },
      ],
      this.halfWidth - 120,
      this.halfHeight
    );
  }

  update(time: number, delta: number): void {
    this.menu.update();
  }
}
