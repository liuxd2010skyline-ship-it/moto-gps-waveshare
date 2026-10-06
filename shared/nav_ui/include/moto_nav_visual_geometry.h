#pragma once

// Native 466 x 466 screen coordinates from the approved V6 proportion sheet.
// Keep the geographic projection and LVGL layout on the same rider anchor.
// These constants describe a visual target; the real map geometry still comes
// from the phone's route and MapScene messages.
enum {
    MOTO_NAV_RIDER_X = 207,
    MOTO_NAV_RIDER_Y = 300,
    MOTO_NAV_MAP_BOTTOM_Y = 350,
    MOTO_NAV_FADE_START_Y = 294,
    MOTO_NAV_FADE_HEIGHT = 56,
    MOTO_NAV_MARKER_X = 175,
    MOTO_NAV_MARKER_Y = 264,
    MOTO_NAV_MARKER_WIDTH = 64,
    MOTO_NAV_MARKER_HEIGHT = 72,
    MOTO_NAV_MANEUVER_X = 101,
    MOTO_NAV_MANEUVER_Y = 342,
    MOTO_NAV_MANEUVER_SIZE = 64,
    MOTO_NAV_DISTANCE_X = 174,
    MOTO_NAV_DISTANCE_Y = 345,
    MOTO_NAV_SPEED_LIMIT_X = 322,
    MOTO_NAV_SPEED_LIMIT_Y = 335,
    MOTO_NAV_SPEED_LIMIT_SIZE = 56,
};
