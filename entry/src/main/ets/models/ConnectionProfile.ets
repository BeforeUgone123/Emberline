export interface ConnectionProfile {
  id: string;
  title: string;
  host: string;
  port: number;
  user: string;
  password: string;
}

export function createFusionVmProfile(host: string, port: number, user: string, password: string): ConnectionProfile {
  const normalizedHost = host.trim().length > 0 ? host.trim() : '172.16.100.2';
  const normalizedUser = user.trim().length > 0 ? user.trim() : 'user';
  return {
    id: `${normalizedUser}@${normalizedHost}:${port}`,
    title: `${normalizedUser}@${normalizedHost}`,
    host: normalizedHost,
    port: port > 0 ? port : 22,
    user: normalizedUser,
    password
  };
}
