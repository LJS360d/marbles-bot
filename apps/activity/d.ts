/// <reference types="vite/client" />
import 'phaser';
import type RexUIPlugin from 'phaser3-rex-plugins/templates/ui/ui-plugin.js';
declare module 'phaser' {
  interface Scene {
    rexUI: RexUIPlugin;
  }
}
