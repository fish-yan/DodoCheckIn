# 多多打卡 · 熊猫宇航员素材

工程内共 44 张 ImageGen 图片（深浅印章分别计数），采用柔软黏土与毛绒质感的太空玩具风格。新版首页依据第二版 iPhone 设计稿重建可独立使用的场景与任务插画，再从透明图集中切分 17 项任务。

| 素材 | 使用位置 |
| --- | --- |
| SectionEnergyFrame / SectionKnowledgeFrame / SectionLifeFrame / SectionCourageFrame | 四组透明基地装饰和完整边框，1080 × 1440，3x 资源，保留顶部和圆角后拉伸直边 |
| HomeLaunchScene | 首页熊猫飞船场景，1536 × 1024，不透明；文字、数字及进度由原生控件叠加 |
| MissionWake … MissionHonesty | 17 张任务插画，每张 384 × 384，真实透明通道、完整轮廓 |
| AppIcon | iOS 桌面图标，1024 × 1024、不透明 |
| AstronautWave | 首页底部熊猫伙伴 |
| SpaceRocket | 星际旅程页顶部 |
| CelebrationPanda | 打卡成功及家长确认庆祝 |
| RewardTreasure | 周月奖励庆祝、统计奖励进度 |
| EmptyExplorer | 尚无有效打卡的统计空状态 |
| PlanetMercury … PlanetNeptune | 首页月度预览和旅程页的八大行星 |
| ParentApprovalStamp / Dark | 家长确认后的半透明盖章标记 |
| TaskCardPending / TaskCardCompleted | 旧版卡片背景，保留资源；新版首页改用原生浅色卡片和独立插画 |

最终 PNG 位于 `../App/Assets.xcassets/`。`manifest.json` 记录所有图片的完整提示词、原始输出路径、工程路径和 SHA-256。本轮参考稿为 `Designs/多多打卡-iPhone原生适配设计稿.png`，完整生成提示词及来源见 `home-native-assets-prompts.json`；透明原始图集和每项切分坐标保存在 `Source/HomeMissionAtlas.png`、`Source/HomeMissionAtlas-crops.json`。

所有任务名称、计分信息、进度、按钮及导航均为原生 SwiftUI 控件。任务网格始终双列，奇数项最后一张保持半宽。装饰图片对 VoiceOver 隐藏，未解锁行星同时有锁图标和名称；庆祝支持减少动态效果和跳过。

印章沿用独立深浅资源，显示大小 36 点、旋转 -8°、顶部 8 点/右距 8 点，盖在卡片右上角，不占一行、不拦截点击。浅色不透明度 26%、暗黑 48%；保留“家长已确认”无障碍说明。原始提示词见 `parent-approval-prompt.json` 和 `parent-approval-dark-prompt.json`。

浏览全部素材：打开 `index.html`。资源验证：在工程根目录运行 `swift tools/verify_artwork.swift`，检查图标尺寸、不透明像素和各插画透明通道。验证详情见 `../docs/VALIDATION.md`。

四组装饰通过 ImageGen 基于设计稿提取，提示词与原始来源见 `section-frame-prompts.json`。透明中心允许原生背景随分区主题和深浅模式变化；边框按 top 112 / left 24 / bottom 24 / right 24 点进行保护式拉伸，避免整张装饰随任务数量变长。标题、分值、分区计数及按钮始终由原生控件渲染。

分区卡片相对边框图片左右各留 28 点、底部留 32 点；顶部按照各素材内沿（74 / 86 / 82 / 98 点）再留 12 点，让可见边框内侧的四周留白接近。完成进度以 64 × 22 点、65% 不透明底色的胶囊叠在顶部边框下沿，不再额外占用一行。

## 打卡统计设计稿落地（2026-09-21）

参考 `Designs/多多打卡-儿童打卡统计设计稿-v2.png`，使用内置 `image_gen.imagegen` 分别提取重绘三张透明素材：

| 工程资源路径 | 用途 |
| --- | --- |
| `App/Assets.xcassets/StatisticsHero.imageset/StatisticsHero.png` | 顶部抱星熊猫、星球与云朵，512 × 512 |
| `App/Assets.xcassets/StatisticsChest.imageset/StatisticsChest.png` | 自然周奖励宝箱，192 × 192 |
| `App/Assets.xcassets/StatisticsMedal.imageset/StatisticsMedal.png` | 月度两阶段奖励勋章，192 × 192 |

以上路径相对工程根目录。完整提示词保存在 `statistics-assets-prompts.json`，原始输出路径及文件哈希已追加至 `manifest.json`；素材总数为 43 张。`EmptyExplorer`、行星和任务插画复用工程已有资源，数字、卡片、图标、周星星进度、日历仍由 SwiftUI 实时渲染。原生导航栏与三 Tab 保持不变。周星星只按实际有效得分达标日期点亮，未获得的月度勋章降低饱和度，并显示“探索中”。


月度达标进度卡片新增 `App/Assets.xcassets/MonthlyProgressStar.imageset/MonthlyProgressStar.png`（192 × 192 透明笑脸星星）。使用内置 ImageGen 参考 `Designs/多多打卡-月度打卡进度优化设计稿.png` 提取重绘，提示词见 `monthly-progress-star-prompt.txt`，原始输出和 SHA-256 已登记在 `manifest.json`。加粗进度条由原生 SwiftUI `ProgressViewStyle` 绘制，星星按真实达标天数移动；不含奖励节点、连线及说明，原有奖励卡片保留。
