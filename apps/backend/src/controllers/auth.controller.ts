import axios, { type AxiosResponse } from 'axios';
import { Controller, CookieParam, Get } from 'routing-controllers';

@Controller('/auth')
export class AuthController {
  @Get('/discord/@me')
  async getDiscordUserInfo(
    @CookieParam('access_token') accessToken: string
  ): Promise<DiscordUserInfo> {
    console.log(accessToken);

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
    authResponse.data.role = 'user';
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
