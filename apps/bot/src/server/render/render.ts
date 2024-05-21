import ejs from 'ejs';
import env from '../../env';
import type { Props, RenderOptions } from './render.options';
import { ThemesIterator } from './themes';

const defaultOptions: RenderOptions = {
	themes: ThemesIterator,
	theme: ThemesIterator[0],
	title: 'Fonzi2 Starter Kit',
	version: env.VERSION,
};

export async function render(
	component: string,
	props?: Props,
	options?: Partial<RenderOptions>
) {
	options = { ...defaultOptions, ...options };
	const filepath = 'views/index.ejs';
	try {
		const content = await ejs.renderFile(
			filepath,
			{
				component,
				props,
				...options,
			},
			{ cache: true }
		);
		return content;
	} catch (error) {
		return JSON.stringify(error, null, 2);
	}
}

export async function hxRender(component: string, props?: Props) {
	return await ejs.renderFile(`views/hx/${component}.ejs`, props);
}
