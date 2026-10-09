#include <atomic>
#include <cstdint>

#include "ble_nav_transport_nimble.h"
#include "board_port.h"
#include "device_power_policy.hpp"
#include "device_settings.h"
#include "esp_err.h"
#include "esp_attr.h"
#include "esp_log.h"
#include "esp_sleep.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "moto_nav_presenter.hpp"
#include "moto_nav_ui.h"
#include "phone_nav_bridge.h"

namespace {
constexpr char kTag[] = "moto_gps";
constexpr std::uint64_t kPowerHoldMs = 3'000;

enum class StartupStage : std::uint32_t {
  BoardInitialization, BootFrame, MainLock, MainConstruction, FirstMainFrame,
  Ready
};
std::atomic<StartupStage> startup_stage{StartupStage::BoardInitialization};
constexpr std::uint32_t kStartupRecoveryMagic = 0x4D475053;
RTC_NOINIT_ATTR std::uint32_t startup_recovery_marker;
RTC_NOINIT_ATTR std::uint32_t startup_previous_stage;
bool startup_is_recovery = false;

const char* startup_stage_name(StartupStage stage) {
  switch (stage) {
    case StartupStage::BoardInitialization: return "board initialization";
    case StartupStage::BootFrame: return "first boot frame";
    case StartupStage::MainLock: return "main UI display lock";
    case StartupStage::MainConstruction: return "main UI construction";
    case StartupStage::FirstMainFrame: return "first main frame flush";
    case StartupStage::Ready: return "ready";
  }
  return "unknown";
}

void startup_guard_task(void*) {
  const auto started = esp_timer_get_time();
  while (esp_timer_get_time() - started < 20'000'000) {
    if (startup_stage.load(std::memory_order_acquire) == StartupStage::Ready) {
      startup_recovery_marker = 0;
      vTaskDelete(nullptr);
      return;
    }
    vTaskDelay(pdMS_TO_TICKS(100));
  }
  const auto stage = startup_stage.load(std::memory_order_acquire);
  if (stage == StartupStage::Ready) {
    startup_recovery_marker = 0;
    vTaskDelete(nullptr);
    return;
  }
  ESP_LOGE(kTag, "Startup stalled at %s; recovery attempt=%u",
           startup_stage_name(stage), startup_is_recovery ? 1U : 0U);
  if (!startup_is_recovery) {
    // One retry only. Preserve NVS/bonds and the last failing stage across
    // this software reset; a persistent fault must not become a reboot loop.
    startup_previous_stage = static_cast<std::uint32_t>(stage);
    startup_recovery_marker = kStartupRecoveryMagic;
    esp_restart();
  }
  ESP_LOGE(kTag, "Startup recovery failed; collect the serial boot log");
  vTaskDelete(nullptr);
}

moto::ble::AckStatus receive_phone_message(
    const moto::ble::ReassembledMessage& message, void* context) {
  return static_cast<PhoneNavBridge*>(context)->on_message(message);
}

void update_phone_link(bool active, void* context) {
  static_cast<PhoneNavBridge*>(context)->on_link_state(active);
}

void demo_tick_task(void* context) {
  auto* bridge = static_cast<PhoneNavBridge*>(context);
  while (true) {
    const auto now_ms = static_cast<std::uint64_t>(esp_timer_get_time()) /
                        1'000U;
    bridge->update_demo(now_ms);
    // Match the display and route interpolation at 40 Hz. Keeping all three
    // clocks phase-compatible avoids periodic long frame gaps.
    vTaskDelay(pdMS_TO_TICKS(25));
  }
}

void power_button_task(void*) {
  std::uint64_t pressed_since_ms = 0;
  // The AXP2101 needs roughly a one-second press to power the board on, so
  // the task usually starts while the user is still holding PWR. Arm the
  // hold-to-shutdown detector only after the line has been seen low once;
  // otherwise the tail of the power-on press is counted as a new 3-second
  // hold and the freshly booted unit switches itself off.
  bool released_once = false;
  while (true) {
    const std::uint64_t now_ms =
        static_cast<std::uint64_t>(esp_timer_get_time()) / 1'000U;
    if (!board_port_power_button_pressed()) {
      if (!released_once) {
        released_once = true;
        ESP_LOGI(kTag, "PWR ready: button released, hold detection armed");
      }
      if (pressed_since_ms != 0 &&
          moto::esp32::is_settings_short_press(now_ms - pressed_since_ms) &&
          board_port_lock(100)) {
        device_settings_toggle();
        board_port_unlock();
      }
      pressed_since_ms = 0;
      vTaskDelay(pdMS_TO_TICKS(20));
      continue;
    }
    if (!released_once) {
      // Startup press still in progress; do not start the hold timer.
      vTaskDelay(pdMS_TO_TICKS(20));
      continue;
    }
    if (pressed_since_ms == 0) {
      pressed_since_ms = now_ms;
      ESP_LOGI(kTag, "PWR press started");
    } else if (now_ms - pressed_since_ms >= kPowerHoldMs) {
      ESP_LOGI(kTag, "PWR held for 3 seconds; requesting shutdown");
      if (board_port_lock(UINT32_MAX)) {
        device_settings_close();
        moto_nav_ui_show_power_off_screen();
        board_port_unlock();
      }
      vTaskDelay(pdMS_TO_TICKS(300));
      const esp_err_t result = board_port_power_off();
      if (result != ESP_OK) {
        ESP_LOGE(kTag, "AXP2101 software power-off failed: %s",
                 esp_err_to_name(result));
      }

      // AXP2101 should remove the switched rails here. If this particular
      // board remains alive while USB is attached, blank the panel and enter
      // deep sleep after key release. GPIO3 high wakes it on the next press.
      vTaskDelay(pdMS_TO_TICKS(500));
      while (board_port_power_button_pressed()) {
        vTaskDelay(pdMS_TO_TICKS(20));
      }
      ESP_ERROR_CHECK(esp_sleep_enable_ext1_wakeup_io(
          1ULL << 3, ESP_EXT1_WAKEUP_ANY_HIGH));
      esp_deep_sleep_start();
    }
    vTaskDelay(pdMS_TO_TICKS(20));
  }
}
} // namespace

