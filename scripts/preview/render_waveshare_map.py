"""Render the Waveshare map design from the firmware palette and Jinan fixture.

This is a design preview, not an LVGL framebuffer capture or a live Baidu map.
The left disc follows the current firmware's layer order, widths, map extent,
heading-up projection and navigation layout. The right disc illustrates the
requested filled land-cover style; its green polygons are deliberately mock
geometry because the current MapScene has no green-space data.
"""

from __future__ import annotations

import json
import math
import re
import sqlite3
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
STYLE = ROOT / "shared/nav_ui/include/moto_map_visual_style.h"
SCENE = ROOT / "shared/demo_fixture/jinan_map_scene_sample.json"
CITY = ROOT / "shared/offline_map/jinan-v1.sqlite"
ROUTE = ROOT / "platforms/ios/App/Adapters/Navigation/JinanDemoFixture.generated.swift"
OUTPUT = ROOT / "docs/technical-proposal/assets/waveshare-map-preview.png"
DESIGN = 360
SCREEN = 466
SCALE = 3
PX = SCREEN / DESIGN
MAP_BOTTOM = round(232 * PX)
CONCEPT_GRASS = (24, 96, 67)
CONCEPT_BUILDING = (143, 185, 195)
CONCEPT_BUILDING_EDGE = (41, 77, 86)
CONCEPT_ROAD = (12, 27, 34)
CONCEPT_ROUTE_SHADOW = (66, 33, 74)
CONCEPT_ROUTE = (229, 91, 192)


def load_palette() -> dict[str, int]:
    source = STYLE.read_text(encoding="utf-8")
    return {
        name: int(value, 16) if value.startswith("0x") else int(value)
        for name, value in re.findall(r"(MOTO_MAP_[A-Z_]+)\s*=\s*(0x[0-9A-Fa-f]+|\d+)", source)
    }


def color(rgb: int) -> tuple[int, int, int]:
    return (rgb >> 16 & 255, rgb >> 8 & 255, rgb & 255)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    names = ["msyhbd.ttc", "msyh.ttc"] if bold else ["msyh.ttc", "simhei.ttf"]
    for name in names:
        path = Path("C:/Windows/Fonts") / name
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default(size=size)


def route_points() -> list[tuple[float, float]]:
    source = ROUTE.read_text(encoding="utf-8")
    block = source.split("static let routeGCJ02:", 1)[1].split("\n    ]", 1)[0]
    return [
        (float(lat), float(lon))
        for lon, lat in re.findall(
            r"GCJ02Point\(longitudeDeg:\s*([\d.]+),\s*latitudeDeg:\s*([\d.]+)\)",
            block,
        )
    ]


def dense_city_geometry(origin: tuple[float, float]) -> tuple[list[dict], list[dict]]:
    """Use the bundled Jinan pack for a denser future-style illustration."""
    centre_lat = round(origin[0] * 1_000_000)
    centre_lon = round(origin[1] * 1_000_000)
    lat_radius = 5_000
    lon_radius = 6_000
    roads: list[dict] = []
    buildings: list[dict] = []
    connection = sqlite3.connect(CITY)
    try:
        connection.execute("PRAGMA query_only=ON")
        for table, limit, target, names in (
            ("roads", 90, roads,
             ["motorway", "primary", "secondary", "residential", "service", "other"]),
            ("buildings", 120, buildings, ["generic", "landmark", "parking"]),
        ):
            rows = connection.execute(
                f"SELECT class,points FROM {table} "
                "WHERE min_lat_e6<=? AND max_lat_e6>=? "
                "AND min_lon_e6<=? AND max_lon_e6>=? LIMIT ?",
                (centre_lat + lat_radius, centre_lat - lat_radius,
                 centre_lon + lon_radius, centre_lon - lon_radius, limit),
            )
            for item_class, blob in rows:
                points = [list(pair) for pair in struct.iter_unpack("<ii", blob)]
                if len(points) >= (3 if table == "buildings" else 2):
                    target.append({"class": names[item_class], "points_e6": points})
    finally:
        connection.close()
    return roads, buildings


def project(
    point: tuple[float, float], origin: tuple[float, float], heading: float
) -> tuple[float, float]:
    """Mirror moto_nav_presenter.cpp's 466 px, heading-up projection."""
    latitude, longitude = point
    theta = math.radians(heading)
    pixels_per_metre = 0.44 * PX
    east = (
        (longitude - origin[1])
        * math.cos(math.radians(origin[0]))
        * math.pi / 180
        * 6_371_000
        * pixels_per_metre
    )
    north = (latitude - origin[0]) * math.pi / 180 * 6_371_000 * pixels_per_metre
    right = east * math.cos(theta) - north * math.sin(theta)
    forward = east * math.sin(theta) + north * math.cos(theta)
    return SCREEN / 2 + right, 196 * PX - forward


