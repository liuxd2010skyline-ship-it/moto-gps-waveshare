#pragma once

/** Load brightness before the deliberately dark boot frame is revealed. */
void device_settings_load_preferences();
/** Create the practical settings overlay; caller holds the LVGL lock. */
void device_settings_create();
/** Start the five-second battery monitor after UI creation. */
void device_settings_start_monitor();
/** Toggle/close settings; caller holds the LVGL lock. */
void device_settings_toggle();
void device_settings_close();
