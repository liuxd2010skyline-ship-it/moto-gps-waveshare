# MOTO GPS · V6/B 圆屏代码化设计契约

2026-10-08：本文视觉契约已开始进入实际共享 C++/ESP32 与 iPhone 外观页；本地完整原生构建 11/11 测试通过。实现、18 种情况的真实降级路径、字体与实机验证边界见 [两端实现记录](../docs/V6_FIRMWARE_APP_DELIVERY_2026-10-08.md)。以下日期段保留历史阶段说明。

日期：2026-10-06。状态：**浏览器参考可运行；V6 基础绘制已有固件构建，完整 B 状态与柔光尚未移植到 ESP32**。基准是用户选定的 B「Soft Graphite」质感、原 V6 转向箭头与既有 466 × 466 屏幕比例。目标导航标签为英文。下述「当前数据」以仓库源码为准，不把概念图中的街区当成北京实测数据。逐项完成情况见 [实现与构建审计](NAV_IMPLEMENTATION_AUDIT_2026-10-06.md)。

2026-10-07 工程状态更新：OSM 北京离线包、真实导航本地查询及建筑传输已接入，云端数据与协议测试通过。新固件容量为 48 个建筑外轮廓 / 240 点，旧固件仍按能力协商使用 16 / 128；小 MTU 会进一步减少整栋建筑。详见 [本轮验证与两端更新记录](../docs/OFFLINE_MAP_DELIVERY_2026-10-07.md)。本契约的视觉尺寸、色板与行为保持原定标准；真实数据稀疏或缺失时仍使用相同降级规则。

## 电脑调节预览修订（当前）

入口：[环境光实验台](nav-ambient-motion-demo.html)。新增存在感、速度和幅度三个 0–100 滑杆，电脑预览默认 `62 / 75 / 85`，设置保存在浏览器本地。它们仅影响背景材质；路线、V6 平底转向箭头、位置箭头、粗数字、英文标签、渐隐范围、细边缘和进度弧沿用同一渲染规则。背景先绘制，地物随后叠加，完整与稀疏场景共用同一光场。

可切换仅路线、道路、有限地物和完整视觉目标四个场景。全部几何为合成测试数据；完整视觉目标有 100 个建筑，超过当前 MapScene 的 48 个外轮廓/包上限，表达设计上限而非当前实地能力。不得把这个 fixture 发送到设备冒充地物。

柔光数量不固定，同时最多四组。随机确定出现时刻、位置、寿命和连续漂移参数，每帧不重新抽样。时钟 `rate = speed == 0 ? 0 : 0.3 + 0.014 * speed`，幅度乘 `travel / 65`。新柔光从接近透明缓缓出现，旧柔光缓缓消失；总 opacity ≤1.9，出生中心间距至少 68 px。正常/完整地物场景共用同一光场与时间，地物到达不重置动画。详细参数见第 5 节，旧版固定三组及“9 px / 1.25×”规则已被取代。

统一色板的唯一编辑源是 `shared/nav_ui/assets/nav_design_palette.json`。运行 `node scripts/preview/build_nav_palette.mjs` 同时生成浏览器 `nav-design-palette.js` 和固件 `moto_map_visual_style.h`，`--check` 检查两者是否过期。当前默认显示 24 位设计色，不提供不同色相的方案切换。硬件导航页的底色、路线深衬、建筑暗边、单位、限速牌与进度弧已使用相同 token；其他页面原石墨色独立保留。颜色变更已通过本地原生编译和 9/9 测试，不能据此宣称 ESP32 上的柔光已实现。

色彩评审使用 [1× 16 秒真彩动画 PNG](nav-ambient-lab-1x.png) 和实时 HTML；[GIF](nav-ambient-lab-1x.gif) 只有 256 色，用于便捷观察动作，不用来评判暗部色阶。二者每帧对应 `1/8 s` 的真实时间，循环的是录制片段，算法本身没有 16 秒循环。[融合对照](nav-ambient-lab-fusion-comparison.png) 为原生 466 px 渲染，右侧是合成几何压力样例，不能取代已选 B 原稿的建筑细节。

