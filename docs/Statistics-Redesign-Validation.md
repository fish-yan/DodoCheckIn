# 打卡统计设计稿落地验证（2026-09-21）

## 实现范围

- `App/StatisticsView.swift`：顶部熊猫、双列指标、黄色今日战绩、紫色本周探索、蓝色本月探索、七日星星轨迹、奖励卡片、前三名、成长日历和历史详情入口。
- 页面外边距 10 点，卡片圆角 20 点；保留原生导航和 TabView，适配浅色与暗黑模式。
- 数据继续由 `PeriodStatistics`、`Journal`、`BeijingCalendar` 计算；没有修改分数、达标条件、奖励结算、数据模型或历史记录。
- 新增 `StatisticsHero`、`StatisticsChest`、`StatisticsMedal`，内置 ImageGen 参考设计稿分别生成透明素材；其余任务与空状态插画复用。提示词见 `Artwork/statistics-assets-prompts.json`，来源及 SHA-256 见 `Artwork/manifest.json`。

## 已完成验证

- Xcode Debug / iOS Simulator 编译通过（iOS 27，iPhone 17e，1170 × 2532 截图）。
- 两项现有 UI 测试通过：`testRulesCalendarAndHistoryAreAvailable`、`testSingleCheckInWrongPasswordAndParentConfirmation`。覆盖确认后的统计入口、滚动到日历、历史详情及只读状态。
- 最终临时截图测试 `testCaptureStatisticsDesign` 通过。测试中显式设置设备 Light / Dark 外观；两套各 5 张滚动帧均成功到达历史详情入口，拼接后为 1170 × 6440。临时截图方法随后移除，原 UI 测试文件逐字恢复。
- 视觉检查：标题和数字未截断；两列指标、奖励说明、排行榜及日历完整；深浅模式下熊猫等透明素材没有矩形底色；不可切换的月份箭头淡化。
- 43 张工程素材透明度验证通过；3 张新增资源均含真实 alpha。
- 使用模拟器原有记录截图：本月 11 次、17.7%、14 有效分、0 奖励分、1/30 达标，与改版前一致。

## 证据

- `TestResults/StatisticsRedesign-UI.xcresult`、对应 `.log`：两项交互测试。
- `TestResults/StatisticsRedesign-Final-v2.xcresult`、对应 `.log`：最终深浅截图与编译。
- `docs/screenshots/多多打卡-新版统计完整长图-浅色.png`
- `docs/screenshots/多多打卡-新版统计完整长图-暗黑.png`

## 边界

未安装、预览或运行到真实 iPhone；未执行真机验证。没有 iOS 17 模拟器运行时，因此本次运行验证限于 iOS 27。未改业务规则，本轮没有重复运行核心规则测试。编译仅有未依赖 AppIntents 的元数据提取提示。

## 月度达标进度卡片更新

- 按月度进度设计稿增加独立半透明卡片、大号达标天数、18 点粗胶囊进度和 40 点笑脸星星。
- 数值仍使用本月实际达标天数和当月总天数；星星位置及填充范围使用相同进度比例，0 到 100% 均限制在卡片内。
- 按要求省略进度条上的 25 天、全月奖励说明及关联进度点、连线，原有两张奖励状态卡片保留。
- `TestResults/MonthlyProgress-UI.xcresult`：Debug 编译及临时深浅模式截图检查通过。截图方法已移除，原 UI 测试文件逐字恢复。未运行真机或重新执行核心规则测试。
- 实际截图：`docs/screenshots/MonthlyProgressCard-Light.png`、`MonthlyProgressCard-Dark.png`；对应整屏截图为 `MonthlyProgress-Light.png`、`MonthlyProgress-Dark.png`。
- 素材验证通过（共 44 张）；新增笑脸星星为真实透明 PNG。提示词及来源见 `Artwork/monthly-progress-star-prompt.txt`、`Artwork/manifest.json`。
