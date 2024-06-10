import { defineConfig } from 'tsup';
import * as pkg from './package.json';
const dev = process.env.NODE_ENV === 'development';

export default defineConfig({
  name: pkg.name,
  entry: ['src/'],
  outDir: 'dist',
  splitting: false,
  sourcemap: !dev,
  dts: !dev,
  clean: !dev,
  treeshake: true,
  silent: dev,
  watch: dev,
  format: ['cjs'],
  loader: {
    '.json': 'copy',
  },
  cjsInterop: true,
  minify: !dev,
});
