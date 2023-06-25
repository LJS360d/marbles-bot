export const emojis = new Map<string, string>([
    ['fire', '🔥'],
    ['coffee', '☕'],
    ['sparkles', '✨'],
    ['red_heart', '❤️'],
    ['blue_heart', '💙'],
    ['red_circle', '🔴'],
    ['blue_circle', '🔵'],
])
export function getRandomEmoji() {
    const possibleEmojis = Array.from(emojis.keys())
    const randomIndex = Math.floor(Math.random() * possibleEmojis.length)
    return emojis.get(possibleEmojis[randomIndex])
}
export function getRandomSpawnMessage() {
    const possibleMessages = [
        "rolled in",
        "spawned",
        "manifested itself",
        "came into existance",
        "wants to be catched",
        "is coming to life",
        "is on a roll",
        "fell from the sky",
        "became whole"
    ]
    const randomIndex = Math.floor(Math.random() * possibleMessages.length)
    return possibleMessages[randomIndex]
}