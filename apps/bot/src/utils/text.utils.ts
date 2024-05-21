import type { MarbleDocumentFields } from '../datastore/structure/marbles/models/marble.model';
import { getRandomArrayItem } from './random.utils';

export const emojis = new Map<string, string>([
	['fire', '🔥'],
	['coffee', '☕'],
	['sparkles', '✨'],
	['star', '⭐'],
	['red_heart', '❤️'],
	['green_heart', '💚'],
	['blue_heart', '💙'],
	['red_circle', '🔴'],
	['green_circle', '🟢'],
	['blue_circle', '🔵'],
]);

export function getRandomEmoji() {
	return getRandomArrayItem(Array.from(emojis.values()));
}

export const spawnMessages = [
	'rolled in',
	'spawned',
	'manifested itself',
	'came into existence',
	'wants to be collected',
	'is coming to life',
	'is on a roll',
	'fell from the sky',
	'became whole',
	'just popped up',
	'magically appeared',
	'materialized out of nowhere',
	'decided to join the party',
	'teleported in with style',
	'was summoned by your charisma',
	'jumped out of a portal',
	'slid into this chat',
	'hitchhiked on a comet',
	'arrived with a bang',
	'made a dramatic entrance',
	'rolled in like a boss',
	'burst into existence',
	'appeared in a puff of smoke',
	'dropped in from another dimension',
	'floated down like a feather',
	'was birthed from the chaos',
	'spun into your world',
];

export function getRandomSpawnMessage() {
	return getRandomArrayItem(spawnMessages);
}

export const marbleAdjectives = [
	'shiny',
	'sparkling',
	'glowing',
	'mysterious',
	'colorful',
	'enchanting',
	'vibrant',
	'radiant',
	'glimmering',
	'luminous',
	'dazzling',
	'brilliant',
	'iridescent',
	'captivating',
	'majestic',
	'mesmerizing',
	'prismatic',
	'gleaming',
	'resplendent',
	'glossy',
	'bewitching',
	'ethereal',
	'translucent',
	'opalescent',
	'glittering',
	'radiating',
	'spellbinding',
	'alluring',
	'enthralling',
	'hypnotic',
	'spectacular',
	'magnificent',
	'splendid',
	'stunning',
	'breathtaking',
	'shimmering',
	'astonishing',
	'exquisite',
	'otherworldly',
];

export function getRandomAdjective() {
	return getRandomArrayItem(marbleAdjectives);
}

function resolveIndefiniteArticle(word: string): string {
	const vowels = ['a', 'e', 'i', 'o', 'u'];
	const firstLetter = word[0].toLowerCase();
	return vowels.includes(firstLetter) ? 'An' : 'A';
}

export function getMarbleSpawnTitle(marble: string) {
	const adjective = getRandomAdjective();
	const article = resolveIndefiniteArticle(adjective);
	return `${article} ${adjective} \`${marble}\` ${getRandomSpawnMessage()}!`;
}

export function getMarbleSpawnDescription(marble: MarbleDocumentFields) {
	const color = marble.color || 'Unknown';
	return `Color: ${color}\n\n${marble.extra}`;
}
