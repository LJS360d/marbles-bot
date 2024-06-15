import type Theme from './common/theme.definition';

const colors = {
  white: '#f2f2f2',
  black: '#0f0f0f',
  primary: '#22d3ee',
  secondary: '#00a8ff',
  accent: '#007aff',
  neutral: '#150200',
  'base-100': '#0f2735',
  info: '#0096ea',
  success: '#3ed31e',
  warning: '#ff7800',
  error: '#ff436f',
} as const;

const hexColors = {
  white: 0xf2f2f2,
  black: 0x0f0f0f,
  primary: 0x22d3ee,
  secondary: 0x00a8ff,
  accent: 0x007aff,
  neutral: 0x150200,
  'base-100': 0x0f2735,
  info: 0x0096ea,
  success: 0x3ed31e,
  warning: 0xff7800,
  error: 0xff436f,
} as const;

export default {
  colors,
  hexColors,
  text: {
    headline: {
      fontFamily: 'Arial Black',
      fontSize: 38,
      color: colors.white,
      stroke: colors.black,
      strokeThickness: 8,
      align: 'left',
    },
    bodyText: {
      fontSize: '18px',
      color: colors.white,
      align: 'left',
    },
  },

  button: {
    ghost: {
      fontSize: '24px',
      color: colors.white,
      stroke: colors.black,
      strokeThickness: 8,
      padding: { left: 20, right: 20, top: 10, bottom: 10 },
      align: 'center',
      fontFamily: 'Arial Black',
    },
    primary: {
      fontSize: '24px',
      color: colors.white,
      backgroundColor: colors.primary,
      stroke: colors.black,
      strokeThickness: 8,
      padding: { left: 20, right: 20, top: 10, bottom: 10 },
      align: 'center',
      fontFamily: 'Arial Black',
    },
    success: {
      fontSize: '24px',
      color: colors.white,
      backgroundColor: colors.success,
      stroke: colors.black,
      strokeThickness: 8,
      padding: { left: 20, right: 20, top: 10, bottom: 10 },
      align: 'center',
      fontFamily: 'Arial Black',
    },
    error: {
      fontSize: '24px',
      color: colors.white,
      backgroundColor: colors.error,
      padding: { left: 20, right: 20, top: 10, bottom: 10 },
      align: 'center',
      fontFamily: 'Arial Black',
    },
  },

  graphics: {
    default: {
      lineStyle: {
        width: 2,
        color: hexColors.white,
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
        color: hexColors.error,
        alpha: 1,
      },
      fillStyle: {
        color: hexColors.warning,
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
