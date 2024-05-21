import axios from 'axios';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const teams = JSON.parse(readFileSync('yield/teams.json', 'utf-8'));
main(teams);
async function main(teams: any[]) {
	for (const team of teams) {
		if (team.image) {
			const logoUrl = await downloadImage(team, 'public/assets/teams/');
			team.image = undefined;
			team.logo = logoUrl;
		}
	}
	writeFileSync('docker/teams.seed.json', JSON.stringify(teams, null, 2));
}

async function downloadImage(team, saveDirectory: string) {
	try {
		const response = await axios({
			url: team.image,
			method: 'GET',
			responseType: 'arraybuffer',
		});

		const fileName = `${toLowerSnakeCase(team.name)}.png`;
		const filePath = join(saveDirectory, fileName);

		writeFileSync(filePath, response.data);

		console.log(`Image saved as ${filePath}`);
		return `https://raw.githubusercontent.com/LJS360d/marbles-bot/master/public/assets/teams/${fileName}`;
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
