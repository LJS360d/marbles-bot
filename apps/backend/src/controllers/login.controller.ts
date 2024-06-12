import type { Request, Response } from 'express';
import { Controller, Get, Req, Res } from 'routing-controllers';
import env from '../env';
import axios, { type AxiosResponse } from 'axios';

@Controller('/login')
export class LoginController {
  @Get('/discord')
  async discordLogin(@Res() res: Response) {
    if (!res.headersSent) {
      res.redirect(env.OAUTH2_URL);
    }
  }

  async getDiscordUserInfo(accessToken: string): Promise<DiscordUserInfo> {
    const authResponse: AxiosResponse<DiscordUserInfo, any> = await axios.get(
      'https://discord.com/api/v10/users/@me',
      {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      }
    );
    const userId = authResponse.data.id;
    const userAvatarHash = authResponse.data.avatar;
    authResponse.data.avatar = `https://cdn.discordapp.com/avatars/${userId}/${userAvatarHash}.png`;
    /* authResponse.data.role = this.config.loginData.ownerIds.includes(userId)
      ? 'owner'
      : 'user'; */
    return authResponse.data;
  }
}

export type DiscordUserInfo = {
  id: string;
  username: string;
  avatar: string;
  discriminator: string;
  public_flags: number;
  premium_type: number;
  flags: number;
  banner: string | null;
  accent_color: number;
  global_name: string;
  role: 'owner' | 'user';
  avatar_decoration_data: any | null; // TODO get proper type inference
  banner_color: string;
  mfa_enabled: boolean;
  locale: string;
  email: string;
  verified: boolean;
};
