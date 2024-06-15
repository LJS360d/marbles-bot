import Sizer from 'phaser3-rex-plugins/templates/ui/sizer/Sizer';

export enum HexGridMap {
  blank = 'blank',
  pillars = 'pillars',
  test = 'test',
  crossroads = 'crossroads',
}
// size 18 -> 19 - 304
// size 19 -> 20 - 340
// size 20 -> 21 - 378
// size 21 -> 22 - 418
// size 22 -> 23 - 460
const firstId = (size: number) => size + 1;
const lastId = (size: number) => size * size - size + 2;
const column = (i: number, size: number) => i % size;
const row = (i: number, size: number) => Math.floor(i / size);

export const HexGridMaps: Map<
  HexGridMap,
  (i: number, size: number) => boolean
> = new Map([
  [HexGridMap.blank, (_) => false],
  [
    HexGridMap.test,
    (i, size) =>
      [
        57, 75, 93, 111, 129, 147, 130, 131, 114, 98, 115, 99, 172, 189, 207,
        225, 243, 244, 263, 246, 247, 229, 211, 193, 176, 177, 195, 213, 231,
      ].includes(i),
  ],
  [HexGridMap.pillars, (i) => i % 4 === 0],
  [
    HexGridMap.crossroads,
    (i, size) => i % (size - 2) === 1 || i % (1 + size) === 1,
  ],
]);

export const HexGridMapsIterator = HexGridMaps.keys();