RGB565 直出/固定 8×8 有序抖动仍可通过测试接口导出，用于判断硬件颜色格式的取舍，不在产品预览中改变色板。实现为 [nav-rgb565-preview.js](nav-rgb565-preview.js)，尚未接入硬件。浏览器真彩、RGB565 量化和 AMOLED 实际光学表现是三个不同验收阶段；软件统一色值不能保证屏幕完全无阶差。

历史视觉修订：用户否决了大面积集中聚光和 A/B/C 三色方案，恢复此前喜欢的深石墨色、不规则多处柔光范围；基底轻微调至 `#263338`，三种同色系软光模板中心 alpha `.29/.26/.21`。当前继续使用这些颜色，但数量与时间按最新随机生命周期运行。旧的加速 GIF、集中聚光及三色截图保留为历史实验，**不是当前设计或颜色标准**。

可执行参考：[nav-code-ready-v1.html](nav-code-ready-v1.html) + [nav-code-ready-v1.js](nav-code-ready-v1.js)。浏览器打开 HTML 后可用 `?scene=route-only`、`short-route`、`roads-only`、`rich-fixture`、`instruction-only`、`gps-lost`、`rerouting`、`phone-offline`、`no-destination` 切换测试数据。`?still=1&t=120` 固定环境光在第 120 秒，`?event=1` 演示一次事件响应，`?reduce-motion=1` 冻结动态。固定渲染图均为**原生 466 × 466 像素**。

## 1. 当前真正可用于实地导航的数据

| 信息 | 当前来源及上限 | 实地使用判断 |
| --- | --- | --- |
| 当前有效定位、航向、精度、失效标志 | `NavSnapshot.has_usable_fix`、`gnss_stale`、`heading_deg`；核心默认超过 5 秒未更新即标记 GNSS stale，精度上限 50 m | 可驱动固定位置车辆箭头，但失效后必须撤下可执行指引 |
| 前向路线 | `route_view_points[24]`；NavCore 从已匹配路线的当前进度开始截取，BLE `RouteGeometry` 要求与路线 token / generation 相符 | **正常情况下可绘制**；只画未驶过的真实点，绝不补路线尾巴 |
| 下一动作与距离 | `has_next_maneuver`、`next_maneuver`、`distance_to_next_maneuver_m` | 与新鲜定位、当前路线状态共同校验后可显示 |
| 周边道路 / 建筑 | 可选 `MapScene`；道路上限 24 条 / 192 点，建筑上限 16 个 / 128 点 | **当前真实北京导航未发送**。iOS `AppModel` 仅在 demo 调用 `surroundingMap.update`，真实流程还使用 `example.invalid` 占位加载器；不能期待 B 图中的密集街区出现 |
| 限速 | `speed_limit_kph`，0 表示未知 | 现字段没有「与当前路段可靠对应」的独立证明；默认隐藏。只有后续验证来源与路段关联后才显示红色限速牌 |
| 连接状态 | BLE `phone_connection` 与互联网 `network` 分开 | 手机断连必须停指导；互联网离线只要缓存路线、定位和引导仍有效，可以继续显示 |

因此**P0 实地默认画面就是「真实路线 + 车辆箭头 + 下一动作/距离」，没有街道、建筑或限速**。现有 `design/v6-concept-b-english-canva.png` 是道路/建筑齐全时的视觉上限，不是本阶段必须伪装出来的常态。

## 2. 统一画布、层级与尺寸

屏幕原生尺寸 `466 × 466`，中心 `(233,233)`，内容裁切半径 `231 px`。同一套坐标贯穿正常、稀疏、失效三类画面，不另起一个低保真页面。下表以**物理像素**标注；量产需用实机拍摄校准 1–2 px 光学误差。

