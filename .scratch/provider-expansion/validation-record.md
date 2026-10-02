# Provider 集成验证记录

最新（2026-10-03，源码379d5dd）：78个provider、69张接入票全部完成。773项完整XCTest零失败；unsigned TokenPulse target包含App、Watch与两端Widgets构建成功；78个图标映射存在。日志 `/tmp/tokenpulse-wave4-final.log`、结果 `/tmp/tokenpulse-wave4-final.xcresult`、构建 `/tmp/tokenpulse-wave4-final-unsigned.log`。第四批10组Pi已完成并逐项处理，见[第四批记录](wave4-progress.md)与[Pi报告](pi-wave4/README.md)。真实账号/实体设备观察不伪称已完成。

以下按批次保留历史过程与当时标准。

## 历史：Sol 首批集成验证

> 最新决定（2026-10-02）：用户将接入票验收简化为图标存在。46个现有provider均通过，37张实现票已关闭，解除24张后继票的依赖。下文保留此前测试及真实验证事实；其中“真实验证阻塞关票”的旧口径已被本决定替代。见[图标验收](icon-acceptance.md)。

日期：2026-10-02。分支：feature/provider-expansion-sol。模型：6 个 gpt-6.1-sol 工作者与 root 集成者。

## 范围与结果

已实现并集成 01 智谱国内版、02 MiniMax 国际版、03 GitHub Copilot、09 Poe、10 Vercel AI Gateway、11 ElevenLabs、12 New API、40 StepFun。提供商枚举从 9 个扩展到 17 个；本轮新增 8 个，未把全部 69 张票标完成。

- 全部 238 项 XCTest 通过，0 failures；原有基线为 148 项。
- unsigned TokenPulse target build 成功，包含 iPhone App、Watch App、两端 Widget 与资产目录编译。
- 真实的本机回环 HTTP fixture 通过生产 GatewayProviderTransport 请求成功，未发送账号 Key 或 Cookie；不代表物理设备私网权限已验收。
- iPhone 17 Pro / iOS 26.5 演示界面已用 Simulator 的截图和可访问性树检查：ElevenLabs 字符单位、Poe points、Vercel 缺失明细、智谱与 MiniMax 地区名称、StepFun 到期/重置区分、New API 余额、Copilot 三项额度与套餐名；添加入口可打开。只使用示例数据，没有登录提供商。
- 63–69 的 7 份源码研究已保存，公开证据的哈希复核由研究组执行。各报告保留手机/Watch 真实验证条件。

## 实际执行命令

```sh
xcodebuild test -project TokenPulse.xcodeproj -scheme TokenPulse \
  -destination 'platform=iOS Simulator,id=DE50A540-0662-4C76-BF55-6EADDDEF7B68' \
  -derivedDataPath /tmp/tokenpulse-sol-tests \
  -resultBundlePath /tmp/tokenpulse-sol-release-validation.xcresult \
  -parallel-testing-enabled NO

xcodebuild build -project TokenPulse.xcodeproj -target TokenPulse \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  SYMROOT=/tmp/tokenpulse-sol-products OBJROOT=/tmp/tokenpulse-sol-objects
```

结果日志：`/tmp/tokenpulse-sol-release-validation.log`、`/tmp/tokenpulse-sol-final-build.log`。测试结果包：`/tmp/tokenpulse-sol-release-validation.xcresult`。这些是本机临时验证产物，不是仓库携带的跨机器附件。

## 发现并修复的问题

