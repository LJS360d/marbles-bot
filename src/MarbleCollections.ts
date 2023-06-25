import { CountingSet } from './structures/CountingSet';

//Remove comments on database stuff in production
//const Database = require("@replit/database")

export const collections = new Map<string, MarbleCollection>();
//export const DB = new Database();
export const DB = new Map<string, string>();
interface MarbleCollectionJSON {
    userId: string;
    guildId: string;
    map: {
        values: string[];
        counts: { [key: string]: number };
    }
}
export class MarbleCollection extends CountingSet<string>
{
    userId: string;
    guildId: string;
    constructor(userId: string, guildId: string) {
        super();
        this.userId = userId;
        this.guildId = guildId;
        collections.set(`${userId}-${guildId}`, this);
    }
    getMarblesNames() {
        return Array.from(this.countMap.keys());
    }

    loadCollection(jsonString: string) {
        const json = JSON.parse(jsonString)
        this.fromJSON(json)
    }

    saveCollection() {
        const collection = collections.get(`${this.userId}-${this.guildId}`);
        const collectionJSON = JSON.stringify(collection.toJSON());
        DB.set(`${this.userId}-${this.guildId}`, collectionJSON)
    }

    private toJSON(): MarbleCollectionJSON {
        const values = [...this];
        const counts: { [key: string]: number } = {};
        for (const [key, value] of this.countMap) {
            counts[key] = value;
        }
        return {
            userId: this.userId,
            guildId: this.guildId,
            map: { values, counts }
        };
    }

    private fromJSON(json: MarbleCollectionJSON): void {
        for (const key in json.map.counts) {
            this.add(key);
        }
    }
}

export async function loadAllCollections() {
    /* DB.list().then(async (keys) => {
        for (const key of keys) {
            const collection = new MarbleCollection(key.split('-')[0], key.split('-')[1]);
            collection.loadCollection(await DB.get(key) as string);
        }

    }) */

}



