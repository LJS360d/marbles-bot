import { Controller, Get, Redirect } from 'routing-controllers';
import env from '../env';

@Controller('/login')
export class LoginController {
  @Get('/discord')
  @Redirect(env.OAUTH2_URL)
  async discordLogin() {}
}
