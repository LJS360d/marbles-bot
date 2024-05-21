import type { ChatInputCommandInteraction, GuildMember } from 'discord.js';
import env from '../env';

export async function ensureAdminInteraction(
	interaction: ChatInputCommandInteraction<'cached'>,
	msg?: string
) {
	const admin = isAdmin(interaction.member);
	if (!admin) {
		void interaction.reply({
			content: msg ?? 'You are not authorized to use this command.',
			ephemeral: true,
		});
	}
	return admin;
}

export async function isAdmin(user: GuildMember) {
	if (env.OWNER_IDS.includes(user.id)) {
		return true;
	}
	const perms = user.permissions;
	if (perms.has('Administrator')) {
		return true;
	}
	return false;
}
