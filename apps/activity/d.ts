/// <reference types="vite/client" />
import 'phaser';
import type RexUIPlugin from 'phaser3-rex-plugins/templates/ui/ui-plugin.js';
import type GridAlignPlugin from 'phaser3-rex-plugins/plugins/gridalign-plugin.js';

declare module 'phaser' {
  interface Scene {
    rexUI: RexUIPlugin;
    rexUIGridAlign: GridAlignPlugin;
  }
}
