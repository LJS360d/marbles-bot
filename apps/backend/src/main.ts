import { type MonitorOptions, monitor } from '@colyseus/monitor';
import { WebSocketTransport } from '@colyseus/ws-transport';
import { Server as ColyseusServer } from 'colyseus';
import 'reflect-metadata';
import Container from 'typedi';
import { GameRoom } from './colyseus/rooms/GameRoom';
import env from './env';
import app, { httpServer } from './express.app';
import logger, { CC } from './logger';

async function main() {
  const server = new ColyseusServer({
    transport: new WebSocketTransport({
      server: httpServer,
      pingInterval: 6000,
      pingMaxRetries: 4,
      clientTracking: true,
    }),
    devMode: env.DEV,
    gracefullyShutdown: true,
    greet: false,
  });
  server
    .define('game', GameRoom)
    // filterBy allows us to call joinOrCreate and then hold one game per channel
    // https://discuss.colyseus.io/topic/345/is-it-possible-to-run-joinorcreatebyid/3
    .filterBy(['channelId']);
  server.listen(env.PORT);
  logger.info(
    `Listening on ${CC.underline}http://localhost:${env.PORT}${CC.stop}`
  );
  Container.set(ColyseusServer, server);
  app.use('/colyseus/monitor', monitor(server as Partial<MonitorOptions>));
}

main().catch((err) => logger.error(err));
