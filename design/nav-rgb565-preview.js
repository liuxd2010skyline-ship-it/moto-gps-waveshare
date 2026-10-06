/* Deterministic RGB565 simulation for the desktop design preview.
 * This is a pixel-level visual check, not the ESP32 display driver.
 */
(function (root) {
  "use strict";

  const bayer8 = Object.freeze([
    0, 48, 12, 60, 3, 51, 15, 63,
    32, 16, 44, 28, 35, 19, 47, 31,
    8, 56, 4, 52, 11, 59, 7, 55,
    40, 24, 36, 20, 43, 27, 39, 23,
    2, 50, 14, 62, 1, 49, 13, 61,
    34, 18, 46, 30, 33, 17, 45, 29,
    10, 58, 6, 54, 9, 57, 5, 53,
    42, 26, 38, 22, 41, 25, 37, 21
  ]);
  function channel(value, levels, threshold) {
    const scaled = value * levels / 255;
    const quantized = Math.max(0, Math.min(levels,
      threshold === null ? Math.round(scaled) : Math.floor(scaled + threshold)));
    return Math.round(quantized * 255 / levels);
  }
  function quantize(imageData, mode) {
    if (mode === "rgb24") return imageData;
    if (mode !== "rgb565-plain" && mode !== "rgb565-dither") {
      throw new Error(`Unknown preview mode: ${mode}`);
    }
    const pixels = imageData.data;
    const width = imageData.width;
    for (let i = 0; i < pixels.length; i += 4) {
      const x = (i / 4) % width;
      const y = Math.floor(i / 4 / width);
      // Keep route, glyphs, labels and real map lines crisp. Only the dark
      // upper material needs ordered dither to interrupt RGB565 banding.
      const materialPixel = y < 350 &&
        Math.max(pixels[i], pixels[i + 1], pixels[i + 2]) < 47;
      const threshold = mode === "rgb565-dither" && materialPixel
        ? (bayer8[(y & 7) * 8 + (x & 7)] + .5) / 64 : null;
      pixels[i] = channel(pixels[i], 31, threshold);
      pixels[i + 1] = channel(pixels[i + 1], 63, threshold);
      pixels[i + 2] = channel(pixels[i + 2], 31, threshold);
    }
    return imageData;
  }
  const api = Object.freeze({ quantize, bayer8 });
  root.NavRGB565Preview = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
