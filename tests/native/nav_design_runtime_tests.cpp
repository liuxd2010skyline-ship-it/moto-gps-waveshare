#include "moto_nav_design_runtime.hpp"
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <set>

namespace {
int failures=0;
#define CHECK(c) do { if(!(c)) {std::cerr<<__LINE__<<": " #c "\n";++failures;} } while(false)
moto_ui_state_t ready() {
    moto_ui_state_t x{};x.mode=MOTO_UI_NAVIGATING;x.has_destination=1;
    x.has_usable_fix=1;x.has_next_maneuver=1;x.geometry_matched=1;x.online=1;
    x.route_point_count=3;x.route_points[0]={207,300};x.route_points[1]={207,180};
    x.route_points[2]={300,110};x.distance_to_maneuver_m=300;
    x.route_identity=6;x.route_generation=1;x.maneuver_identity=77;return x;
}
void scenes() {
    using namespace moto::design;
    auto x=ready(); auto d=decide(x,MOTO_UI_PHONE_OFFLINE);
    CHECK(d.scene==Scene::PhoneOffline && !d.guidance && !d.geometry);
    CHECK(decide(x,MOTO_UI_PHONE_CONNECTING).scene==Scene::PhoneConnecting);
    d=decide(x,MOTO_UI_PHONE_ONLINE);CHECK(d.scene==Scene::RouteOnly && d.geometry && d.guidance);
    x.road_polyline_count=1;CHECK(decide(x,MOTO_UI_PHONE_ONLINE).scene==Scene::RoadsOnly);
    x.building_footprint_count=1;CHECK(decide(x,MOTO_UI_PHONE_ONLINE).scene==Scene::Rich);
    x.online=0;x.mode=MOTO_UI_OFFLINE;CHECK(decide(x,MOTO_UI_PHONE_ONLINE).guidance);
    x.off_route=1;d=decide(x,MOTO_UI_PHONE_ONLINE);
    CHECK(d.scene==Scene::OfflineOffRoute && !d.guidance && !d.motion);
    x.online=1;CHECK(decide(x,MOTO_UI_PHONE_ONLINE).scene==Scene::Rerouting);
    x=ready();x.gnss_stale=1;d=decide(x,MOTO_UI_PHONE_ONLINE);
    CHECK(d.scene==Scene::GpsLost && !d.geometry && !d.limit);
    x=ready();x.has_next_maneuver=0;CHECK(decide(x,MOTO_UI_PHONE_ONLINE).scene==Scene::WaitingRoute);
    x=ready();x.geometry_matched=0;d=decide(x,MOTO_UI_PHONE_ONLINE);
    CHECK(d.scene==Scene::InstructionOnly && d.guidance && !d.geometry && !d.motion);
    x=ready();x.route_points[0]={100,100};CHECK(!decide(x,MOTO_UI_PHONE_ONLINE).geometry);
    x=ready();x.has_destination=0;CHECK(decide(x,MOTO_UI_PHONE_ONLINE).scene==Scene::Ready);
    x=ready();x.mode=MOTO_UI_ARRIVED;d=decide(x,MOTO_UI_PHONE_ONLINE);
    CHECK(d.scene==Scene::Arrived && !d.guidance);
    x=ready();x.speed_limit_kph=60;CHECK(!decide(x,MOTO_UI_PHONE_ONLINE).limit);
    x.speed_limit_validated=1;CHECK(decide(x,MOTO_UI_PHONE_ONLINE).limit);
    x.speed_limit_kph=0;CHECK(!decide(x,MOTO_UI_PHONE_ONLINE).limit);
}
void motion() {
    using namespace moto::design;
    Ambient a;initialize(a,12345);tick(a,1000,true);
    const auto before=material_pixel(a,177,111);
    const float initial=a.time;
    std::set<int> counts;bool changed=false;
    for(unsigned ms=1500;ms<500000;ms+=500) {
        CHECK(tick(a,ms,true));float sum=0;int count=0;
        for(const auto& p:a.patches) if(p.live) {++count;sum+=p.opacity;CHECK(std::isfinite(p.dx)&&std::isfinite(p.dy));}
        CHECK(count<=4 && sum<=1.901F);counts.insert(count);
        changed |= material_pixel(a,177,111)!=before;
    }
    CHECK(changed && a.time>initial && counts.size()>1);
    const auto pixel=material_pixel(a,177,111);const auto time=a.time;
    CHECK(!tick(a,500000,false));CHECK(a.time==time && material_pixel(a,177,111)==pixel);
    configure(a,{62,75,85,1});CHECK(!tick(a,500500,true));CHECK(a.time==time);
    configure(a,{62,0,85,0});CHECK(!tick(a,501000,true));CHECK(a.time==time);
    configure(a,{255,255,255,255});CHECK(a.settings.intensity==100 && a.settings.reduce_motion==1);
    auto x=ready();navigation_event(a,x,true);CHECK(a.event_age==0);
    a.event_age=8;x.distance_to_maneuver_m=190;navigation_event(a,x,true);CHECK(a.event_age==0);
    a.event_age=8;x.distance_to_maneuver_m=210;navigation_event(a,x,true);CHECK(a.event_age==8);
    x.distance_to_maneuver_m=195;navigation_event(a,x,true);CHECK(a.event_age==8);
    x.distance_to_maneuver_m=79;navigation_event(a,x,true);CHECK(a.event_age==0);
    x.route_generation++;a.event_age=8;navigation_event(a,x,true);CHECK(a.event_age==0);
}
void color() {
    using namespace moto::design;
    CHECK(fade_at(294)==0 && fade_at(350)==1);
    float last=0;for(int y=294;y<=350;++y) {CHECK(fade_at(y)>=last);last=fade_at(y);}
    CHECK(building_color(42,false)==building_color(42,false));
    CHECK(road_color(0x62696D,0)!=road_color(0x62696D,349));
    // The spatial pattern is stationary and unbiased over a complete 8x8 tile.
    double mean=0;
    for(int y=0;y<8;++y)for(int x=0;x<8;++x) {
        const auto p=rgb565(30,35,40,x,y);
        CHECK(p==rgb565(30,35,40,x+8,y+8));mean+=((p>>11)&31)*255.0/31;
    }
    CHECK(std::abs(mean/64-30)<0.2);
}
}
int main() {scenes();motion();color();return failures?EXIT_FAILURE:EXIT_SUCCESS;}
