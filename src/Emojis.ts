export const emojis = new Map<string, string>([
    ['fire', '🔥'],
    ['coffee', '☕'],
    ['red_heart', '❤️'],
    ['blue_heart', '💙'],
    ['green_heart', '💚'],
    ['white_heart', '🤍'],
    ['purple_heart', '💜'],
    ['orange_heart', '🧡'],
    ['yellow_heart', '💛'],
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
        "is getting angry",
    ]
    const randomIndex = Math.floor(Math.random() * possibleMessages.length)
    return possibleMessages[randomIndex]
}