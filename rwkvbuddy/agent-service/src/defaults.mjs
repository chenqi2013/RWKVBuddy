import { existsSync, readFileSync } from 'node:fs';

// Deployment credentials stay in the ignored local profile; clean checkouts use the example.
const localProfile = new URL('../default-connection.json', import.meta.url);
const profile = existsSync(localProfile) ? localProfile : new URL('../default-connection.example.json', import.meta.url);
export const defaultConnection = JSON.parse(readFileSync(profile, 'utf8'));
