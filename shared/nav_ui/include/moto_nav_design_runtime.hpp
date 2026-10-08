#pragma once
#include "moto_nav_ui.h"
#include <cstdint>

namespace moto::design {
enum class Scene : std::uint8_t {
    PhoneOffline, PhoneConnecting, Arrived, Ready, Rerouting, OfflineOffRoute,
    GpsLost, WaitingRoute, InstructionOnly, RouteOnly, RoadsOnly, Rich
};
struct Decision {
    Scene scene = Scene::PhoneOffline;
    bool guidance = false, geometry = false, limit = false, motion = false;
    const char *title = "PHONE DISCONNECTED";
    const char *subtitle = "OPEN MOTO GPS ON YOUR PHONE";
};
Decision decide(const moto_ui_state_t&, moto_ui_phone_connection_t) noexcept;
const char *maneuver_label(moto_maneuver_t) noexcept;
float fade_at(float y) noexcept;
std::uint32_t building_color(std::uint32_t key, bool landmark) noexcept;
std::uint32_t road_color(std::uint32_t base, float y) noexcept;
std::uint16_t rgb565(float r, float g, float b, int x, int y) noexcept;

struct Patch {
    bool live = false;
    std::uint8_t kind = 0;
    float born = 0, life = 0, fade_in = 0, fade_out = 0;
    float cx = 0, cy = 0, rx = 0, ry = 0, angle = 0;
    float ax = 0, ay = 0, tx = 1, ty = 1, phase = 0;
    float dx = 0, dy = 0, opacity = 0;
    float inverse_rx = 0, inverse_ry = 0, cosine = 1, sine = 0;
};
// Four retained records, no history allocation, no per-frame random noise.
struct Ambient {
    Patch patches[4]{};
    moto_ui_appearance_t settings{62,75,85,0};
    std::uint32_t rng = 0x6D6F746F, last_tick = 0;
    std::uint32_t route = 0, generation = 0, action = 0;
    std::uint8_t distance_band = 0;
    float time = 18, next_birth = 0, event_age = 10;
    bool initialized = false, was_active = false;
};
void initialize(Ambient&, std::uint32_t seed) noexcept;
void configure(Ambient&, const moto_ui_appearance_t&) noexcept;
bool tick(Ambient&, std::uint32_t now_ms, bool active) noexcept;
void navigation_event(Ambient&, const moto_ui_state_t&, bool valid) noexcept;
std::uint16_t material_pixel(const Ambient&, int x, int y) noexcept;
struct MaterialColor { float r=0, g=0, b=0; };
struct MaterialScratch { MaterialColor rows[2][118]{}; };
// Fixed four-pixel sampling pitch; interpolate before stationary quantization.
void render_material(const Ambient&, std::uint16_t *pixels, MaterialScratch&) noexcept;
} // namespace moto::design
