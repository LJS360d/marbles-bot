import { Scene } from 'phaser';
import { getAccessToken } from '../utils/auth.utils';

export class Preloader extends Scene {
  constructor() {
    super('Preloader');
  }

  init() {
    const bg = this.add.image(
      this.cameras.main.width / 2,
      this.cameras.main.height / 2,
      'background'
    );
    const scaleX = this.cameras.main.width / bg.width + 0.2;
    const scaleY = this.cameras.main.height / bg.height + 0.2;
    const scale = Math.max(scaleX, scaleY);
    bg.setScale(scale).setScrollFactor(0);

    //  A simple progress bar. This is the outline of the bar.
    this.add
      .rectangle(
        Number(this.game.config.width) * 0.5,
        Number(this.game.config.height) * 0.5,
        468,
        32
      )
      .setStrokeStyle(1, 0xffffff);

    //  This is the progress bar itself. It will increase in size from the left based on the % of progress.
    const bar = this.add.rectangle(
      Number(this.game.config.width) * 0.5 - 230,
      Number(this.game.config.height) * 0.5,
      4,
      28,
      0xffffff
    );

    //  Use the 'progress' event emitted by the LoaderPlugin to update the loading bar
    this.load.on('progress', (progress) => {
      //  Update the progress bar (our bar is 464px wide, so 100% = 464px)
      bar.width = 4 + 460 * progress;
    });
  }

  preload() {
    //  Load the assets for the game - Replace with your own assets
    this.load.setPath('assets');

    // Load the alphabet images
    const alphabetArray = 'abcd'.split(''); // efghijklmnopqrstuvwxyz

    alphabetArray.forEach((letter) => {
      this.load.image(letter, `${letter}.png`);
    });

    this.load.image('smile', 'smile.png');
    this.load.image('alien', 'alien.png');
    this.load.image('logo', 'logo.png');
    this.load.image('nought_1', 'nought.png');
    this.load.image('nought_2', 'nought.png');
    this.load.image('nought_3', 'nought.png');
    this.load.image('cross_1', 'cross.png');
    this.load.image('cross_2', 'cross.png');
    this.load.image('cross_3', 'cross.png');
    this.load.image('grid', 'grid.png');
    // icons
    // read the icons from the assets/icons folder
    // iterate over them and load them
    const icons = [
      'cart',
      'cross',
      'exclamation',
      'exit',
      'gear',
      'home',
      'info',
      'levels',
      'locker-locked',
      'locker-unlocked',
      'mediumarrow-left',
      'mediumarrow-right',
      'multiplayer',
      'music-off',
      'music-on',
      'pause',
      'play',
      'player',
      'podium',
      'question',
      'repeat-right',
      'sharelink',
      'solidarrow-left',
      'solidarrow-right',
      'sound-none',
      'sound-one',
      'sound-three',
      'sound-two',
      'star',
      'talkbubble',
      'thumb-down',
      'thumb-up',
      'tick',
      'twoplayer',
    ];
    icons.forEach((icon) => {
      this.load.svg(icon, `../icons/${icon}.svg`);
    });
  }

  create() {
    const accessToken = getAccessToken();
    if (accessToken) {
      this.scene.start('MainMenu');
      return;
    }
    this.scene.start('Login');
  }
}
