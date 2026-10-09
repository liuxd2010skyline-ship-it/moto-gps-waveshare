"""Build the pinned Beijing extract as a phone-local offline map resource."""
import argparse
import hashlib
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FILENAME = "beijing-261004.osm.pbf"
SOURCE = "https://download.geofabrik.de/asia/china/" + FILENAME


def download(url, destination):
    request = urllib.request.Request(url, headers={"User-Agent": "MotoGPS-offline-pack/1.0"})
    partial = destination.with_suffix(destination.suffix + ".partial")
    with urllib.request.urlopen(request, timeout=90) as response, partial.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)
    partial.replace(destination)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    args = parser.parse_args()
    directory = ROOT / "build/offline-maps"
    directory.mkdir(parents=True, exist_ok=True)
    pbf = args.source or directory / FILENAME
    if not pbf.is_file():
        download(SOURCE, pbf)
    checksum_file = directory / (FILENAME + ".md5")
    download(SOURCE + ".md5", checksum_file)
    expected = checksum_file.read_text().split()[0].lower()
    with pbf.open("rb") as source:
        actual = hashlib.file_digest(source, "md5").hexdigest()
    if len(expected) != 32 or actual != expected:
        raise ValueError("Official source checksum does not match the downloaded PBF")
    geojson = directory / "beijing.geojsonseq"
    subprocess.run([sys.executable, str(ROOT / "scripts/offline_map/export_osm_pack.py"),
                    str(pbf), str(geojson), "--region", "北京市（含海淀区）",
                    "--source-url", SOURCE], check=True)
    metadata_file = geojson.with_suffix(".source.json")
    metadata = json.loads(metadata_file.read_text(encoding="utf-8"))
    metadata.update(reference_latitude=40, context_all_roads=True,
                    source_label="OpenStreetMap / Geofabrik Beijing extract")
    metadata_file.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    output = directory / "beijing-v1.sqlite"
    subprocess.run(["node", str(ROOT / "scripts/offline_map/build_jinan_sqlite.mjs"),
                    str(geojson), str(output), str(metadata_file)], check=True)
    subprocess.run(["node", str(ROOT / "scripts/offline_map/validate_beijing_sqlite.mjs"),
                    str(output)], check=True)


if __name__ == "__main__":
    main()
