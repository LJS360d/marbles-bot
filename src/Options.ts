import { GatewayIntentBits as intents } from 'discord.js';

export const options = {
    intents: [
        //intents.AutoModerationConfiguration,
        //intents.AutoModerationExecution,
        //intents.DirectMessageReactions,
        //intents.DirectMessages,
        //intents.GuildEmojisAndStickers,
        //intents.GuildIntegrations,
        //intents.GuildInvites,
        intents.GuildMembers,
        intents.GuildMessageReactions,
        intents.GuildMessageTyping,
        intents.GuildMessages,
        //intents.GuildModeration,
        //intents.GuildPresences,
        //intents.GuildScheduledEvents,
        //intents.GuildVoiceStates,
        //intents.GuildWebhooks,
        intents.Guilds,
        intents.MessageContent,
    ],
}