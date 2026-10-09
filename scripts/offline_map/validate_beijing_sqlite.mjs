import fs from 'node:fs';
import crypto from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';

const file = process.argv[2] ?? 'build/offline-maps/beijing-v1.sqlite';
const database = new DatabaseSync(file, {readOnly:true});
const metadata = Object.fromEntries(database.prepare('SELECT key,value FROM metadata').all().map(x=>[x.key,x.value]));
function check(value, message) { if (!value) throw new Error(message); }
check(database.prepare('PRAGMA integrity_check').get().integrity_check === 'ok', 'Damaged map');
check(database.prepare('PRAGMA application_id').get().application_id === 0x4d475053, 'Wrong file type');
check(metadata.coordinate_system === 'GCJ-02' && metadata.schema_version === '1', 'Wrong coordinates/schema');
check(metadata.source_sha256?.length === 64 && metadata.attribution?.includes('OpenStreetMap'), 'Missing provenance');
const counts = {};
for (const table of ['roads','buildings']) {
  counts[table] = Number(database.prepare(`SELECT count(*) n FROM ${table}`).get().n);
  const tree = table === 'roads' ? 'road_rtree' : 'building_rtree';
  check(counts[table] === Number(database.prepare(`SELECT count(*) n FROM ${tree}`).get().n), 'Broken index');
  for (const row of database.prepare(`SELECT * FROM ${table}`).iterate()) {
    const buffer = Buffer.from(row.points);
    const points = [];
    for (let i=0;i<buffer.length;i+=8) points.push([buffer.readInt32LE(i),buffer.readInt32LE(i+4)]);
    check(points.every(([a,b])=>a>=38_000_000&&a<=42_000_000&&b>=114_000_000&&b<=119_000_000), 'Non-Beijing geometry');
    check(Math.min(...points.map(x=>x[0])) === row.min_lat_e6 && Math.max(...points.map(x=>x[0])) === row.max_lat_e6 &&
          Math.min(...points.map(x=>x[1])) === row.min_lon_e6 && Math.max(...points.map(x=>x[1])) === row.max_lon_e6, 'Bounds mismatch');
    if(table === 'buildings') check(points.length>=3 && points[0].join() !== points.at(-1).join(), 'Bad footprint');
  }
}
check(counts.roads > 5_000 && counts.buildings > 5_000, 'Extract unexpectedly sparse');
// GCJ-02 approximate city neighbourhoods, not a claim of complete surveying.
const places = [
  ['Haidian Zhongguancun',39.9845,116.3225],
  ['Haidian Wudaokou',39.9925,116.3430],
  ['Haidian Shangdi',40.0330,116.3040],
];
const coverage = places.map(([name,lat,lon])=> {
  const range=[Math.round((lat-.006)*1e6),Math.round((lat+.006)*1e6),Math.round((lon-.008)*1e6),Math.round((lon+.008)*1e6)];
  const result={name};
  for(const [table,key] of [['road_rtree','roads'],['building_rtree','buildings']]) {
    result[key]=Number(database.prepare(`SELECT count(*) n FROM ${table} WHERE max_lat_e6>=? AND min_lat_e6<=? AND max_lon_e6>=? AND min_lon_e6<=?`).get(...range).n);
  }
  check(result.roads>0 && result.buildings>0, `No real map features near ${name}`);
  return result;
});
database.close();
const sha256=crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
console.log(JSON.stringify({file,sha256,counts,coverage,source:metadata.source_url,snapshot:metadata.source_snapshot},null,2));
