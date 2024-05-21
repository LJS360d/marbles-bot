import type { DiscordUserInfo } from 'fonzi2';

export type RenderOptions = Readonly<{
	themes: string[];
	theme: string;
	title: string;
	userInfo?: DiscordUserInfo;
	version: string;
}>;

export interface Props {
	[x: string]: any;
}
