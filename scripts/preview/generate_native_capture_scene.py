"""Bounded real Jinan geometry for the actual LVGL capture test (not a mockup)."""
import argparse
import math
import re
import sqlite3
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    source = (ROOT / 'platforms/ios/App/Adapters/Navigation/JinanDemoFixture.generated.swift').read_text(encoding='utf-8')
    block = source.split('static let routeGCJ02:', 1)[1].split('\n    ]', 1)[0]
    route = [(float(lat), float(lon)) for lon, lat in re.findall(r'GCJ02Point\(longitudeDeg:\s*([\d.]+),\s*latitudeDeg:\s*([\d.]+)\)', block)]
    route = route[12:36]
    origin = route[0]
    heading = math.atan2((route[1][1]-origin[1])*math.cos(math.radians(origin[0])), route[1][0]-origin[0])
    def project(p):
        n = (p[0]-origin[0])*math.pi/180*6371000*(.44*466/360)
        e = (p[1]-origin[1])*math.pi/180*6371000*math.cos(math.radians(origin[0]))*(.44*466/360)
        return round(207+e*math.cos(heading)-n*math.sin(heading)), round(300-e*math.sin(heading)-n*math.cos(heading))
    def visible(points):
        return min(p[0] for p in points)<466 and max(p[0] for p in points)>0 and min(p[1] for p in points)<350 and max(p[1] for p in points)>0
    sections=[]
    lat, lon = (round(v*1e6) for v in origin)
    with sqlite3.connect(ROOT / 'shared/offline_map/jinan-v1.sqlite') as db:
        db.execute('PRAGMA query_only=ON')
        for table, max_items, budget in [('roads',24,192), ('buildings',48,240)]:
            rows=db.execute(f'SELECT id,class,points FROM {table} WHERE min_lat_e6<=? AND max_lat_e6>=? AND min_lon_e6<=? AND max_lon_e6>=? ORDER BY abs((min_lat_e6+max_lat_e6)/2-?)+abs((min_lon_e6+max_lon_e6)/2-?) LIMIT 512',
                (lat+5000,lat-5000,lon+6000,lon-6000,lat,lon))
            selected=[];used=0
            for key, kind, blob in rows:
                points=[project((a/1e6,b/1e6)) for a,b in struct.iter_unpack('<ii',blob)]
                if not visible(points) or len(points)<(3 if table=='buildings' else 2) or used+len(points)>budget: continue
                if not all(-32768<=a<=32767 and -32768<=b<=32767 for a,b in points): continue
                selected.append((key,kind,points));used+=len(points)
                if len(selected)>=max_items: break
            sections.append(selected)
    tokens=[str(len(route))]
    tokens += [f'{x} {y}' for x,y in map(project,route)]
    for index, section in enumerate(sections):
        tokens.append(str(len(section)))
        for key,kind,points in section:
            tokens.append(f'{kind} {key & 0xFFFFFFFF} {len(points)}' if index else f'{kind} {len(points)}')
            tokens += [f'{x} {y}' for x,y in points]
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text('\n'.join(tokens)+'\n',encoding='utf-8')
    print(f'OSM Jinan: {len(sections[0])} roads, {len(sections[1])} complete building rings; native capture input ready.')

if __name__ == '__main__': main()
