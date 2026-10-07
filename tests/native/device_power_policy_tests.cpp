#include "device_power_policy.hpp"

#include <cstdlib>
#include <iostream>

namespace {
int failures = 0;
#define CHECK(condition) do { \
  if (!(condition)) { \
    std::cerr << __LINE__ << ": " #condition " failed\n"; \
    ++failures; \
  } \
} while (false)

void test_brightness_keeps_the_screen_recoverable() {
  using moto::esp32::clamp_brightness;
  CHECK(clamp_brightness(-100) == 10);
  CHECK(clamp_brightness(0) == 10);
  CHECK(clamp_brightness(9) == 10);
  CHECK(clamp_brightness(10) == 10);
  CHECK(clamp_brightness(55) == 55);
  CHECK(clamp_brightness(100) == 100);
  CHECK(clamp_brightness(255) == 100);
}

void test_a_power_on_or_shutdown_hold_is_not_a_settings_tap() {
  using moto::esp32::is_settings_short_press;
  CHECK(!is_settings_short_press(0));
  CHECK(!is_settings_short_press(39));
  CHECK(is_settings_short_press(40));
  CHECK(is_settings_short_press(500));
  CHECK(is_settings_short_press(1499));
  CHECK(!is_settings_short_press(1500));
  CHECK(!is_settings_short_press(3000));
  CHECK(!is_settings_short_press(4000));
}

void test_battery_percentage_and_charge_state_come_from_the_pmic() {
  using moto::esp32::decode_battery;
  const auto charging = decode_battery(0x28, 0x20, 73);
  CHECK(charging.present && charging.usb_power && charging.charging);
  CHECK(charging.percent_valid && charging.percent == 73);

  const auto discharging = decode_battery(0x08, 0x40, 52);
  CHECK(discharging.present && !discharging.usb_power && !discharging.charging);
  CHECK(discharging.percent_valid && discharging.percent == 52);

  const auto full_on_usb = decode_battery(0x28, 0, 100);
  CHECK(full_on_usb.usb_power && !full_on_usb.charging);
  CHECK(full_on_usb.percent_valid && full_on_usb.percent == 100);
  CHECK(decode_battery(0x08, 0, 0).percent_valid);

  const auto usb_disabled = decode_battery(0x28, 0x08, 50);
  CHECK(!usb_disabled.usb_power);
}

void test_missing_or_invalid_gauge_data_is_not_a_fake_percentage() {
  using moto::esp32::decode_battery;
  for (const auto raw : {0, 50, 100, 255}) {
    const auto absent = decode_battery(0x20, 0x20, raw);
    CHECK(!absent.present && !absent.charging && !absent.percent_valid);
    CHECK(absent.usb_power && absent.percent == 0);
  }
  for (const auto raw : {101, 127, 255}) {
    const auto invalid = decode_battery(0x08, 0, raw);
    CHECK(invalid.present && !invalid.percent_valid && invalid.percent == 0);
  }
}
}  // namespace

int main() {
  test_brightness_keeps_the_screen_recoverable();
  test_a_power_on_or_shutdown_hold_is_not_a_settings_tap();
  test_battery_percentage_and_charge_state_come_from_the_pmic();
  test_missing_or_invalid_gauge_data_is_not_a_fake_percentage();
  if (failures) return EXIT_FAILURE;
  std::cout << "Battery, brightness and PWR gesture checks passed\n";
  return EXIT_SUCCESS;
}
