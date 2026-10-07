# MOTO GPS 圆屏导航 · 设计总表

更新：2026-10-06。范围是微雪 466 × 466 圆屏的导航主画面及导航状态。本表整理视觉决定；效果图用于审美验收，不能代替真实地理数据。

当前可执行标准见 [V6/B 代码化设计契约](NAV_CODE_READY_SYSTEM_V1.md)，逐项落地与底图问题见 [实现审计](NAV_IMPLEMENTATION_AUDIT_2026-10-06.md)。后续确认的英文标签、B 石墨材料、无过去尾巴及随机有限柔光优先于下文历史候选中的中文、旧尺寸与固定背景规则；历史图保留供对照。

2026-10-07：先完成数据与建筑传输，沿用此处的视觉标准。OSM 北京离线包已通过生成、数据校验和生产查询测试，新固件支持 48 个建筑外轮廓 / 240 点；[实施记录与实机步骤](../docs/OFFLINE_MAP_DELIVERY_2026-10-07.md)列明本轮实际结果。柔光、英文 HUD 和完整 B 材质仍按实现审计继续，不把数据包成功等同于全部视觉模块落地。

当前统一的视觉冻结提案见 [`NAV_DRAWING_STANDARD_CONFIRMATION.md`](NAV_DRAWING_STANDARD_CONFIRMATION.md)；**原生尺寸确认图**是 [`nav-native-466-dimensioned.png`](nav-native-466-dimensioned.png)，而 [`nav-final-standard-review.png`](nav-final-standard-review.png) 仅用于审美方向对照。其中已加入“白色路线只显示当前位置前方，已走过路段无小尾巴”的最新要求；用户确认前，候选细节仍按本表标注。

## 已确定的方向

| 项目 | 当前决定 | 参考 |
| --- | --- | --- |
| 整体构图 | 以 V6 圆盘效果图为基准：地图占主体，下方短渐隐连接导航信息，圆盘边缘只有窄暗晕 | [`moto-gps-v6-screen-effect.png`](moto-gps-v6-screen-effect.png) |
| 色彩 | 地图采用黑、灰、白的克制体系；红色限速牌作为原图中的功能性标识保留，不给建筑和地表加入鲜艳色 | [`BUILDING_MATERIAL_V3.md`](BUILDING_MATERIAL_V3.md) |
| 下方转向符号 | 使用用户确认的 V6 同系列箭头；箭杆底部平直、转弯圆润、无外框 | [`maneuver-icon-family-v6.png`](maneuver-icon-family-v6.png) · [`maneuver-icons-v6/`](maneuver-icons-v6/) |
| 字体方向 | 数字、单位与中文指引按苹方的字重和基线设计；Windows 预览字形为替代字体 | [`TYPOGRAPHY_PINGFANG_V1.md`](TYPOGRAPHY_PINGFANG_V1.md) |
| 图标语法 | V6 七枚转向箭头原样保留；转向、位置、限速与导航状态各有独立语义和尺寸 | [`NAV_ICON_STANDARD_V1.md`](NAV_ICON_STANDARD_V1.md) · [`nav-icon-standard-v1.png`](nav-icon-standard-v1.png) |
| 地图真实性 | 道路、建筑和地表形状来自可用数据；缺失的建筑不补画假轮廓 | [`NAV_VISUAL_DIRECTION.md`](NAV_VISUAL_DIRECTION.md) |

## 已有设计稿，仍需视觉确认

| 项目 | 当前候选 | 待确认之处 |
| --- | --- | --- |
| 建筑材质 | [`building-material-v3-screen-effect.png`](building-material-v3-screen-effect.png)；深石墨灰、低幅度明暗、无明显描边与粗糙纹理 | 用户尚未明确确认 V3 整屏效果 |
| 道路与骑行位置箭头 | [`road-and-position-marker-v1-screen-effect.png`](road-and-position-marker-v1-screen-effect.png)；道路分级、细微明暗变化、白色位置箭头 | 道路微渐变的强度与 466 px 边缘需要整屏确认 |
| 字体细节 | [`typography-pingfang-screen-v1.svg`](typography-pingfang-screen-v1.svg)；数字/单位比例 | 在 466 px 下的三位、四位距离与中文实际观感 |
| 补充图标 | 到达、限速圈、连接中/断连、定位与重新规划的 V1 矢量 | 在导航状态整屏与 466 px 实机确认；V6 七枚不受影响 |
| 稀疏底图 | 保持同一构图，真实道路、白色路线与车辆箭头为主体，以深色留白替代虚构建筑 | 候选已与密集城市并列，待视觉确认 |

三种代表性画面已形成候选并列图：[`nav-three-scenarios-v1.svg`](nav-three-scenarios-v1.svg)；包括密集城市、建筑稀少、手机断连。尚待用户视觉确认，不等同设计冻结。

极端数据缺失候选：[`nav-worst-data-v1.png`](nav-worst-data-v1.png) / [`NAV_WORST_DATA_V1.md`](NAV_WORST_DATA_V1.md)。同一条真实路线分别以原始和优化镜头显示；路线或定位也失效时清楚暂停指引。这一稿不伪造周边道路或建筑，仍待用户视觉确认。

十二种基础状态当前视觉候选：[`nav-scenarios-atlas-v2.png`](nav-scenarios-atlas-v2.png) / [`NAV_SCENARIO_ATLAS_V1.md`](NAV_SCENARIO_ATLAS_V1.md)。覆盖底图密度、定位、航向、蓝牙与网络、偏航重算、临近转弯、复杂立交和到达。V1 方块草图已由符合 V6 材质层级的 V2 设计样本替代；判定证据仍是文字规则，未写成产品代码。

六种复合压力场景当前视觉候选：[`nav-composite-cases-v2.png`](nav-composite-cases-v2.png) / [`NAV_COMPOSITE_CASES_V1.md`](NAV_COMPOSITE_CASES_V1.md)。重点处理 GPS 孤立跳点、遮挡、离线偏航、连续转弯、限速路段切换以及重连后路线版本不一致，明确旧指令撤下与恢复的条件。共 18 枚 V6 风格示意圆盘；详细视觉改动见 [`NAV_VISUAL_ATLAS_V2.md`](NAV_VISUAL_ATLAS_V2.md)。

已否定的 [`building-color-v1-comparison.png`](building-color-v1-comparison.png) 仅能用来分析地图数据密度；V2 建筑纹理稿也不是当前视觉目标。不要从这些图反推新 UI。

## 尚需完成的最小视觉集合

1. **稀疏底图整屏稿确认**：候选已画出，需确认建筑少时的留白、道路骨架与下方信息是否仍然协调；无足够地物时不伪造街区。
2. **地图灰阶地物规则**：绿地、水域和大面积非建筑地表若有可靠数据，确定近黑灰的层次；若无数据，明确视觉留白。道路的路口、并行道路、桥与隧道需要有清楚的遮挡关系。
3. **HUD 组合表**：同一版式下展示 `80 m`、`300 m`、`1.2 km`；左、右、直行、掉头及环岛；有/无限速值。检验字号、留白和左右视觉平衡。
4. **导航状态图**：正常导航、重新规划、定位暂失、手机断连、到达终点。状态变化不能突然把 V6 主画面换成风格不同的大字黑屏。
5. **466 px 实际尺寸总图**：将以上已确认状态放到圆屏原生像素查看建筑边缘、路线弯角、箭头、渐隐和字距，作为设计冻结的依据。

这些是**设计收束项**，不表示现在开始修改固件、协议或数据来源。每一项确认后记录成唯一当前版本，避免多个候选互相冲突。
