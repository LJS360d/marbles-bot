import express from 'express';
import morgan from 'morgan';
import { createServer } from 'node:http';
import { createExpressServer } from 'routing-controllers';
import { AuthController } from './controllers/auth.controller';
import { LoginController } from './controllers/login.controller';

const app = createExpressServer({
  controllers: [LoginController, AuthController],
});
export const httpServer = createServer(app);

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(morgan('dev'));
app.use(express.static('public'));
export default app;
