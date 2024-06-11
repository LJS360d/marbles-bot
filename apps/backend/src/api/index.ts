import app from '../express.app';

const registerRoutes = () => {
  app.get('/', (req, res) => {
    res.send('Hello World!');
  });
};

export default registerRoutes;