- 运行时缺失及 SDK build 映射错误：安装 iOS 26.5 arm64 (23F73)，为 SDK 23F81a 配置当前 Xcode 的运行时映射；细节与恢复默认命令在团队记录。
- 原工程 PlatformTests 固定另一机器绝对路径，改为 SOURCE_ROOT 相对路径。
- 多个 provider 集成时补齐共享枚举、查询、Widget 与演示分支，保留每家凭证和单位语义。
- 修复 Swift 6 XCTest actor 隔离，使用独立 UserDefaults 实例和 Date 值捕获。
- Poe 小组件显示非货币积分；区域 scoped 窗口保留详情，无限额度不显示伪造有限计数。
- ElevenLabs 极大重置时间溢出回归先失败后修复；解析边界和提醒规划均保护时间转换。
- Copilot 百分比完整但计数缺失的窗口得以保留；数字不能冒充布尔状态。两项回归先失败再修复，全套通过。
- StepFun 畸形响应不能清除旧套餐；关闭/切站取消登录验证，Cookie 读取完成后发送请求前重查当前会话。
- 云端合并按最终配置的凭证身份筛选快照和提醒记录，旧设备迟到数据不覆盖新账号；新快照先到、Keychain 仍旧时保留正确缓存。
- 启动时没有数据变更不重写真实存储，演示往返和取消刷新原有回归重新通过。Token 数量使用浮点容差断言；货币保持 Decimal 精确断言。

## 尚未验收

真实账号授权及 provider 当前兼容性、真实凭证失效和续期、iCloud Keychain 跨设备到达、物理 Watch 在手机离线时独立刷新、物理设备私网权限与可达性，以及各尺寸小组件/表盘的系统级完整验收。模拟器截图、响应 fixtures 和 unsigned build 不替代这些证据。

首批票均为 implemented-awaiting-real-validation，研究票为 awaiting-validation；后继票没有绕过真实依赖门槛启动。

# Sol 第二批集成验证

日期：2026-10-02；首批基线 `6c12386`，第二批整组集成 `c082bba`。继续使用六个 Sol 工作者独立 worktree，root 串行运行 Xcode 与 Simulator。

## 范围

新增 29 个 provider：Moonshot、Alibaba Coding Plan、Factory、Synthetic、V2EX、Command Code、Amp、Atlas Cloud、Chutes、ClinePass、Codebuff、DeepInfra、DevPass、GitKraken AI、Hugging Face、Hyper、IBM Bob、Kilo Code、Neuralwatt、v0、Venice、Warp、xKiro、ZenMux、Aixy、ClawRouter、xAI API、Volcengine、Cursor。提供商枚举从 17 扩展为 46；Moonshot 的国内/国际区域、Factory 的两种计费模式仍是各自同一 provider。

## 已实际执行

- `c082bba` 完整 XCTest：457 项、0 失败，`/tmp/tokenpulse-sol-wave2-full46.log` 与 `/tmp/tokenpulse-sol-wave2-full46.xcresult`。
- `c082bba` unsigned `TokenPulse` target build 成功，包含 iPhone、Watch、两端 Widgets 及资产目录：`/tmp/tokenpulse-sol-wave2-unsigned.log`。
- 独立新建 `TokenPulse Wave2 Review` iPhone 17 Pro / iOS 26.5 模拟器（`EE85B732-757D-4ECA-9447-F8BD7AEEEAD8`），安装上述测试产物，以 `-demoModeEnabled YES` 启动。仅使用合成数据，未登录任何 provider。通过原生 Simulator 可访问性树及截图浏览全部新增账号卡片；重点截图检查了 Aixy 多预算范围、Neuralwatt kWh/美元限额/钱包、Codebuff credits、Moonshot 双区域币种、Kilo/DeepInfra 混合钱包、Hyper/DIEM 非货币余额、Amp 持续补充与纯日期、Hugging Face GPU 秒、Synthetic 部分补充、xKiro 独立免费 tokens、Cursor 双模型池、火山双计划、IBM Bob 缺分母仅已用、Warp grant 到期和 v0/DevPass。添加表单和 provider 菜单可打开，取消后未新增账号。
- 截图/可访问性证据在本次工具记录中；没有声称逐一验证所有 Widget 尺寸或物理 Watch 界面。

