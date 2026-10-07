#include "device_settings.h"

#include <cstdio>

#include "board_port.h"
#include "device_power_policy.hpp"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "lvgl.h"
#include "nvs.h"
#include "nvs_flash.h"

namespace {
constexpr char kTag[] = "device_settings";
constexpr char kNamespace[] = "device_ui";
constexpr char kBrightnessKey[] = "brightness";
lv_obj_t* overlay = nullptr;
lv_obj_t* battery_value = nullptr;
lv_obj_t* battery_status = nullptr;
lv_obj_t* brightness_value = nullptr;
lv_obj_t* brightness_slider = nullptr;
lv_obj_t* save_status = nullptr;
bool shown = false;
std::uint8_t saved_brightness = 100;
board_port_battery_t latest_battery{};

lv_obj_t* label(const char* text, int y, const lv_font_t* font) {
  lv_obj_t* object = lv_label_create(overlay);
  lv_label_set_text(object, text);
  lv_obj_set_width(object, 380);
  lv_obj_set_style_text_align(object, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_set_style_text_color(object, lv_color_white(), 0);
  lv_obj_set_style_text_font(object, font, 0);
  lv_obj_align(object, LV_ALIGN_TOP_MID, 0, y);
  return object;
}

void refresh_battery() {
  if (!shown || battery_value == nullptr) return;
  if (!latest_battery.available) {
    lv_label_set_text(battery_value, "--");
    lv_label_set_text(battery_status, "BATTERY UNAVAILABLE");
  } else if (!latest_battery.present) {
    lv_label_set_text(battery_value, "--");
    lv_label_set_text(battery_status, latest_battery.usb_power
        ? "NO BATTERY / USB POWER" : "NO BATTERY");
  } else {
    if (latest_battery.percent_valid) {
      lv_label_set_text_fmt(battery_value, "%u%%",
          static_cast<unsigned>(latest_battery.percent));
    } else {
      lv_label_set_text(battery_value, "--");
    }
    lv_label_set_text(battery_status, !latest_battery.percent_valid
        ? "WAITING FOR BATTERY GAUGE"
        : latest_battery.charging ? "CHARGING"
        : latest_battery.usb_power ? "USB POWER" : "ON BATTERY");
  }
}

void refresh_brightness() {
  lv_label_set_text_fmt(brightness_value, "BRIGHTNESS  %u%%",
      static_cast<unsigned>(board_port_get_brightness()));
}

void save_brightness() {
  const auto percent = board_port_get_brightness();
  if (percent == saved_brightness) return;
  nvs_handle_t storage = 0;
  esp_err_t result = nvs_open(kNamespace, NVS_READWRITE, &storage);
  if (result == ESP_OK) {
    result = nvs_set_u8(storage, kBrightnessKey, percent);
    if (result == ESP_OK) result = nvs_commit(storage);
    nvs_close(storage);
  }
  if (result == ESP_OK) {
    saved_brightness = percent;
    lv_label_set_text(save_status, "SAVED");
  } else {
    lv_label_set_text(save_status, "SAVE FAILED - TRY AGAIN");
    ESP_LOGW(kTag, "brightness persistence failed: %s", esp_err_to_name(result));
  }
}

void apply_brightness(int requested) {
  const auto value = moto::esp32::clamp_brightness(requested);
  const auto previous = board_port_get_brightness();
  const esp_err_t result = board_port_set_brightness(value);
  lv_slider_set_value(brightness_slider,
      result == ESP_OK ? value : previous, LV_ANIM_OFF);
  refresh_brightness();
  if (result != ESP_OK) {
    lv_label_set_text(save_status, "BRIGHTNESS UPDATE FAILED");
    ESP_LOGW(kTag, "AMOLED brightness update failed: %s", esp_err_to_name(result));
  } else {
    lv_label_set_text(save_status, value == saved_brightness
        ? "SAVED" : "RELEASE TO SAVE");
  }
}

void slider_event(lv_event_t* event) {
  if (lv_event_get_code(event) == LV_EVENT_VALUE_CHANGED) {
    apply_brightness(lv_slider_get_value(brightness_slider));
  } else {
    // Persist on release, never for every intermediate slider position.
    save_brightness();
  }
}

void button_event(lv_event_t* event) {
  const auto* action = static_cast<const char*>(lv_event_get_user_data(event));
  if (*action == 'b') {
    device_settings_close();
  } else {
    apply_brightness(static_cast<int>(board_port_get_brightness()) +
                     (*action == '+' ? 10 : -10));
    save_brightness();
  }
}

void button(const char* text, const char* action, int x, int y, int width) {
  lv_obj_t* object = lv_button_create(overlay);
  lv_obj_set_pos(object, x, y);
  lv_obj_set_size(object, width, 50);
  lv_obj_set_style_bg_color(object, lv_color_hex(0x343A3D), 0);
  lv_obj_set_style_radius(object, 10, 0);
  lv_obj_set_style_shadow_width(object, 0, 0);
  lv_obj_add_event_cb(object, button_event, LV_EVENT_CLICKED,
                      const_cast<char*>(action));
  lv_obj_t* title = lv_label_create(object);
  lv_label_set_text(title, text);
  lv_obj_set_style_text_color(title, lv_color_white(), 0);
  lv_obj_set_style_text_font(title, &lv_font_montserrat_20, 0);
  lv_obj_center(title);
}

void battery_monitor(void*) {
  while (true) {
    board_port_battery_t reading{};
    board_port_read_battery(&reading);
    // I2C work stays outside LVGL. Even a failed PMIC read cannot stall the
    // navigation renderer while holding its display lock.
    if (board_port_lock(100)) {
      latest_battery = reading;
      refresh_battery();
      board_port_unlock();
    }
    vTaskDelay(pdMS_TO_TICKS(5'000));
  }
}
}  // namespace

void device_settings_load_preferences() {
  std::uint8_t brightness = 100;
  const esp_err_t init = nvs_flash_init();
  if (init == ESP_OK) {
    nvs_handle_t storage = 0;
    if (nvs_open(kNamespace, NVS_READONLY, &storage) == ESP_OK) {
      nvs_get_u8(storage, kBrightnessKey, &brightness);
      nvs_close(storage);
    }
  } else {
    // The existing BLE startup handles incompatible NVS layouts. Settings
    // must not erase bonds or block boot simply because preferences are absent.
    ESP_LOGW(kTag, "brightness preferences not loaded: %s", esp_err_to_name(init));
  }
  saved_brightness = moto::esp32::clamp_brightness(brightness);
  board_port_set_brightness(saved_brightness);
}

void device_settings_create() {
  if (overlay != nullptr) return;
  overlay = lv_obj_create(lv_layer_top());
  lv_obj_remove_style_all(overlay);
  lv_obj_set_size(overlay, MOTO_DISPLAY_WIDTH, MOTO_DISPLAY_HEIGHT);
  lv_obj_set_style_bg_color(overlay, lv_color_black(), 0);
  lv_obj_set_style_bg_opa(overlay, LV_OPA_COVER, 0);
  lv_obj_remove_flag(overlay, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_GESTURE_BUBBLE);
  lv_obj_add_flag(overlay, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_HIDDEN);
  label("SETTINGS", 34, &lv_font_montserrat_28);
  label("BATTERY", 86, &lv_font_montserrat_16);
  battery_value = label("--", 109, &lv_font_montserrat_48);
  battery_status = label("READING BATTERY", 170, &lv_font_montserrat_16);
  brightness_value = label("BRIGHTNESS", 217, &lv_font_montserrat_20);
  brightness_slider = lv_slider_create(overlay);
  lv_obj_set_pos(brightness_slider, 128, 270);
  lv_obj_set_size(brightness_slider, 210, 12);
  lv_slider_set_range(brightness_slider, 10, 100);
  lv_slider_set_value(brightness_slider, board_port_get_brightness(), LV_ANIM_OFF);
  lv_obj_set_style_bg_color(brightness_slider, lv_color_hex(0x343A3D), LV_PART_MAIN);
  lv_obj_set_style_bg_color(brightness_slider, lv_color_white(), LV_PART_INDICATOR);
  lv_obj_set_style_bg_color(brightness_slider, lv_color_white(), LV_PART_KNOB);
  lv_obj_add_event_cb(brightness_slider, slider_event, LV_EVENT_VALUE_CHANGED, nullptr);
  lv_obj_add_event_cb(brightness_slider, slider_event, LV_EVENT_RELEASED, nullptr);
  lv_obj_add_event_cb(brightness_slider, slider_event, LV_EVENT_PRESS_LOST, nullptr);
  button("-", "-", 58, 251, 50);
  button("+", "+", 358, 251, 50);
  save_status = label("SAVED", 313, &lv_font_montserrat_16);
  button("BACK", "back", 163, 353, 140);
  label("PWR: SETTINGS / BACK", 415, &lv_font_montserrat_16);
  refresh_brightness();
}

void device_settings_start_monitor() {
  if (xTaskCreate(battery_monitor, "moto_battery", 3'072, nullptr, 1,
                  nullptr) != pdPASS) {
    ESP_LOGW(kTag, "battery monitor could not start");
  }
}

void device_settings_close() {
  if (overlay == nullptr || !shown) return;
  save_brightness();
  shown = false;
  lv_obj_add_flag(overlay, LV_OBJ_FLAG_HIDDEN);
}

void device_settings_toggle() {
  if (overlay == nullptr) return;
  if (shown) {
    device_settings_close();
  } else {
    shown = true;
    lv_obj_remove_flag(overlay, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(overlay);
    refresh_battery();
    refresh_brightness();
  }
}
