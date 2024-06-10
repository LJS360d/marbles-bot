import { Server } from 'colyseus';
import 'dotenv/config';

async function main() {
  const server = new Server({
    devMode: process.env.NODE_ENV !== 'production',
  });
  const port = Number(process.env.PORT) || 8080;
  server.listen(port);
  console.log(`Listening on port ${port}`);
}

main();