| 层级，自下而上 | 视觉合同 | 当前数据缺失时 |
| --- | --- | --- |
| 基底 | `#050708` 黑底，上半部微弱石墨色环境光；非地理纹理 | 始终保留 |
| 建筑 | 真实封闭轮廓，`#303335`，地标 `#373B3D`，低对比哑光 | 完全不绘制 |
| 道路 | 真正的折线，主路 5.2 px `#62696D`、常规 3.9 px `#42474B`、支路 2.6 px `#2B3033`；可用低幅灰阶过渡 | 完全不绘制；不同真实道路不得强行连接 |
| 路线下衬 | 18 px `#273034`，圆头圆接 | 与路线一同出现/消失 |
| 未来路线 | 12 px `#F3F4EF`，只从匹配当前位置向前；实际折点处最大 18 px 平滑，不越过道路几何 | 无匹配路线则不绘制、不推算终点 |
| 位置箭头 | 车辆轴线 `(207,300)`，白形约 `41 × 43 px`，方向朝上；无光环、无尾巴 | 定位无效则不绘制 |
| 底部遮罩 | 仅 `y=294…350` 的 56 px 渐隐，随后为干净黑底；圆盘边缘仅 1–2 px 暗晕 | 始终保留，不扩大到半屏 |
| 转向与距离 | V6 平底箭头的约 64 px 画板；可视符号约 39–40 px；56 px 粗数字、20 px 单位、12 px 英文动作 | 仅有效引导显示；不放入图标框 |
| 有效限速 | 圆牌直径 56 px，中心 `(350,363)`，仅有经路段验证的数值才出现 | 整枚隐藏，HUD 左右重新居中 |
| 进度弧 | 下缘 2.2 px 暗弧、2.6 px 明弧。已知总长才画明弧 | 无效总长只留暗弧 |

距离排版：**有限速**时 V6 图标画板左上 `(101,342)`、数字左缘约 `174`；**无限速**时图标与数字各右移约 `24 px`，使组合整体以圆盘中轴平衡。数字约 `56 px / 700`，单位 `20 px / 500`，`km` 时数字用最多一位小数；按照实际字体测量值放置单位，不把 `m` 写死在截图坐标。英文标签如 `TURN RIGHT` 在数字下方，字级 `12 px / 650`，约 `1.3 px` 字距。标注只提供语义，不占据路线区域。

字体目标按苹方/SF 的字面比例与粗细设计。iPhone 用系统字体；ESP32 当前有 `moto_font_distance_56`、`lv_font_montserrat_20`、`moto_font_nav_16`。要让实机匹配参考稿，应以**有嵌入许可**的字形资产替换或补齐数字与英文标签；不把 Apple 字体文件直接打包进固件。字形、字距、单位基线要在实屏拍照后调，而不是只在 Windows 浏览器截图上通过。

## 3. 画面选择：安全优先于数据密度

令 `validGuidance = state==Navigating && has_destination && has_usable_fix && !gnss_stale && has_next_maneuver && !off_route && !route_request_in_flight && distance_finite_nonnegative`。有效路线还需 `RouteGeometry` token/generation 匹配、2–24 个有限坐标、首点距离屏幕车辆锚点 ≤8 px。`speedLimitValid` 需要来源与当前路段的独立核验；现版本无法证明，默认 false。

| 优先级 | 条件 | 画面 | 允许显示 |
| --- | --- | --- | --- |
| 1 | BLE 断开/连接中 | `PHONE_OFFLINE` / `PHONE_CONNECTING` | 环境光、连接英文状态；撤下旧路线、动作、米数、限速 |
| 2 | 已到达 | `ARRIVED` | 完成状态；不继续显示下一转向 |
| 3 | 未设置目的地 | `READY` | 简洁待命屏 |
| 4 | 偏航、路线请求中、重算中 | `REROUTING` | 状态屏；最后位置可保留为低对比**历史**层，但不执行指导 |
| 5 | 无有效定位或 GNSS stale | `GPS_LOST` | 状态屏；严禁旧转向和旧距离 |
| 6 | 下一动作/距离不可靠 | `WAITING_ROUTE` | 状态屏 |
| 7 | 动作有效，但匹配的路线几何未到达 | `INSTRUCTION_ONLY` | 底部 V6 动作/距离，地图区显示小字 `MAP PREVIEW UNAVAILABLE`，无路线/车辆箭头 |
| 8 | 匹配路线有效，道路与建筑都缺 | `ROUTE_ONLY` | **底图缺失时的重点画面**：白色真实前向路线、车辆箭头、无框英文 HUD |
| 9 | 有真实道路，无真实建筑 | `ROADS_ONLY` | 在同一版面逐条补上道路 |
| 10 | 两类真实地物均有 | `RICH` | 与 B 稿相同材料、层级；密度只由数据决定 |