命令与首批相同，测试结果包改为上述第二批路径。模拟器 XCTest 保留代码签名以验证 Keychain；设备 target build 使用 `CODE_SIGNING_ALLOWED=NO`。两种构建未并行执行。

## 整合与复核修正

- 保留 Decimal 部分计数、仅日期精度、连续补充/非周期额度、钱包独立采集时间及失败状态，避免工作分支覆盖共享模型。
- 精确阈值使用 Decimal 比较，避免接近上限的数量因 Double 舍入提前触发；恢复补充只重新允许阈值提醒，不伪造完整重置。
- 更新凭证后按实际身份隔离旧快照；区域和组织范围保留，未把不同实例预算相加。
- 修复 Chutes 适配可选 Decimal 字段后的编译问题；全量集成后再执行测试。
- 界面抽查发现非周期补充包仍显示“下次重置：未提供”，已改为“额度类型：无周期重置”；真实 grant 到期时间继续显示。

## 验收边界

29 张票均保留 `implemented-awaiting-real-validation`。没有读取真实 Key/Cookie，没有验证实际套餐、续期、当前网页接口可用性、跨设备 iCloud 凭证到达、手机离线时物理 Watch 独立查询。尤其百炼 Key 与控制台会话兼容性、Cursor 移动授权以及 Warp macOS 兼容请求头仍需要真实账号证据。其余 25 张依赖票未绕过前置验收启动；7 张研究票保持待验证。


## 第二批最终复核结果（c5e3382）

- 完整 XCTest **465 项通过，0 failures**，日志 `/tmp/tokenpulse-sol-wave2-verified.log`，结果包 `/tmp/tokenpulse-sol-wave2-verified.xcresult`。
- 同一源码 unsigned `TokenPulse` target build **BUILD SUCCEEDED**，覆盖 App、Watch、两端 Widgets 与资产目录；日志 `/tmp/tokenpulse-sol-wave2-verified-unsigned.log`。
- 检查37个provider image sets：均有明确SVG尺寸、无currentColor、开启vector preservation和template rendering。
- 新增回归覆盖混合账号旧nil设置第一次关闭额度告警时钱包偏好独立、Chutes部分计数持久化、Decimal极小余量、DevPass缺字段/零限额保留旧数据。DevPass仅明确JSON null限额才能显示无上限，矩形complication优先显示状态文案。
- `/tmp/tokenpulse-sol-wave2-final.log`记录复核中间失败：465项中同一Chutes极小余量回归有3个断言失败。实测Apple Foundation在对齐相距很远的小数指数后可能返回noError却丢弃减数；最终加入逆减法一致性检查，不修改回归断言，重跑全量已通过。未把中间失败隐藏为成功。
- 界面抽查仍对应c082bba演示版；之后的开关、非周期额度文案与矩形complication小改动通过回归、代码检查和最终多目标构建，未补充物理Watch或系统级各尺寸组件的视觉验收。

最终代码均提交于 `feature/provider-expansion-sol`。票据总计69张：37张实现待真实验收、7张研究待验证、25张依赖票未实施；没有将真实验收勾选为完成。


# 第三批 Sol 实施与 Pi 批量回归最终验证

完成日期：2026-10-03。最终源码提交：4adb520。分支feature/provider-expansion-sol。用户指定“实现完成+图标存在”作为接入验收；真实账号与物理设备验证记录不作为关票门槛，也未伪造为已执行。

## 范围与结果

