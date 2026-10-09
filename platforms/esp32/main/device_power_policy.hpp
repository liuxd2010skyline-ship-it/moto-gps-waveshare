#pragma once

#include <cstdint>

namespace moto::esp32 {

constexpr std::uint8_t clamp_brightness(int percent) {
  return static_cast<std::uint8_t>(percent < 10 ? 10 : percent > 100 ? 100 : percent);
}

constexpr bool is_settings_short_press(std::uint64_t duration_ms) {
  return duration_ms >= 40 && duration_ms < 1'500;
}

struct BatteryReading {
  bool present = false;
  bool usb_power = false;
  bool charging = false;
  bool percent_valid = false;
  std::uint8_t percent = 0;
};

// AXP2101 status 0x00/0x01 and fuel-gauge percentage 0xA4. These are
// hardware readings, never a linear voltage-to-percentage approximation.
constexpr BatteryReading decode_battery(std::uint8_t status1,
                                       std::uint8_t status2,
                                       std::uint8_t percent) {
  const bool present = (status1 & 0x08U) != 0;
  return {present,
          (status1 & 0x20U) != 0 && (status2 & 0x08U) == 0,
          present && (status2 >> 5U) == 1U,
          present && percent <= 100,
          static_cast<std::uint8_t>(present && percent <= 100 ? percent : 0)};
}

}  // namespace moto::esp32
