import express, {
    Request,
    Response,
} from 'express';
import http from 'http';

import { spawnChannels } from './EventManager';
import {
    client,
    remainingTime,
} from './main';
import { collections } from './MarbleCollections';

export function startAdminServer() {
    const app: express.Application = express();
    const httpServer: http.Server = http.createServer(app);
    app.set('view engine', 'ejs');

    app.get('/', (req: Request, res: Response) => {
        const props = {
            client: client,
            guilds: client.guilds.cache,
            channels: new Set<string>(),
            time: formatTime(remainingTime),
            collections: collections
        };
        client.guilds.cache.forEach(guild => {
            guild.channels.cache.forEach(channel => {
                if (spawnChannels.has(channel.id))
                    props.channels.add(channel.name);
            })
        })
        res.render('admin', props);

        Array.from(collections.keys()).forEach(collection => {
            app.get(`/${collection}`, (req: Request, res: Response) => {
                res.json(collections.get(collection));
            });
        });
    });
    app.get('/time', (req: Request, res: Response) => {
        res.json(formatTime(remainingTime));
    })

    //const PORT: number | string = process.env.PORT || 8080;
    const PORT = 8080;
    httpServer.listen(PORT, () => {
        console.log(`Server listening on port ${PORT}`);
    });

}
function formatTime(milliseconds: number) {
    const date = new Date(milliseconds);
    const hours = date.getUTCHours().toString().padStart(2, '0');
    const minutes = date.getUTCMinutes().toString().padStart(2, '0');
    const seconds = date.getUTCSeconds().toString().padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
}
