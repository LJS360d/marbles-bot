import { ScaleFlow } from './utils/ScaleFlow';
import { initiateDiscordSDK, discordSdk } from './utils/discordSDK';

import { Boot } from './scenes/Boot';
import { Game } from './scenes/Game';
import { MainMenu } from './scenes/MainMenu';
import { Preloader } from './scenes/Preloader';
import { Background } from './scenes/Background';
import { SettingsMenu } from './scenes/SettingsMenu';
import { DebugConsole } from './debug/DebugConsole';

(async () => {
	initiateDiscordSDK();

	const scaleFlow = new ScaleFlow({
		type: Phaser.AUTO,
		parent: 'gameParent',
		width: 1280, // this must be a pixel value
		height: 720, // this must be a pixel value
		backgroundColor: '#000000',
		roundPixels: false,
		pixelArt: false,
		antialiasGL: true,
		antialias: true,
		transparent: false,
		fps: {
			limit: 240,
			smoothStep: true,
			min: 30,
			target: 60,
		},
		scene: [Boot, Preloader, MainMenu, Game, Background, SettingsMenu],
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
