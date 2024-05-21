import axios from 'axios';
import { load } from 'cheerio';
import { writeFileSync } from 'node:fs';

const url = 'https://jellesmarbleruns.fandom.com/wiki/';
const teams = [
	'Balls_of_Chaos',
	'Black_Jacks',
	'Bluefastics',
	'Bumblebees',
	'Chocolatiers',
	'Constrictors',
	"Crazy_Cat's_Eyes",
	'Gliding_Glaciers',
	'Golden_Orbs',
	'Green_Ducks',
	'Green_Gang',
	'Hazers',
	'Hornets',
	'Indigo_Stars',
	'Jawbreakers',
	'Jungle_Jumpers',
	'Kobalts',
	'Limers',
	'Mellow_Yellow',
	'Midnight_Wisps',
	'Minty_Maniacs',
	'Noxious_Ivy',
	"O'rangers",
	'Oceanics',
	'Pinkies',
	'Purple_Rockets',
	'Quicksilvers',
	'Raspberry_Racers',
	'Rojo_Rollers',
	'Ruby_Rollers',
	'Savage_Speeders',
	'Shining_Swarm',
	'Snowballs',
	'Solar_Flares',
	'Strixes',
	'Team_Galactic',
	'Team_Momo',
	'Team_Momary',
	'Team_Plasma',
	'Team_Phoenix',
	'Team_Primary',
	'Thunderbolts',
	'Turtle_Sliders',
	'Valiant_Violets',
	'Wolfpack',
];

const teamData: any[] = [];
const marbleData: any[] = [];

async function fetchTeamInfo(team: string) {
	try {
		const response = await axios.get(`${url}${encodeURIComponent(team)}`);
		const $ = load(response.data);

		const teamName = $('#firstHeading').text().trim();
		const logoUrl = $('img.pi-image-thumbnail').attr('src')!.trim();
		const color = $('div[data-source="color"]')
			.find('div.pi-data-value.pi-font')
			.text()
			.trim();
		const coach = $('div[data-source="coach"]')
			.find('div.pi-data-value.pi-font')
			.text()
			.trim();
		const manager = $('div[data-source="manager"]')
			.find('div.pi-data-value.pi-font')
			.text()
			.trim();
		const membersRaw = $('table.article-table > tbody tr td[style]')
			.text()
			.trim();
		const membersSet = new Set(
			membersRaw
				.replace(/[ⅠⅡⅢ\[1\]]/g, '')
				.split('\n')
				.map((member) => member.trim())
		);
		const members = Array.from(membersSet);

		const marblePromises = Array.from(membersSet).map((marble) =>
			fetchMarbleData(marble, teamName)
		);

		const marbles = await Promise.all(marblePromises);

		const teamInfo = {
			name: teamName,
			color: color,
			coach: coach === '' ? 'No coach' : coach,
			manager: manager === '' ? 'No manager' : manager,
			members: members,
			image: logoUrl,
		};

		teamData.push(teamInfo);
		marbleData.push(...marbles);
	} catch (error) {
		console.error(`Error fetching team ${team}:`, error);
	}
}

async function fetchMarbleData(marble: string, team = '') {
	try {
		const marbleResponse = await axios.get(
			`${url}${encodeURIComponent(marble)}`
		);
		const $m = load(marbleResponse.data);
		const image = $m('img.pi-image-thumbnail').attr('src')?.trim() ?? '';
		const color = $m('[data-source="color"]').children('div').text();
		const marbleInfo = {
			name: marble,
			team,
			image,
			color,
		};
		return marbleInfo;
	} catch (error) {
		console.log(`${marble} Error: ${error}`);
		const marbleInfo = {
			name: marble,
			team,
			image: '',
			color: '',
		};
		return marbleInfo;
	}
}

async function marblesListFetch() {
	try {
		const response = await axios.get(`${url}List_of_Marbles`);
		const $ = load(response.data);
		const data: string[] = $('table.wikitable > tbody')
			.text()
			.split('\n')
			.filter(Boolean);
		data.shift();
		data.shift();
		const marbles = data.reduce((result, _, index, arr) => {
			if (index % 2 === 0 && index + 1 < arr.length) {
				result.push({
					name: arr[index],
					notes: extractMarbleNotes(arr[index + 1]),
				});
			}
			return result;
		}, [] as any[]);
		return marbles;
	} catch (e) {
		console.error(e);
		return [];
	}
}

function extractMarbleNotes(notesStr: string) {
	const split = notesStr.split('of the');
	console.log(notesStr);
	console.log(split);
	const [positionRaw, teamRaw] =
		split.length > 1
			? split
			: notesStr.split('of').length > 1
				? notesStr.split('of')
				: notesStr.split('in the');
	const position =
		positionRaw?.trim().split(' ').at(-1)?.trim().toUpperCase() ??
		'MISSING POSITION';
	const team = teamRaw?.trim() ?? 'MISSING';
	return { team, position };
}

async function main() {
	/* await Promise.all(teams.map((team) => fetchTeamInfo(team)));
	writeFileSync('yield/teams.json', JSON.stringify(teamData, null, 2)); */
	/* const marblesList = await marblesListFetch();
	const noDataMarbles = marblesList.filter(
		(e) =>
			!marbleData.find((d) => d.name.toUpperCase() === e!.name.toUpperCase())
	);
	writeFileSync(
		'yield/nodata_marbles.json',
		JSON.stringify(noDataMarbles, null, 2)
	); */
	/* const marblePromises = noDataMarbles.map((m) => fetchMarbleData(m!.name));
	const noTeamMarblesData = await Promise.all(marblePromises);
	marbleData.push(...noTeamMarblesData);
	writeFileSync('yield/marbles.json', JSON.stringify(marbleData, null, 2)); */
}

main();
