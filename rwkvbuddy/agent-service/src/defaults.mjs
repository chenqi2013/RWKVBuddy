import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

// Deployment credentials stay in the ignored local profile; clean checkouts use the example.
const localProfile = new URL('../default-connection.json', import.meta.url);
const userProfile = join(homedir(),
  ...(process.platform === 'darwin' ? ['Library', 'Application Support'] : ['.local', 'share']),
  'RWKVBuddy', 'default-connection.json');
const profile = process.env.RWKVBUDDY_CONNECTION_FILE || (existsSync(localProfile) ? localProfile : existsSync(userProfile) ? userProfile : new URL('../default-connection.example.json', import.meta.url));
export const defaultConnection = JSON.parse(readFileSync(profile, 'utf8'));
