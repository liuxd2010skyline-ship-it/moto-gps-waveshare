# Waveshare 1.75C battery and brightness settings

Short-press the case **PWR** button to open **SETTINGS**. Short-press again,
or touch **BACK**, to return to navigation. Holding PWR for three seconds
retains the existing shutdown action; the power-on hold is ignored.

- **BATTERY** displays the AXP2101 fuel-gauge percentage and charging/USB state,
  refreshed every five seconds. No battery, an invalid percentage, or an I2C
  failure is shown as `--` with the corresponding status, never a fabricated
  battery percentage.
- **BRIGHTNESS** is adjustable from **10% to 100%** with the touch slider or
  the **− / +** buttons. The AMOLED changes immediately. Slider release or a
  button tap saves the value in NVS; boot restores it before revealing the screen.
- **SAVED** confirms persistence. A failed write shows **SAVE FAILED - TRY AGAIN**.
  The 10% minimum avoids accidentally making the page unusable.

This is a board-only overlay on `lv_layer_top()`. Navigation, BLE snapshots,
route/building rendering and the iPhone UI keep their current implementation.
It does not erase NVS, change battery charging current/voltage, or reset gauge
calibration. Battery detection and fuel-gauge enable bits use read-modify-write.

## Hardware references

- [AXP2101 datasheet](https://files.waveshare.com/wiki/common/X-power-AXP2101_SWcharge_V1.0.pdf):
  status registers 0x00/0x01; gauge percentage 0xA4; detection enable 0x68 bit 0;
  gauge enable 0x18 bit 3. Battery accuracy follows the PMIC's stored model and learning.
- [Espressif CO5300 API](https://github.com/espressif/esp-iot-solution/blob/2d289eb1f14431e345b345c3fd6fc299a555d770/components/display/lcd/esp_lcd_co5300/include/esp_lcd_co5300.h):
  `esp_lcd_panel_co5300_set_brightness` accepts a 0–100 percentage.

## Physical acceptance after flashing

1. Short-press PWR: settings opens; BACK and PWR both return to navigation.
2. Move the slider and tap −/+; confirm visible brightness changes.
3. Restart and confirm the saved brightness is restored.
4. With the battery connected, confirm a real percentage. Connect/disconnect USB
   and allow up to five seconds for the charging/power status to refresh.
5. Hold PWR for three seconds and confirm the existing shutdown still works.

Compilation and native tests do not replace these physical checks.