def draw_line(
    drawing: ImageDraw.ImageDraw,
    points: list[tuple[float, float]],
    fill: tuple[int, int, int],
    width: float,
) -> None:
    if len(points) < 2:
        return
    scaled = [(round(x * SCALE), round(y * SCALE)) for x, y in points]
    scaled_width = max(1, round(width * SCALE))
    drawing.line(scaled, fill=fill, width=scaled_width, joint="curve")
    r = scaled_width / 2
    for x, y in (scaled[0], scaled[-1]):
        drawing.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def draw_disc(
    scene: dict, route: list[tuple[float, float]],
    palette: dict[str, int], concept: bool,
    dense_roads: list[dict], dense_buildings: list[dict],
) -> Image.Image:
    canvas = Image.new("RGB", (SCREEN * SCALE, SCREEN * SCALE), color(palette["MOTO_MAP_BLACK"]))
    map_layer = Image.new("RGB", canvas.size, color(palette["MOTO_MAP_BLACK"]))
    draw = ImageDraw.Draw(map_layer)
    origin = route[0]
    delta_east = (route[1][1] - origin[1]) * math.cos(math.radians(origin[0]))
    delta_north = route[1][0] - origin[0]
    heading = math.degrees(math.atan2(delta_east, delta_north)) % 360

    def geom(item: dict) -> list[tuple[float, float]]:
        return [project((lat / 1_000_000, lon / 1_000_000), origin, heading)
                for lat, lon in item["points_e6"]]

    if concept:
        # These shapes show the intended visual grammar only. They are NOT
        # observed green-space geometry at the fixture's real coordinates.
        for poly in (
            [(10, 12), (94, 12), (110, 68), (70, 128), (8, 112)],
            [(348, 75), (463, 61), (463, 188), (385, 195), (338, 146)],
        ):
            draw.polygon([(round(x * SCALE), round(y * SCALE)) for x, y in poly],
                         fill=CONCEPT_GRASS)

    for building in dense_buildings if concept else scene["buildings"][:16]:
        polygon = geom(building)
        if len(polygon) < 3:
            continue
        if concept:
            draw.polygon([(round(x * SCALE), round(y * SCALE)) for x, y in polygon],
                         fill=CONCEPT_BUILDING)
            line_color = CONCEPT_BUILDING_EDGE
        else:
            line_color = color(palette[
                "MOTO_MAP_BUILDING_LANDMARK" if building["class"] == "landmark"
                else "MOTO_MAP_BUILDING"
            ])
        draw_line(draw, polygon + polygon[:1], line_color,
                  (2 if building["class"] == "landmark" else 1) * PX)

    for road in dense_roads if concept else scene["roads"][:24]:
        road_class = road["class"]
        major = road_class in {"motorway", "primary", "secondary"}
        service = road_class in {"service", "other"}
        if concept:
            line_color = CONCEPT_ROAD
            width = (6 if major else 4 if not service else 3) * PX
        else:
            key = "MOTO_MAP_ROAD_MAJOR" if major else (
                "MOTO_MAP_ROAD_MINOR" if service else "MOTO_MAP_ROAD"
            )
            line_color = color(palette[key])
            width = palette[
                "MOTO_MAP_ROAD_MAJOR_WIDTH" if major else (
                    "MOTO_MAP_ROAD_MINOR_WIDTH" if service else "MOTO_MAP_ROAD_WIDTH"
                )
            ] * PX
        draw_line(draw, geom(road), line_color, width)

    # The firmware's fade object is drawn after context but before the route.
    # Twenty-four eased strips make the map disappear into the lower black HUD.
    fade_top = round(palette["MOTO_MAP_FADE_START_Y"] * PX * SCALE)
    fade_height = round(palette["MOTO_MAP_FADE_HEIGHT"] * PX * SCALE)
    bands = palette["MOTO_MAP_FADE_BANDS"]
    overlay = Image.new("RGBA", map_layer.size, (0, 0, 0, 0))
    fade_draw = ImageDraw.Draw(overlay)
    for index in range(bands):
        y1 = fade_top + index * fade_height // bands
        y2 = fade_top + (index + 1) * fade_height // bands - 1
        opacity = (index + 1) ** 2 * 255 // (bands ** 2)
        fade_draw.rectangle((0, y1, overlay.width - 1, y2),
                            fill=(*color(palette["MOTO_MAP_BLACK"]), opacity))
    map_layer = Image.alpha_composite(map_layer.convert("RGBA"), overlay).convert("RGB")
    draw = ImageDraw.Draw(map_layer)

    route_screen = [project(point, origin, heading) for point in route[:24]]
    if concept:
        draw_line(draw, route_screen, CONCEPT_ROUTE_SHADOW, 14 * PX)
        draw_line(draw, route_screen, CONCEPT_ROUTE, 6 * PX)
    else:
        draw_line(draw, route_screen, color(palette["MOTO_MAP_ROUTE_SHADOW"]),
                  palette["MOTO_MAP_ROUTE_SHADOW_WIDTH"] * PX)
        draw_line(draw, route_screen, color(palette["MOTO_MAP_ROUTE"]),
                  palette["MOTO_MAP_ROUTE_WIDTH"] * PX)

    # Firmware keeps the vehicle at (180, 196) in its 360-unit layout.
    top_x, top_y = 180 * PX, 177 * PX
    def triangle(coords: list[tuple[float, float]], fill: tuple[int, int, int]) -> None:
        draw.polygon([(round((top_x + x * PX) * SCALE),
                       round((top_y + y * PX) * SCALE)) for x, y in coords], fill=fill)
    triangle([(0, 0), (-17, 36), (17, 36)], color(palette["MOTO_MAP_BLACK"]))
    triangle([(0, 5), (-11, 30), (11, 30)], color(palette["MOTO_MAP_ROUTE"]))

    # The LVGL map object occupies only y=0..px(232); HUD is on top below it.
    canvas.paste(map_layer.crop((0, 0, canvas.width, MAP_BOTTOM * SCALE)), (0, 0))
    hud = ImageDraw.Draw(canvas)
    white = color(palette["MOTO_MAP_ROUTE"])
    quiet = (120, 126, 127)
    sx = lambda n: round(n * PX * SCALE)
    # The navigation page's right-turn hero starts at design (29,220).
    arrow = [(29 + 34, 220 + 102), (29 + 34, 220 + 63),
             (29 + 55, 220 + 42), (29 + 84, 220 + 42)]
    hud.line([(sx(x), sx(y)) for x, y in arrow], fill=white,
             width=sx(12), joint="curve")
    hud.polygon([(sx(29 + 105), sx(220 + 42)),
                 (sx(29 + 79), sx(220 + 24)),
                 (sx(29 + 79), sx(220 + 60))], fill=white)
    hud.text((sx(151), sx(243)), "180", font=font(sx(48), True), fill=white)
    hud.text((sx(276), sx(260)), "m", font=font(sx(20)), fill=quiet)
    # Three lower page dots echo the firmware navigation layout.
    for index, radius in enumerate((8, 3, 3)):
        x, y = 176 + index * 21, 439
        hud.rounded_rectangle((sx(x - radius), sx(y - 2), sx(x + radius), sx(y + 2)),
                              radius=sx(2), fill=white if index == 0 else (48, 53, 57))

    mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, canvas.width - 1, canvas.height - 1), fill=255)
    round_canvas = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    round_canvas.paste(canvas, (0, 0), mask)
    return round_canvas.resize((SCREEN, SCREEN), Image.Resampling.LANCZOS)