extern "C" void app_main(void) {
  static_assert(MOTO_DISPLAY_WIDTH == MOTO_UI_CANVAS_WIDTH &&
                    MOTO_DISPLAY_HEIGHT == MOTO_UI_CANVAS_HEIGHT,
                "The board and shared UI canvas must have one resolution");
  static_assert(LV_COLOR_DEPTH == MOTO_DISPLAY_BITS_PER_PIXEL,
                "Firmware and Web must both build the shared UI as RGB565");

  ESP_LOGI(kTag, "starting %dx%d RGB565 firmware target",
           MOTO_DISPLAY_WIDTH, MOTO_DISPLAY_HEIGHT);
  startup_is_recovery = startup_recovery_marker == kStartupRecoveryMagic &&
                        esp_reset_reason() == ESP_RST_SW;
  if (startup_is_recovery) {
    ESP_LOGW(kTag, "Recovering startup stalled at %s",
             startup_stage_name(static_cast<StartupStage>(startup_previous_stage)));
  } else {
    startup_recovery_marker = 0;
  }
  ESP_LOGI(kTag, "reset reason=%d", static_cast<int>(esp_reset_reason()));
  // Independent from the LVGL lock/worker, so a missed DMA completion cannot
  // leave app_main waiting forever after the logo has finished.
  if (xTaskCreatePinnedToCore(startup_guard_task, "moto_startup", 4096,
                             nullptr, 2, nullptr, 1) != pdPASS) {
    ESP_LOGW(kTag, "Startup guard task allocation failed");
  }

  const esp_err_t init_result = board_port_init();
  if (init_result != ESP_OK) {
    ESP_LOGE(kTag, "board initialization stopped before shared UI startup: %s",
             esp_err_to_name(init_result));
    vTaskDelete(nullptr);
    return;
  }

  lv_display_t *const display = board_port_get_display();
  if (display == nullptr) {
    ESP_LOGE(kTag, "board port returned no LVGL display");
    vTaskDelete(nullptr);
    return;
  }

  device_settings_load_preferences();

  if (lv_display_get_horizontal_resolution(display) != MOTO_DISPLAY_WIDTH ||
      lv_display_get_vertical_resolution(display) != MOTO_DISPLAY_HEIGHT ||
      lv_display_get_color_format(display) != LV_COLOR_FORMAT_RGB565) {
    ESP_LOGE(kTag, "board display violates the shared RGB565 portability "
                   "contract");
    vTaskDelete(nullptr);
    return;
  }

  startup_stage.store(StartupStage::BootFrame, std::memory_order_release);
  if (!board_port_lock(3'000)) {
    ESP_LOGE(kTag, "could not acquire LVGL lock");
    vTaskDelete(nullptr);
    return;
  }

  moto_nav_ui_show_boot_screen();
  // Commit the deliberately black first animation frame while the physical
  // panel is still hidden, then reveal it.  This removes the white frame that
  // used to leak from LVGL's default startup screen.
  lv_refr_now(display);
  const esp_err_t reveal_result = board_port_reveal_display();
  if (reveal_result != ESP_OK) {
    ESP_LOGE(kTag, "could not reveal boot animation: %s",
             esp_err_to_name(reveal_result));
  }
  board_port_unlock();

  // Give the display worker enough time to commit the monochrome power-on
  // frame before constructing the full production UI.
  vTaskDelay(pdMS_TO_TICKS(1'250));

  startup_stage.store(StartupStage::MainLock, std::memory_order_release);
  if (!board_port_lock(3'000)) {
    ESP_LOGE(kTag, "could not reacquire LVGL lock after boot screen");
    vTaskDelete(nullptr);
    return;
  }

  startup_stage.store(StartupStage::MainConstruction, std::memory_order_release);
  ESP_LOGI(kTag, "constructing main UI; main stack headroom=%u bytes",
           static_cast<unsigned>(uxTaskGetStackHighWaterMark(nullptr)));
  moto_nav_ui_create();
  static moto::nav::NavPresenter presenter;
  static PhoneNavBridge phone_bridge(presenter);
  static BleNavTransport transport;
  // NavSnapshot contains the complete bounded roads/buildings window and is
  // several kilobytes.  A temporary here inflates app_main's stack frame for
  // the entire display/BSP startup call chain, which can trip the FreeRTOS
  // main-task canary before this line is even reached.  Keep the immutable
  // initial state in static storage just like the bridge's retained snapshots.
  static const moto::nav::NavSnapshot initial_snapshot{};
  presenter.update(initial_snapshot);
  presenter.apply_to_lvgl();
  moto_nav_ui_set_music_page_enabled(0);
  phone_bridge.install_ui_callbacks();
  device_settings_create();
  startup_stage.store(StartupStage::FirstMainFrame, std::memory_order_release);
  // Finish the handoff before background services allocate memory or begin
  // producing navigation updates. Do not rely on a future timer to redraw.
  lv_obj_invalidate(lv_screen_active());
  lv_refr_now(display);
  ESP_LOGI(kTag, "first main UI frame submitted; main stack headroom=%u bytes",
           static_cast<unsigned>(uxTaskGetStackHighWaterMark(nullptr)));
  startup_stage.store(StartupStage::Ready, std::memory_order_release);
  board_port_unlock();
  device_settings_start_monitor();

  if (!phone_bridge.start_renderer()) {
    ESP_LOGE(kTag, "UI renderer startup failed; BLE was not started");
    vTaskDelete(nullptr);
    return;
  }

  phone_bridge.set_sender(BleNavTransport::send_from_bridge, &transport);
  transport.set_callbacks(receive_phone_message, update_phone_link,
                          &phone_bridge);
  const esp_err_t ble_result = transport.start();
  if (ble_result != ESP_OK) {
    ESP_LOGE(kTag, "BLE startup failed; display remains in offline mode: %s",
             esp_err_to_name(ble_result));
  }

  // Course and route matching are authoritative on the phone. Do not start
  // the 125 Hz gyro task: device yaw must not rotate the navigation map.

  // Demo generation fills the retained snapshot in place, but geometry and
  // LVGL projection still use deeper C++ call frames than a trivial task.
  if (xTaskCreate(demo_tick_task, "moto_demo", 6'144, &phone_bridge, 2,
                  nullptr) != pdPASS) {
    ESP_LOGW(kTag, "navigation demo task could not start");
  }
  if (xTaskCreate(power_button_task, "moto_power", 3'072, nullptr, 3,
                  nullptr) != pdPASS) {
    ESP_LOGW(kTag, "PWR long-hold task could not start");
  }

  ESP_LOGI(kTag,
           "iPhone travel course -> NavPresenter -> shared LVGL running");
  vTaskDelete(nullptr);
}
