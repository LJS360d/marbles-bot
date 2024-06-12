import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import { createServer } from 'node:http';
import { createExpressServer } from 'routing-controllers';

const app = createExpressServer({
  cors: true,
  controllers: ['./src/controllers/*.controller.ts'],
});
export const httpServer = createServer(app);

app.use(cors());
app.use(helmet());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(morgan('dev'));
app.use(express.static('public'));
export default app;