该表是唯一的画面选择器，参考实现在 `nav-code-ready-v1.js` 的 `selectScene()`。不要用「道路数量低于 N 就生成建筑」这种补偿规则。稀疏区域也可保持美观：真实路线占据视觉主轴、留白承托对比、HUD 自适应平衡、漫反射提供非地理层次。短路线尤其不能为了填屏而凭空延长。网络离线与 BLE 断开绝不共用一个判断。

固件移植时让**同一份快照一次性得出场景和可见层**，不要先把旧路线画出来、随后只隐藏数字。可直接照此转换为 C++：

```cpp
Scene select_scene(const DisplayInput& x) {
  if (x.phone != PhoneLink::Online) return x.phone == PhoneLink::Connecting
      ? Scene::PhoneConnecting : Scene::PhoneOffline;
  if (x.nav_state == NavState::Arrived) return Scene::Arrived;
  if (!x.has_destination) return Scene::Ready;
  if (x.off_route || x.route_request_in_flight ||
      x.nav_state == NavState::Rerouting) return Scene::Rerouting;
  if (!x.has_usable_fix || x.gnss_stale) return Scene::GpsLost;
  if (!valid_guidance(x)) return Scene::WaitingRoute;
  if (!matched_route_geometry(x)) return Scene::InstructionOnly;
  if (valid_roads(x) && valid_buildings(x)) return Scene::Rich;
  if (valid_roads(x)) return Scene::RoadsOnly;
  return Scene::RouteOnly;
}

void apply_scene(const DisplayDecision& d) {
  // One coherent transition: map, marker, HUD, limit, and status together.
  show_future_route(d.scene == RouteOnly || d.scene == RoadsOnly || d.scene == Rich);
  show_position_marker(future_route_visible() && d.fix_valid);
  show_turn_and_distance(d.guidance_valid &&
      (future_route_visible() || d.scene == InstructionOnly));
  show_speed_limit(turn_and_distance_visible() && d.segment_limit_validated);
  show_status(d.scene);                 // English copy table below
  position_hud_by_measured_text_width();
}
```

`matched_route_geometry()` 接受 BLE bridge 已提交且与当前 `route_id`/`route_generation` 相符的点集，不拿旧路线补洞。`valid_roads()` / `valid_buildings()` 还要核对 `MapScene` 修订与当前会话一致。上面的 `future_route_visible()` 等是说明原子可见性关系的接口名，移植时可用 LVGL `HIDDEN` 标志实现，不要求新增全套页面。

## 4. 路线与相机的可实现规则

1. 保留现有 NavCore 的**前向截取**：`route_view_origin` 等于未驶过路线的起点；NavPresenter 投影后首点落在 `(207,300)`。不恢复旧 55 m lookback；不得在车辆箭头下方露出白色小尾巴。
2. 保留原作者思路的**稳定车头向上街道尺度**：现值为 `0.44 × (466/360) ≈ 0.569 px/m`。不在 100 m/50 m 关口突然跳变缩放。相机和地物共享同一变换。短路线保持真实短路段，辅以排版平衡；不造中间折点或远处道路。
3. 折点圆润化与现有 LVGL 算法一致：入段/出段长度不足 4 px，或 `dot > 0.94` / `dot < -0.8` 时保留顶点；其他拐角的圆角半径为 `min(18 px, 入段/3, 出段/3)`。只做屏幕绘制层平滑，不改变百度路线或导航计算。
4. 路线、道路、建筑在圆盘内裁切；对象出屏则自然消失。首点必须已与路线匹配；几何版本不一致时降为 `INSTRUCTION_ONLY` 或状态屏。
5. 地物按**真实覆盖**绘制。未覆盖处保留深石墨环境光。不得通过镜像、随机网格、重复建筑、推断草地来填满空白。

