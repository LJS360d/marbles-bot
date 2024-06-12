import type Theme from './common/theme.definition';

export default {
  text: {
    headline: {
      fontFamily: 'Arial Black',
      fontSize: 38,
      color: '#ffffff',
      stroke: '#000000',
      strokeThickness: 8,
      align: 'left',
    },
    button: {
      fontSize: '24px',
      color: '#00ff00',
      backgroundColor: '#000000',
      padding: { left: 20, right: 20, top: 10, bottom: 10 },
      align: 'center',
    },
    buttonActive: {
      fontSize: '24px',
      color: '#7289da',
      backgroundColor: '#000000',
      padding: { left: 20, right: 20, top: 10, bottom: 10 },
      align: 'center',
    },
    bodyText: {
      fontSize: '18px',
      color: '#ffffff',
      align: 'left',
    },
    caption: {
      fontSize: '14px',
      color: '#aaaaaa',
      align: 'left',
    },
  },

  graphics: {
    default: {
      lineStyle: {
        width: 2,
        color: 0xffffff,
        alpha: 1,
      },
      fillStyle: {
        color: 0x000000,
        alpha: 1,
      },
    },
    highlighted: {
      lineStyle: {
        width: 4,
        color: 0xff0000,
        alpha: 1,
      },
      fillStyle: {
        color: 0xffff00,
        alpha: 1,
      },
    },
  },

  sprite: {
    default: {
      scale: 1,
    },
    large: {
      scale: 2,
    },
  },

  container: {
    default: {
      x: 0,
      y: 0,
    },
  },

  tileSprite: {
    default: {
      width: 100,
      height: 100,
      scale: 1,
    },
    large: {
      width: 200,
      height: 200,
      scale: 2,
    },
  },

  particles: {
    default: {
      speed: 100,
      lifespan: 2000,
      quantity: 4,
      scale: { start: 1, end: 0 },
      blendMode: 'ADD',
    },
    explosion: {
      speed: { min: 200, max: 400 },
      lifespan: 1000,
      quantity: 10,
      scale: { start: 1, end: 0 },
      blendMode: 'ADD',
    },
  },
} satisfies Theme;
