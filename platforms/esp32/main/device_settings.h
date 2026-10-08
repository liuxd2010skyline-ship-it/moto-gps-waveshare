#pragma once
#include "moto_nav_ui.h"

/** Load brightness before the deliberately dark boot frame is revealed. */
void device_settings_load_preferences();
/** Create the practical settings overlay; caller holds the LVGL lock. */
void device_settings_create();
/** Start the five-second battery monitor after UI creation. */
void device_settings_start_monitor();
/** Toggle/close settings; caller holds the LVGL lock. */
void device_settings_toggle();
void device_settings_close();
/** Phone preferences are applied by the render task while holding LVGL's lock. */
void device_settings_apply_phone_preferences(const moto_ui_appearance_t*, unsigned char brightness);
