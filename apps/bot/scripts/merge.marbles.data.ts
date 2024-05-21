import { readFileSync, writeFileSync } from 'node:fs';

const mergeDeep = (target, source) => {
	for (const key of Object.keys(source)) {
		if (source[key] instanceof Object && key in target) {
			Object.assign(source[key], mergeDeep(target[key], source[key]));
		}
	}
	return { ...target, ...source };
};

const mergeArrays = (arr1, arr2, key) => {
	const arr1Map = new Map(arr1.map((item) => [item[key], item]));

	return arr2.map((item) => {
		const arr1Item = arr1Map.get(item[key]) || {};
		return mergeDeep(arr1Item, item);
	});
};

/* const arr1 = JSON.parse(readFileSync('yield/marbles.json', 'utf-8'));
const arr2 = JSON.parse(readFileSync('yield/nodata_marbles.json', 'utf-8'));
const merged = mergeArrays(arr1, arr2, 'name');
writeFileSync('yield/merged_marbles.json', JSON.stringify(merged, null, 2));
 */

const merged = JSON.parse(readFileSync('yield/cleaned_marbles.json', 'utf-8'));

for (const marble of merged) {
	if (marble.notes.position.toLowerCase().includes('competitor')) {
		marble.notes.competition = marble.notes.team;
	} else {
		marble.notes.competition = '';
	}

	marble.notes.team = undefined;
}

writeFileSync('yield/cleaneder_marbles.json', JSON.stringify(merged, null, 2));