## 5. 非地理的微漫反射与事件响应

这是解决无地物时单调感的**界面材质层**，位置低于全部地图和文字；完整地物可覆盖在其上。保留原稿的三种低对比不规则软光形体，每组两个相叠椭圆，但同时出现的组数在 0–4 之间变化。它们不是建筑、河道、定位精度或交通状态。`ambientAt()` 对给定 seed、时间和状态输出确定结果，`createAmbientController()` 决定何时推进时间及响应真实指引变化。

| 参数 | P0 默认值 | 验收边界 |
| --- | --- | --- |
| 色相/亮度 | 唯一色板中的深石墨色；基底中心 `#263338`，模板中心 alpha `.29/.26/.21`；强度由滑杆调节 | 不自动改变色相；道路、白线与文字层级固定 |
| 形体与数量 | 每组两个叠合椭圆；最多 4 组；中心间距至少 68 px，总组 opacity ≤1.9 | 有宽范围软过渡与局部中心，无新增巨大聚光斑；不挤成同一中心 |
| 随机出生 | 逻辑时间每 4.5–8.5 s 尝试出生；寿命 14–26 s；达到上限或找不到间距合适的位置则跳过 | 仅出生时抽随机参数，每帧沿连续轨迹走；不是随机闪烁 |
| 出现与消失 | 2.8–4.2 s 渐入、3.8–5.8 s 渐出，使用 `smoothstep` | 新光从透明起，消失前回到透明，不突现突灭 |
| 漂移 | `dx=(travel/65)*(Ax*sin(age/Tx+phase)+4*sin(age/17))`，`dy=(travel/65)*Ay*sin(age/Ty+.7*phase)`；Ax 12–20、Ay 8–14，Tx 5–9、Ty 7–12 | 路线、地图、箭头和 HUD 坐标不跟着移动；寿命有限，不固定重复同一组 |
| 时间与 seed | 实时倍率 `0.3+0.014*speed`；速度 0 完全冻结；每次打开实验台生成新的 seed，固定 seed 可复现验收 | 电脑默认速度 75 时倍率 1.35：出生间隔约 3.3–6.3 s、寿命约 10.4–19.3 s |
| 刷新 | 浏览器参考每 125 ms 更新；ESP32 集成目标 **2 Hz**，优先局部刷新 | 导航渲染优先；若实机掉帧或内存不足，降为 1 Hz 或静止 |
| 事件 | 真实路线版本、下一动作身份改变，或距离首次跨过 `200/80/30 m`，才触发单次 `1.1 s` 二次衰减；最大 opacity 增量 `.03` | 距离每包变化及阈值附近抖动不重复触发；不把静止状态误作导航 |
| 状态/减少动态 | GNSS 失效、重算、手机断连、待命等状态停在稳定底图；启用减少动态时固定第一帧 | 状态与文字独立准确，不能仅靠动画传递信息 |

算法输出可变数量的 `(id,cx,cy,rx,ry,angle,dx,dy,opacity)`。seed 对应的时间表缓存最多 4 个；活跃记录按寿命清理，无限运行不累积全部历史。出生中心分布仍围绕原稿的左上、右上、左中区域，缓慢移位且形体不大幅改变。控制器比较 `route_generation` / `route_id` / `next_maneuver.id`；后者在 `NavCore` 已有，但当前 UI 契约尚未带到显示层。单纯 BLE 距离变化或地图地物到达不重置事件；每动作的最小已跨过距离档位防止抖动重触发。状态屏与减少动态使用稳定底图。

