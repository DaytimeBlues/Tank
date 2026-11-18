import {riverCrossings} from './river-crossings.mjs';
import {readFileSync} from 'node:fs';
import {SOLO_MAP} from './solo-map.mjs';
// One authored geometry contract; SOLO_MAP remains an unchanged comparison baseline.
const document=JSON.parse(readFileSync(new URL('../data/roadside-cover.json',import.meta.url),'utf8'));
const landmarks=JSON.parse(readFileSync(new URL('../data/depot-landmarks.json',import.meta.url),'utf8')).landmarks;
const districtMeshes=JSON.parse(readFileSync(new URL('../data/windmill-district.json',import.meta.url),'utf8')).placements;
export const ROADSIDE_MAP=riverCrossings({...SOLO_MAP,cover:document.cover,landmarks,districtMeshes});
