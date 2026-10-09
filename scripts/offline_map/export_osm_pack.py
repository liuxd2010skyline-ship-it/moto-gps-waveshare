"""Export real roads/building outer rings from an official OSM PBF.

Requires pyosmium 4.2.0. No map tiles, SDK internals, routing inference or
synthetic buildings are used. Keep the PBF and generated source metadata for
reproducibility; the phone consumes the smaller SQLite output, not the PBF.
"""
import argparse
import hashlib
import json
from pathlib import Path

import osmium


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--region", required=True)
    parser.add_argument("--source-url", required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    processor = osmium.FileProcessor(str(args.pbf)).with_locations().with_areas()
    factory = osmium.geom.GeoJSONFactory()
    counts = {"roads": 0, "buildings": 0, "invalid_geometry": 0,
              "building_holes_omitted": 0}
    with args.output.open("w", encoding="utf-8", newline="\n") as output:
        for item in processor:
            tags = dict(item.tags)
            try:
                if item.is_way() and tags.get("highway"):
                    if tags["highway"] in {"proposed", "construction", "raceway"}:
                        continue
                    geometry = json.loads(factory.create_linestring(item))
                    identifier = f"w{item.id}"
                    kind = "roads"
                elif item.is_area() and tags.get("building") not in {None, "no"}:
                    geometry = json.loads(factory.create_multipolygon(item))
                    identifier = f"a{item.id}"
                    kind = "buildings"
                    counts["building_holes_omitted"] += sum(
                        max(0, len(polygon) - 1) for polygon in geometry["coordinates"])
                else:
                    continue
                feature = {"type": "Feature", "id": identifier,
                           "properties": tags, "geometry": geometry}
                output.write(json.dumps(feature, ensure_ascii=False, separators=(",", ":")) + "\n")
                counts[kind] += 1
            except (osmium.InvalidLocationError, RuntimeError):
                counts["invalid_geometry"] += 1
    with args.pbf.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    metadata = {
        "region": args.region,
        "source_url": args.source_url,
        "source_timestamp": processor.header.get("osmosis_replication_timestamp"),
        "source_sha256": digest,
        "source_filename": args.pbf.name,
        "coordinate_system_input": "WGS-84",
        "extractor": "pyosmium 4.2.0",
        "geometry_scope": "source extract; building outer rings only",
        **counts,
    }
    args.output.with_suffix(".source.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metadata, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