ESP32 实现应将原稿形体预烘焙成带固定空间抖动的 A8/A4 mask，移植同一生命周期和语义事件控制器；导航渲染优先，背景目标 2 Hz。禁止新增每帧 466² 渐变计算或全屏 RGB565 离屏缓冲（一张约 434,312 字节）。当前只有 palette token 到了 C++，还没有这套背景对象、资源和定时器。

先前集中聚光版的 [RGB565 量化模拟](nav-ambient-blue-rgb565-check.png)出现明显同心色阶，这也是弃用它的一个原因。[本轮旧式柔光的直接 RGB565 量化](nav-ambient-refined-rgb565-check.png)仍可见轻微阶差；量产资源应在离线制图阶段对光场使用**固定空间位置**的 8×8 有序抖动或等效蓝噪声，避免每帧随机噪声闪烁。模拟不能代替 AMOLED 实机拍摄。

## 6. 英文状态与优先级

| 场景 | 主文案 | 次文案 |
| --- | --- | --- |
| 正常右转 | `TURN RIGHT` | 距离数字独立于标签 |
| 路线几何缺失 | `MAP PREVIEW UNAVAILABLE` | 仅在引导本身仍有效时显示动作与距离 |
| 定位失效 | `GPS SIGNAL LOST` | `WAITING FOR A FRESH POSITION` |
| 重算 | `REROUTING` | `WAITING FOR A NEW ROUTE` |
| 手机断连 | `PHONE DISCONNECTED` | `OPEN MOTO GPS ON YOUR PHONE` |
| 待命 | `READY TO RIDE` | `CHOOSE A DESTINATION ON YOUR PHONE` |

状态主字约 22 px / 650，次字约 11–12 px / 550。保持 B 稿的中性白与灰，不用黄色或巨大的警告框。危险在于过期导航内容，故**状态出现时优先移除误导内容**，而不是单靠颜色表达风险。

## 7. 接到现有固件的最小改动点

| 文件 | 需要落地的改动 | 当前情况 |
| --- | --- | --- |
| `shared/nav_core/nav_core.cpp` | 保留路线前向截取和 24 点限制 | 已有，无须重写路由算法 |
| `shared/nav_presenter/src/moto_nav_presenter.cpp` | 将 `has_usable_fix`、`gnss_stale`、`off_route`、`has_next_maneuver` 等可靠性结果明确映射给 UI；保留现有稳定投影 | 目前 UI 结构缺少这些显式标志 |
| `shared/nav_ui/include/moto_nav_ui.h` | 加入少量 `guidance_valid`、`geometry_matched`、`speed_limit_validated` 等显示契约字段，或等价的单一枚举；保证电话连接独立 | 当前只有 route count 等弱条件 |
| `shared/nav_ui/src/moto_nav_ui.cpp` | `update_navigation` 以场景选择器控制 HUD、路线、状态；当前 `route_point_count >= 2` 即显示指导，需修正。复用现有 V6 位图、路线平滑、圆屏裁切；加英文标签、环境光图层 | 页面可局部修改，不重写整套原有地图绘图 |
| `shared/nav_ui/include/moto_map_visual_style.h` 和 `moto_nav_visual_geometry.h` | 集中记录本页颜色、尺寸和环境光参数，避免硬编码分散 | 已有主要底图 token 与 466 几何 |
| `platforms/esp32/main/phone_nav_bridge.cpp` | 确保 token/generation 不匹配或 BLE 断开时及时清掉有效几何/导航状态；给 UI 明确失效信号 | 已有多处清理逻辑，仍需与新选择器联测 |
| `platforms/ios/App/AppModel.swift` | 发送真实路线，同时按 GCJ-02 位置查询已验证的北京/济南本地包；不同城市的地物不串用 | 2026-10-07 已接入；完整数据、稀疏地物与无覆盖均由实际查询结果决定，实物显示仍待验收 |

限速牌的 `speed_limit_validated` 在拿不到可靠段级来源之前固定为 false，即使 `speed_limit_kph > 0` 也不直接画。当前 `moto_nav_ui.cpp` 会见非零就画，此处是必须处理的真实性差异。

