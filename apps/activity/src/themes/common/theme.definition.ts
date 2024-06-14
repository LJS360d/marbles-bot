import type { Types } from 'phaser';

export type TextStyle = Types.GameObjects.Text.TextStyle;
export type GraphicsStyles = Types.GameObjects.Graphics.Styles;
export type SpriteConfig = Types.GameObjects.Sprite.SpriteConfig;
export type ContainerConfig = Types.GameObjects.Container.ContainerConfig;
export type TileSpriteConfig = Types.GameObjects.TileSprite.TileSpriteConfig;
export type ParticleEmitterConfig =
  Types.GameObjects.Particles.ParticleEmitterConfig;

abstract class ITheme {
  abstract readonly colors: Record<string, string>;
  abstract readonly hexColors: Record<string, number>;
  abstract readonly text: Record<string, TextStyle>;
  abstract readonly button: Record<string, TextStyle>;
  abstract readonly graphics: Record<string, GraphicsStyles>;
  abstract readonly sprite: Record<string, SpriteConfig>;
  abstract readonly container: Record<string, ContainerConfig>;
  abstract readonly tileSprite: Record<string, TileSpriteConfig>;
  abstract readonly particles: Record<string, ParticleEmitterConfig>;
}

export default ITheme;
