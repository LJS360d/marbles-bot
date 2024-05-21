import axios from 'axios';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const data = JSON.parse(readFileSync('yield/cleaneder_marbles.json', 'utf-8'));
main(data);
async function main(data: any[]) {
	for (const marble of data) {
		if (marble.image) {
			marble.image = `https://raw.githubusercontent.com/LJS360d/marbles-bot/master/public/assets/marbles/${toLowerSnakeCase(
				marble.name
			)}.png`;
		}
		marble.position = marble.notes.position;
		marble.competition = marble.notes.competition ?? '';
		marble.extra = marble.notes.extra ?? '';
		marble.notes = undefined;
	}
	writeFileSync('docker/marbles.seed.json', JSON.stringify(data, null, 2));
}

async function downloadImage(marble, saveDirectory: string) {
	try {
		const response = await axios({
			url: marble.image,
			method: 'GET',
			responseType: 'arraybuffer',
		});

		const fileName = `${toLowerSnakeCase(marble.name)}.png`;
		const filePath = join(saveDirectory, fileName);

		writeFileSync(filePath, response.data);

		console.log(`Image saved as ${filePath}`);
	} catch (error) {
		console.error('Error downloading the image:', error);
	}
}
function toLowerSnakeCase(str: string) {
	return str
		.replace(/\s+/g, '_')
		.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`)
		.replace(/__+/g, '_')
		.replace(/^_/, '')
		.toLowerCase();
}
