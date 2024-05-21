import { Colors, type ColorResolvable } from 'discord.js';

export function getRandom(min: number, max: number): number {
	return Math.floor(Math.random() * (max - min + 1) + min);
}

export function getRandomArrayItem<T>(arr: T[]): T {
	const randomIndex = Math.floor(Math.random() * arr.length);
	return arr[randomIndex];
}

export function getRandomDiscordColor(): ColorResolvable {
	return getRandomArrayItem(Object.values(Colors));
}