def main() -> None:
    palette = load_palette()
    scene = json.loads(SCENE.read_text(encoding="utf-8"))
    route = route_points()
    if len(route) < 2:
        raise SystemExit("The Jinan route fixture has fewer than two points")
    dense_roads, dense_buildings = dense_city_geometry(route[0])
    width, height = 1260, 750
    image = Image.new("RGB", (width, height), (10, 16, 19))
    draw = ImageDraw.Draw(image)
    white = (242, 245, 242)
    muted = (151, 165, 167)
    draw.text((72, 34), "微雪圆屏地图 · 绘图设计预览", font=font(34, True), fill=white)
    draw.text((72, 86), "基于固件颜色 / 线宽 / 图层顺序与济南样例几何；不是设备截图", font=font(20), fill=muted)
    for x, title, subtitle, concept in (
        (86, "固件绘图代码", "原有图层 · 新增渐变 · 白色路线", False),
        (708, "地物填色目标", "更多建筑 · 绿色地块 · 粉色路线", True),
    ):
        draw.text((x, 139), title, font=font(26, True), fill=white)
        draw.text((x, 179), subtitle, font=font(18), fill=muted)
        disc = draw_disc(scene, route, palette, concept,
                         dense_roads, dense_buildings)
        cx, cy = x + 233, 454
        draw.ellipse((cx - 250, cy - 250, cx + 250, cy + 250), fill=(27, 36, 40))
        draw.ellipse((cx - 240, cy - 240, cx + 240, cy + 240), fill=(3, 5, 7))
        image.paste(disc, (x, 221), disc)
        draw.ellipse((x - 2, 219, x + 468, 689), outline=(52, 69, 74), width=2)
    draw.text((78, 706), "左：当前 MapScene 可绘制的图层", font=font(17), fill=muted)
    draw.text((707, 706), "右：济南包更密；绿地形状仅作示意", font=font(17), fill=muted)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT, optimize=True)
    print(OUTPUT)


if __name__ == "__main__":
    main()
