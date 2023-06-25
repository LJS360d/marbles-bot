import { parse } from 'csv-parse';
import { ColorResolvable } from 'discord.js';
import { readFileSync } from 'fs';

export interface Rarity {
    name: string;
    color: ColorResolvable;
}
export interface Team {
    name: string;
    color: string;
    coach: string;
    manager: string;
    members: Marble[];
    logo: string;
}

export interface Marble {
    name: string;
    image: string;
}

const teamsCSVData = readFileSync('./data/teams.csv', 'utf-8');
const marblesCSVData = readFileSync('./data/marbles.csv', 'utf-8');

export const teamMap: Map<string, Team> = new Map();
export let marblesArray: Marble[] = [];

function parseTeamsData(data: any[], marblesData: Marble[]) {
    data.forEach((teamData: any) => {
        const { name, color, coach, manager, members, logo } = teamData;

        const membersArray = members.split('|');

        const marbleMembers: Marble[] = membersArray.map((member: string) => {
            const marble = marblesData.find((marbleData: any) => marbleData.name === member);
            if (marble === undefined) return {
                name: member,
                image: '',
            }
            return {
                name: marble.name,
                image: marble.image,
            };
        });

        teamMap.set(name, {
            name,
            color,
            coach,
            manager,
            members: marbleMembers,
            logo: logo,
        });
    });
};

function mapMarblesData(data: any[]) {
    const marblesData: Marble[] = data.map((marbleData: any) => ({
        name: marbleData.name,
        image: marbleData.image,
    }));

    return marblesData;
};

export function loadMarblesData() {
    parse(teamsCSVData, { columns: true }, (err, teamsData) => {
        if (err) console.log(err);
        parse(marblesCSVData, { columns: true }, (err, marblesData) => {
            if (err) console.log(err);
            marblesArray = mapMarblesData(marblesData);

            parseTeamsData(teamsData, marblesArray);
            console.log('Marbles data loaded successfully');
            //Can now use loaded teamMap and marblesArray 

        })
    })
}

export function getRandomMarble() {
    return marblesArray[Math.floor(Math.random() * marblesArray.length)];
}

export function getMarbleByName(name: string) {
    return marblesArray.find((marble: Marble) => marble.name === name);
}

export function getRandomTeam() {
    const teamNames = Array.from(teamMap.keys());
    return teamMap.get(teamNames[Math.floor(Math.random() * teamNames.length)]);
}

export function getTeamByMarble(marble: Marble) {
    return Array.from(teamMap.values()).find((team: Team) => team.members.find((member: Marble) => member.name === marble.name));
}

export function getRandomRarity(): Rarity {
    const colorMap = new Map<string, ColorResolvable>()
    colorMap.set('Common', "White");
    colorMap.set('Uncommon', "Green");
    colorMap.set('Rare', "Blue");
    colorMap.set('Epic', "Purple");
    colorMap.set('Legendary', "Gold");
    const random = Math.floor(Math.random() * Array.from(colorMap.keys()).length);
    const color = Array.from(colorMap.values())[random];
    const rarity = Array.from(colorMap.keys())[random];
    return { name: rarity, color: color } as Rarity;
}