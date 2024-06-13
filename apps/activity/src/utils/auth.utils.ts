export function getCookie(name: string) {
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) return parts.pop()!.split(';').shift();
  return null;
}

export function setCookie(name: string, value: string, days: number) {
  const expires = new Date();
  expires.setTime(expires.getTime() + days * 24 * 60 * 60 * 1000);
  document.cookie = `${name}=${value};expires=${expires.toUTCString()};path=/`;
}

export function getAccessToken() {
  return getCookie('access_token');
}

export async function logout() {
  document.cookie = 'access_token=; expires=Thu, 01 Jan 1970 00:00:00 GMT';
  // TODO: logout from server
}
