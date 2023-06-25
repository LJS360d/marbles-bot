import axios from 'axios';
import cheerio from 'cheerio';
import { createObjectCsvWriter as createCsvWriter } from 'csv-writer';

const url = 'https://jellesmarbleruns.fandom.com/wiki/';
const teams = [
    'Balls_of_Chaos',
    'Black_Jacks',
    'Bluefastics',
    'Bumblebees',
    'Chocolatiers',
    'Constrictors',
    'Crazy_Cat%27s_Eyes',
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
    'O%27rangers',
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
    'Wolfpack'
];

const teamData = [];
const marbleData = [];

const fetchTeamInfo = async (team: string) => {
    try {
        const response = await axios.get(`${url}${team}`);
        const $ = cheerio.load(response.data);

        const teamName = $('#firstHeading').text().trim();
        const logoUrl = $('img.pi-image-thumbnail').attr('src').trim();
        const color = $('div[data-source="color"]').find('div.pi-data-value.pi-font').text().trim();
        const coach = $('div[data-source="coach"]').find('div.pi-data-value.pi-font').text().trim();
        const manager = $('div[data-source="manager"]').find('div.pi-data-value.pi-font').text().trim();
        const membersRaw = $('table.article-table > tbody tr td[style]').text().trim();
        const membersSet = new Set(membersRaw.replace(/[ⅠⅡⅢ\[1\]]/g, '').split('\n').map(member => member.trim()));
        const members = Array.from(membersSet).join('|');

        const marblePromises = Array.from(membersSet).map(async (marble) => {
            try {
                const marbleResponse = await axios.get(`${url}${marble}`);
                const $marble = cheerio.load(marbleResponse.data);
                const marbleImage = $marble('img.pi-image-thumbnail').attr('src').trim();

                const marbleInfo = {
                    marbleName: marble,
                    marbleImage: marbleImage,
                };
                marbleData.push(marbleInfo);
            } catch (error) {
                console.log(`${marble} page does not exist`);
            }
        });

        await Promise.all(marblePromises);


        const teamInfo = {
            teamName: teamName,
            color: color,
            coach: coach == '' ? 'No coach' : coach,
            manager: manager == '' ? 'No manager' : manager,
            members: members,
            logoUrl: logoUrl,
        };

        teamData.push(teamInfo);
    } catch (error) {
        console.error(`Error fetching team ${team}:`, error);
    }
};

(async () => {
    await Promise.all(teams.map(team => fetchTeamInfo(team)));

    const teamsWriter = createCsvWriter({
        path: 'data/teams.csv',
        header: [
            { id: 'teamName', title: 'name' },
            { id: 'color', title: 'color' },
            { id: 'coach', title: 'coach' },
            { id: 'manager', title: 'manager' },
            { id: 'members', title: 'members' },
            { id: 'logoUrl', title: 'logo' }
        ]
    });

    await teamsWriter.writeRecords(teamData);

    const marblesWriter = createCsvWriter({
        path: 'data/marbles.csv',
        header: [
            { id: 'marbleName', title: 'name' },
            { id: 'marbleImage', title: 'image' }
        ]
    })
    await marblesWriter.writeRecords(marbleData);

})();