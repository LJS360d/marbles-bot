import {
    readdir,
    readFileSync,
    writeFileSync,
} from 'fs';

import { CountingSet } from './structures/CountingSet';

export const collections = new Map<string, MarbleCollection>();
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
        writeFileSync(`./data/collections/${this.userId}-${this.guildId}.json`, JSON.stringify(this.toJSON()))
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
            this.setValue(key, json.map.counts[key]);
        }
    }
}

export async function loadAllCollections() {
    readdir('./data/collections', (err, files) => {
        if (err) console.log(err);
        files.forEach(file => {
            const content = readFileSync(`./data/collections/${file}`, 'utf8');
            const collection = new MarbleCollection(file.split('-')[0], file.split('-')[1].replace('.json', ''));
            collection.loadCollection(content);
        })
    })

}



