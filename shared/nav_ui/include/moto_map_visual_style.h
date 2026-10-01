#ifndef MOTO_MAP_VISUAL_STYLE_H
#define MOTO_MAP_VISUAL_STYLE_H

// Shared display palette and 360-unit design widths. Both the LVGL screen and
// the iPhone preview use these values; each platform draws with its own API.
enum {
    MOTO_MAP_DESIGN_WIDTH = 360,
    MOTO_MAP_BLACK = 0x050607,
    MOTO_MAP_ROUTE = 0xF3F4EF,
    MOTO_MAP_ROUTE_SHADOW = 0x303539,
    MOTO_MAP_ICE = 0xB8EDF5,
    MOTO_MAP_AMBER = 0xE6C84F,
    MOTO_MAP_ROAD = 0x42474B,
    MOTO_MAP_ROAD_MAJOR = 0x62696D,
    MOTO_MAP_ROAD_MINOR = 0x2B3033,
    MOTO_MAP_BUILDING = 0x24292C,
    MOTO_MAP_BUILDING_LANDMARK = 0x384044,
    MOTO_MAP_ROUTE_WIDTH = 6,
    MOTO_MAP_ROUTE_SHADOW_WIDTH = 13,
    MOTO_MAP_ROAD_WIDTH = 3,
    MOTO_MAP_ROAD_MAJOR_WIDTH = 4,
    MOTO_MAP_ROAD_MINOR_WIDTH = 2,
    MOTO_MAP_BUILDING_WIDTH = 1,
    MOTO_MAP_FADE_START_Y = 142,
    MOTO_MAP_FADE_HEIGHT = 90,
    MOTO_MAP_FADE_BANDS = 24,
};

#define MOTO_MAP_RED(rgb) (((rgb) >> 16) & 0xFF)
#define MOTO_MAP_GREEN(rgb) (((rgb) >> 8) & 0xFF)
#define MOTO_MAP_BLUE(rgb) ((rgb) & 0xFF)

#endif
