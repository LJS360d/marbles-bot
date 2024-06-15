import { ScaleFlow } from './utils/ScaleFlow';
import { initiateDiscordSDK, discordSdk } from './utils/discordSDK';

import { Boot } from './scenes/Boot';
import { Game } from './scenes/Game';
import { MainMenu } from './scenes/MainMenu';
import { Preloader } from './scenes/Preloader';
import { Background } from './scenes/Background';
import { SettingsMenu } from './scenes/SettingsMenu';
import { DebugConsole } from './debug/DebugConsole';
import { Login } from './scenes/auth/Login';
import UIPlugin from 'phaser3-rex-plugins/templates/ui/ui-plugin';
import GridAlignPlugin from 'phaser3-rex-plugins/plugins/gridalign-plugin.js';
import { MapBuilder } from './debug/MapBuilder';

(async () => {
  initiateDiscordSDK();

  const scaleFlow = new ScaleFlow({
    type: Phaser.WEBGL,
    parent: 'gameParent',
    width: 1280, // this must be a pixel value
    height: 720, // this must be a pixel value
    backgroundColor: '#000000',
    roundPixels: false,
    pixelArt: false,
    antialiasGL: true,
    antialias: true,
    transparent: false,
    plugins: {
      scene: [
        {
          key: 'rexUI',
          plugin: UIPlugin,
          mapping: 'rexUI',
          start: true,
        },
        {
          key: 'rexUIGridAlign',
          plugin: GridAlignPlugin,
          mapping: 'rexUIGridAlign',
          start: true,
        },
      ],
    },
    fps: {
      limit: 240,
      smoothStep: true,
      min: 30,
      target: 60,
    },
    scene: [
      Boot,
      Preloader,
      MainMenu,
      Game,
      MapBuilder,
      Background,
      SettingsMenu,
      Login,
    ],
  });

  window.addEventListener('keydown', (event: KeyboardEvent) => {
    if (event.shiftKey && event.key === 'D') {
      const currentScene = scaleFlow.game.scene.getScenes(true)[0];
      if (
        !currentScene.children
          .getAll()
          .filter((child) => child instanceof DebugConsole).length
      )
        new DebugConsole(currentScene);
    }
  });
})();
