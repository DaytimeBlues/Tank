import {readFileSync} from 'node:fs';
import {SOLO_MAP} from './solo-map.mjs';
// One authored geometry contract; SOLO_MAP remains an unchanged comparison baseline.
const document=JSON.parse(readFileSync(new URL('../data/roadside-cover.json',import.meta.url),'utf8'));
export const ROADSIDE_MAP={...SOLO_MAP,cover:document.cover};
