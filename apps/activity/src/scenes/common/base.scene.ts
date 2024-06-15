import type RexUIPlugin from 'phaser3-rex-plugins/templates/ui/ui-plugin.js';
import type GridAlignPlugin from 'phaser3-rex-plugins/plugins/gridalign-plugin.js';

export class BaseScene extends Phaser.Scene {
  readonly rexUI: RexUIPlugin;
  readonly rexUIGridAlign: GridAlignPlugin;
  get width() {
    return Number(this.game.config.width);
  }
  get halfWidth() {
    return this.width * 0.5;
  }

  get height() {
    return Number(this.game.config.height);
  }
  get halfHeight() {
    return this.height * 0.5;
  }
}