- 第三批25个provider全部集成：sub2api、Bifrost、LiteLLM、LLM API Key Proxy、小米Coding Plan、Qoder国内、Ollama Cloud、Devin、Abacus、Augment、LongCat、Manus、Mistral、Notion AI、Perplexity API、Qwen Cloud、Raycast AI、Replicate、Sakana、T3 Chat、TypeSafe、Zed、ZoomMate、Grok Bot、Windsurf。
- 现有71个provider，全部图标映射存在：56个资产映射对应53套SVG，15个SF映射对应8种系统符号。向量/模板属性、尺寸、currentColor替换、文件与符号存在性均检查通过。18个通用图标没有冒充品牌资产。
- **638项完整XCTest通过，0 failures**；结果 `/tmp/tokenpulse-wave3-final.log` 和 `/tmp/tokenpulse-wave3-final.xcresult`。
- **同源码unsigned TokenPulse target BUILD SUCCEEDED**；日志 `/tmp/tokenpulse-wave3-final-unsigned.log`，包含App、Watch、两端Widgets及资产目录。
- 69张票中62张integration均done，7张feasibility研究票未完成且未伪加provider。新增25票按最新口径验收，历史真实验收复选框仍保留原事实。

## Pi执行与处理

按用户要求启动10个独立Pi任务，冻结各阶段源码，限定本地分析、Swift/Python复现及报告；禁止读取真实凭证、禁止Xcode/模拟器、禁止改工作分支。默认zcode/glm-5.3-flash服务503后切换已配置cch/glm-5.3，并以4并发交付全部报告。部分代理524错误留档；CLI退出码0不代表模型任务或测试成功。完整报告经root审阅后归档到[pi-regression](pi-regression/README.md)，临时复现源码/输出及事件保留在 `/tmp/tokenpulse-pi-regression-20261002-222956`。

修复了Claude新登录UUID与旧会话来源身份、普通API Key和MiniMax原始Key换绑后旧缓存/云数据污染、登录浏览器重启视图身份、乱序额度/空帧/提醒计划保护、Chutes兼容分支Decimal舍入、微小余额显示、T3 null重置回退、Qwen无套餐与历史tier并列、Manus不可信used推导；另增加有界Mistral flight多参数与Sakana inline标题支持。Replicate遍历上限保留完整枚举要求，未以部分结果自动选组织；“找不到许可”观察已用Notices 41/43/45行纠正。root另复现并修复ZoomMate将HTTP400/404/422误当5xx而换主机的问题。

## 中间失败与最终纠正

- 初次完整71版编译发现重复Augment UI引用未定义augmentResetAvailable；删除重复控件，复用现有reset能力判断，随后607项通过。
- Mistral overflow测试以38个9相加假定溢出；原生Foundation证明该和仍可表示。改用Decimal.greatestFiniteMagnitude的真实溢出输入，微额吸收断言原样保留，后续通过。
- ZoomMate新4xx请求计数回归先产生3个失败断言；保留HTTP状态分类后同套10项相关回归通过。
- 提醒单调性修复全套629项中的两个既有回归失败，原因是等时previousWindow被丢弃但ledger使用判断仍为严格大于。改为等时也使用ledger用量，原断言不改，629项全过。
- API Key通用身份修复导致Factory/DevPass/v0/Warp的wrong-kind guard四个既有断言失败；恢复仅API Key类型可建立该身份的守卫，原断言保留。
- 最终638项覆盖以上纠正及MiniMax raw Key兼容性，不把中间失败隐藏为通过。

## 实际命令

```sh
xcodebuild test -project TokenPulse.xcodeproj -scheme TokenPulse \
  -destination 'platform=iOS Simulator,id=DE50A540-0662-4C76-BF55-6EADDDEF7B68' \
  -derivedDataPath /tmp/tokenpulse-sol-tests \
  -resultBundlePath /tmp/tokenpulse-wave3-final.xcresult \
  -parallel-testing-enabled NO

xcodebuild build -project TokenPulse.xcodeproj -target TokenPulse \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  SYMROOT=/tmp/tokenpulse-sol-products OBJROOT=/tmp/tokenpulse-sol-objects
```

Xcode与模拟器始终由root串行运行；Pi及Sol工作者的小模块检查不冒充完整XCTest。前批演示截图属于对应版本，本轮没有新增真实登录、iCloud、物理Watch或所有尺寸组件视觉验收。临时日志/结果包是本机产物，不是仓库内的跨机器附件。
