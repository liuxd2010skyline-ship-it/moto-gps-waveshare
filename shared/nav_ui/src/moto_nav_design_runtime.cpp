#include "moto_nav_design_runtime.hpp"
#include "moto_map_visual_style.h"
#include "moto_nav_dither_tile.hpp"
#include <algorithm>
#include <cmath>

namespace moto::design {
namespace {
float smooth(float x) { x=std::clamp(x,0.F,1.F); return x*x*(3-2*x); }
std::uint32_t random(Ambient& a) { a.rng ^= a.rng<<13; a.rng ^= a.rng>>17; a.rng ^= a.rng<<5; return a.rng; }
float range(Ambient& a,float lo,float hi) { return lo+(hi-lo)*(random(a)&0xFFFFFF)/16777215.F; }
float channel(std::uint32_t c,int shift) { return static_cast<float>((c>>shift)&255); }
void mix(float& r,float& g,float& b,std::uint32_t c,float opacity) {
    opacity=std::clamp(opacity,0.F,1.F);
    r+=(channel(c,16)-r)*opacity; g+=(channel(c,8)-g)*opacity; b+=(channel(c,0)-b)*opacity;
}
void birth(Ambient& a,float when) {
    for(auto& p:a.patches) if(!p.live) {
        float cx=0,cy=0; bool spaced=false;
        for(int attempt=0;attempt<12;++attempt) {
            const int region=static_cast<int>(random(a)%3);
            cx=range(a,region==1?225.F:90.F,region==1?330.F:215.F);
            cy=range(a,region==2?160.F:70.F,region==2?245.F:165.F);
            spaced=true;
            for(const auto& q:a.patches) if(q.live && std::hypot(q.cx-cx,q.cy-cy)<68) spaced=false;
            if(spaced) break;
        }
        if(!spaced) return;
        p={}; p.live=true; p.kind=static_cast<std::uint8_t>(random(a)%3);
        p.born=when; p.life=range(a,14,26); p.fade_in=range(a,2.8F,4.2F); p.fade_out=range(a,3.8F,5.8F);
        p.cx=cx; p.cy=cy; p.rx=range(a,96,145); p.ry=range(a,76,128);
        p.angle=range(a,-.48F,.48F); p.ax=range(a,12,20); p.ay=range(a,8,14);
        p.tx=range(a,5,9); p.ty=range(a,7,12); p.phase=range(a,0,6.283185F);
        p.inverse_rx=1/p.rx; p.inverse_ry=1/p.ry;
        p.cosine=std::cos(p.angle); p.sine=std::sin(p.angle);
        return;
    }
}
void sample(Ambient& a) {
    float total=0;
    for(auto& p:a.patches) if(p.live) {
        const float age=a.time-p.born;
        if(age>=p.life) { p.live=false; p.opacity=0; continue; }
        p.opacity=smooth(age/p.fade_in)*smooth((p.life-age)/p.fade_out);
        const float travel=a.settings.travel/65.F;
        p.dx=travel*(p.ax*std::sin(age/p.tx+p.phase)+4*std::sin(age/17));
        p.dy=travel*p.ay*std::sin(age/p.ty+.7F*p.phase);
        total+=p.opacity;
    }
    if(total>1.9F) for(auto& p:a.patches) p.opacity*=1.9F/total;
}
} // namespace

Decision decide(const moto_ui_state_t& x,moto_ui_phone_connection_t phone) noexcept {
    Decision d;
    if(phone!=MOTO_UI_PHONE_ONLINE) {
        if(phone==MOTO_UI_PHONE_CONNECTING) { d.scene=Scene::PhoneConnecting; d.title="CONNECTING"; d.subtitle="KEEP YOUR PHONE NEARBY"; }
        return d;
    }
    if(x.mode==MOTO_UI_ARRIVED) { d.scene=Scene::Arrived; d.title="YOU HAVE ARRIVED"; d.subtitle="RIDE COMPLETE"; return d; }
    if(!x.has_destination) { d.scene=Scene::Ready; d.title="READY TO RIDE"; d.subtitle="CHOOSE A DESTINATION ON YOUR PHONE"; return d; }
    if(x.off_route || x.route_request_in_flight || x.mode==MOTO_UI_REROUTING) {
        d.scene=(!x.online && x.off_route)?Scene::OfflineOffRoute:Scene::Rerouting;
        d.title=d.scene==Scene::OfflineOffRoute?"OFFLINE / OFF ROUTE":"REROUTING";
        d.subtitle=d.scene==Scene::OfflineOffRoute?"RECONNECT TO GET A NEW ROUTE":"WAITING FOR A NEW ROUTE"; return d;
    }
    if(!x.has_usable_fix || x.gnss_stale) { d.scene=Scene::GpsLost; d.title="GPS SIGNAL LOST"; d.subtitle="WAITING FOR A FRESH POSITION"; return d; }
    if(!x.has_next_maneuver || (x.mode!=MOTO_UI_NAVIGATING && x.mode!=MOTO_UI_OFFLINE)) {
        d.scene=Scene::WaitingRoute; d.title="WAITING FOR ROUTE"; d.subtitle="WAITING FOR VALID GUIDANCE"; return d;
    }
    d.guidance=true; d.title=""; d.subtitle="";
    d.geometry=x.geometry_matched && x.route_point_count>=2 && x.route_point_count<=MOTO_UI_ROUTE_POINT_CAPACITY;
    if(d.geometry) {
        const auto p=x.route_points[0];
        d.geometry=std::hypot(static_cast<float>(p.x-207),static_cast<float>(p.y-300))<=8.F;
    }
    d.limit=x.speed_limit_validated && x.speed_limit_kph>0 && x.speed_limit_kph<=255;
    if(!d.geometry) { d.scene=Scene::InstructionOnly; d.title="MAP PREVIEW UNAVAILABLE"; d.limit=false; return d; }
    d.motion=true;
    d.scene=x.building_footprint_count?Scene::Rich:x.road_polyline_count?Scene::RoadsOnly:Scene::RouteOnly;
    return d;
}

const char *maneuver_label(moto_maneuver_t m) noexcept {
    switch(m) {
        case MOTO_MANEUVER_LEFT:return "TURN LEFT";
        case MOTO_MANEUVER_RIGHT:return "TURN RIGHT";
        case MOTO_MANEUVER_SLIGHT_LEFT:return "KEEP LEFT";
        case MOTO_MANEUVER_SLIGHT_RIGHT:return "KEEP RIGHT";
        case MOTO_MANEUVER_UTURN:return "MAKE A U-TURN";
        case MOTO_MANEUVER_ROUNDABOUT:return "ROUNDABOUT";
        case MOTO_MANEUVER_ARRIVE:return "YOU HAVE ARRIVED";
        default:return "CONTINUE STRAIGHT";
    }
}
float fade_at(float y) noexcept {
    const float t=std::clamp((y-294.F)/56.F,0.F,1.F);
    return t<.42F ? t*(.45F/.42F) : .45F+(t-.42F)*(.55F/.58F);
}
std::uint32_t building_color(std::uint32_t key,bool landmark) noexcept {
    if(landmark) return MOTO_MAP_BUILDING_LANDMARK;
    key ^= key>>16; key*=0x7FEB352DU; key^=key>>15;
    const int delta=static_cast<int>(key%9)-4;
    const int r=48+delta,g=51+delta,b=53+delta;
    return static_cast<std::uint32_t>((r<<16)|(g<<8)|b);
}
std::uint32_t road_color(std::uint32_t base,float y) noexcept {
    // A six-level change across the map, never an embossed/highlighted road.
    const int delta=static_cast<int>(std::lround(3-6*std::clamp(y/350.F,0.F,1.F)));
    const int r=std::clamp(static_cast<int>(channel(base,16))+delta,0,255);
    const int g=std::clamp(static_cast<int>(channel(base,8))+delta,0,255);
    const int b=std::clamp(static_cast<int>(channel(base,0))+delta,0,255);
    return static_cast<std::uint32_t>((r<<16)|(g<<8)|b);
}
std::uint16_t rgb565(float r,float g,float b,int x,int y) noexcept {
    // A fixed blue-noise tile avoids the old visible 8x8 ordered grid. It
    // preserves the mean design color and never creates temporal shimmer.
    const float threshold=(kDitherTile[((y&63)<<6)|(x&63)]+.5F)/256.F;
    const auto q=[threshold](float v,int n){return std::clamp(static_cast<int>(std::floor(std::clamp(v,0.F,255.F)*n/255.F+threshold)),0,n);};
    return static_cast<std::uint16_t>((q(r,31)<<11)|(q(g,63)<<5)|q(b,31));
}
void initialize(Ambient& a,std::uint32_t seed) noexcept {
    a=Ambient{}; a.rng=seed?seed:0x6D6F746F;
    // Start in a mature but subdued state, instead of an apparently inert first 10s.
    while(a.next_birth<a.time) { birth(a,a.next_birth); a.next_birth+=range(a,4.5F,8.5F); sample(a); }
    sample(a);
}
void configure(Ambient& a,const moto_ui_appearance_t& s) noexcept {
    a.settings={static_cast<std::uint8_t>(std::min<int>(100,s.intensity)),static_cast<std::uint8_t>(std::min<int>(100,s.speed)),static_cast<std::uint8_t>(std::min<int>(100,s.travel)),static_cast<std::uint8_t>(s.reduce_motion!=0)};
    sample(a);
}
bool tick(Ambient& a,std::uint32_t now,bool active) noexcept {
    const auto elapsed=a.initialized ? static_cast<std::uint32_t>(now-a.last_tick) : 0;
    a.last_tick=now; a.initialized=true;
    if(!active || a.settings.reduce_motion || !a.settings.speed) { a.was_active=false; return false; }
    // No catch-up after screen sleep or a long render stall.
    const float dt=std::min(elapsed/1000.F,1.F)*(.3F+.014F*a.settings.speed);
    a.time+=dt; a.event_age+=dt; a.was_active=true;
    for(auto& p:a.patches) if(p.live && a.time-p.born>=p.life) p.live=false;
    if(a.time>=a.next_birth) { birth(a,a.time); a.next_birth=a.time+range(a,4.5F,8.5F); }
    sample(a); return dt>0;
}
void navigation_event(Ambient& a,const moto_ui_state_t& x,bool valid) noexcept {
    if(!valid) { a.event_age=10; return; }
    const bool changed=a.route!=x.route_identity || a.generation!=x.route_generation || a.action!=x.maneuver_identity;
    if(changed) { a.route=x.route_identity;a.generation=x.route_generation;a.action=x.maneuver_identity;a.distance_band=0;a.event_age=0; }
    const std::uint8_t band=x.distance_to_maneuver_m<=30?3:x.distance_to_maneuver_m<=80?2:x.distance_to_maneuver_m<=200?1:0;
    if(band>a.distance_band) { a.distance_band=band;a.event_age=0; }
}
MaterialColor material_color(const Ambient& a,int x,int y) noexcept {
    float r=channel(MOTO_MAP_BLACK,16),g=channel(MOTO_MAP_BLACK,8),b=channel(MOTO_MAP_BLACK,0);
    const float strength=a.settings.intensity/62.F;
    const float bx=(x-191.F)/354.F,by=(y-130.F)/354.F;
    const float base=std::clamp(1-std::sqrt(bx*bx+by*by),0.F,1.F);
    mix(r,g,b,MOTO_MAP_AMBIENT_BASE,.7F*base*strength);
    const std::uint32_t colors[]={MOTO_MAP_AMBIENT_A,MOTO_MAP_AMBIENT_B,MOTO_MAP_AMBIENT_C};
    const float alphas[]={.29F,.26F,.21F};
    const float boost=a.event_age<1.1F?.03F*(1-a.event_age/1.1F)*(1-a.event_age/1.1F):0;
    for(const auto& p:a.patches) if(p.live && p.opacity>0) {
        const float dx=x-p.cx-p.dx,dy=y-p.cy-p.dy;
        const float u=(dx*p.cosine+dy*p.sine)*p.inverse_rx;
        const float v=(-dx*p.sine+dy*p.cosine)*p.inverse_ry;
        const float q=u*u+v*v;
        const float q2=(u+.32F)*(u+.32F)/(.46F*.46F)+(v-.15F)*(v-.15F)/(.8F*.8F);
        // Smooth compact-support lobes; no concentric step boundaries.
        const float f=smooth(1-std::min(q,1.F));
        const float f2=smooth(1-std::min(q2,1.F));
        mix(r,g,b,colors[p.kind],(alphas[p.kind]+boost)*p.opacity*strength*std::min(1.F,f+.45F*f2));
    }
    return {r,g,b};
}
std::uint16_t finish_material(MaterialColor c,int x,int y) noexcept {
    const float dx=x-233.F,dy=y-233.F;
    const float distance2=dx*dx+dy*dy;
    if(distance2>=231.F*231.F) return rgb565(channel(MOTO_MAP_BLACK,16),channel(MOTO_MAP_BLACK,8),channel(MOTO_MAP_BLACK,0),x,y);
    mix(c.r,c.g,c.b,MOTO_MAP_BLACK,fade_at(static_cast<float>(y)));
    if(distance2>229.F*229.F) mix(c.r,c.g,c.b,MOTO_MAP_BLACK,smooth((std::sqrt(distance2)-229)/2));
    return rgb565(c.r,c.g,c.b,x,y);
}
std::uint16_t material_pixel(const Ambient& a,int x,int y) noexcept {
    return finish_material(material_color(a,x,y),x,y);
}
void render_material(const Ambient& a,std::uint16_t* pixels,MaterialScratch& scratch) noexcept {
    if(!pixels) return;
    for(int column=0;column<118;++column) scratch.rows[0][column]=material_color(a,column*4,0);
    for(int band=0;band<350;band+=4) {
        const int upper=(band/4)&1, lower=1-upper;
        for(int column=0;column<118;++column) scratch.rows[lower][column]=material_color(a,column*4,band+4);
        for(int row=0;row<4 && band+row<350;++row) {
            const float fy=row*.25F;
            for(int x=0;x<466;++x) {
                const int column=x/4;const float fx=(x&3)*.25F;
                const auto& c00=scratch.rows[upper][column];const auto& c10=scratch.rows[upper][column+1];
                const auto& c01=scratch.rows[lower][column];const auto& c11=scratch.rows[lower][column+1];
                const auto blend=[fx,fy](float a,float b,float c,float d) {return (a+(b-a)*fx)*(1-fy)+(c+(d-c)*fx)*fy;};
                const MaterialColor color{blend(c00.r,c10.r,c01.r,c11.r),blend(c00.g,c10.g,c01.g,c11.g),blend(c00.b,c10.b,c01.b,c11.b)};
                pixels[(band+row)*466+x]=finish_material(color,x,band+row);
            }
        }
    }
}
} // namespace moto::design