## 8. 可执行验收表

1. **实地默认**：北京海淀区有效路线，无 `MapScene`，无有效限速 → 只见真路线、车辆箭头、V6 转向、距离、英文提示和细进度弧。不得出现网格、建筑、红圈。
2. **短路线**：下一动作仅数十米 → 线段短而真实，转角平顺；不延长、不错接，HUD 保持平衡。
3. **几何包迟到/版本不匹配**：保留仍有效的动作/数字，但不画虚构线条或定位在假道路上。
4. **定位 >5 秒失效、偏航重算、BLE 断开**：当帧撤下过期路线、箭头、米数、限速，出现对应英文状态；网络离线但 BLE/定位/缓存路线有效时不得误报手机断连。
5. **真实地物陆续到达**：从 `ROUTE_ONLY` 到 `ROADS_ONLY` 到 `RICH` 仅加真实图层，路径与车辆锚点不跳动，地物不跨路线版本残留。
6. **动态**：静态截图仍是原版微弱、自然的多处柔光，只略增存在感；实时观看能察觉缓慢漂移，不抢过道路。重要指引变化仅一短次响应；状态屏与减少动态冻结纹理。
7. **实屏**：用 466×466 AMOLED 实拍验收 12/18 px 路线、V6 末端、字体抗锯齿与弱反射的 RGB565 阶差。模拟器截图通过不能代替实机通过。

参考图：

- [当前数据主画面：只有路线](nav-code-ready-route-only-466.png)
- [短路线 / 临近左转](nav-code-ready-short-route-466.png)
- [引导有效但几何未到达](nav-code-ready-instruction-only-466.png)
- [定位失效](nav-code-ready-gps-lost-466.png)
- [真实道路但无建筑的示意 fixture](nav-code-ready-roads-only-466.png)
- [完整地物的**合成** fixture](nav-code-ready-rich-fixture-466.png)

这些图中的路线和地物仅为**渲染测试 fixture**，不代表北京的真实地理形状。最终设备使用百度实际路线与已获用户同意的 OSM 离线地物，喂给同一渲染规则。

## 9. 审阅入口与源码依据

Canva 的可编辑审阅稿：[本轮克制柔光修订](https://www.canva.com/d/g5PiJHfWAOnipIq)、[已选 B 英文版](https://www.canva.com/d/h_YVZfOCbe8dzLA)、[当前数据主画面校准版](https://www.canva.com/d/BGBcaS4xFYMprkW)、[短路线](https://www.canva.com/d/Oc1ErHf-nSVwuZ2)、[GPS 丢失](https://www.canva.com/d/R5x3RTZhZdeIkVq)。这些 Canva 页面由图像转为可编辑元素，后续视觉沟通使用；**本目录的 SVG/HTML 渲染规则和 466 px PNG 是像素与行为验收基准**，不能以 Canva 转换后可能出现的字形或微小位置偏差替代源码。

GitHub 插件复核的代码依据：[iPhone 真实导航查询离线 MapScene](https://github.com/liuxd2010skyline-ship-it/moto-gps-waveshare/blob/45d87f01a604fb66799ca047294c423cb63d7321/platforms/ios/App/AppModel.swift#L404-L420)、[NavCore 截取未驶过路线](https://github.com/liuxd2010skyline-ship-it/moto-gps-waveshare/blob/45d87f01a604fb66799ca047294c423cb63d7321/shared/nav_core/nav_core.cpp#L571-L637)、[实际 UI 指引条件](https://github.com/liuxd2010skyline-ship-it/moto-gps-waveshare/blob/45d87f01a604fb66799ca047294c423cb63d7321/shared/nav_ui/src/moto_nav_ui.cpp)。本轮数据与传输的构建状态见 [10 月 7 日实施记录](../docs/OFFLINE_MAP_DELIVERY_2026-10-07.md)；本地 origin 缓存不是云端状态的证据。新色板、浏览器行为参考、真实底图及固件柔光分别核对其对应提交与测试，不能把一次旧绿灯当作全部目标完成。
