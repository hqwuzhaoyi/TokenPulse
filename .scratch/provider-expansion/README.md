# TokenPulse provider 扩展 tickets

状态：用户于 2026-10-02 以“可以”批准完整拆分；69 张 tickets 已正式发布至本地 tracker，每票单独成文，状态为 `ready-for-agent`。任务尚未开始实现。

范围：按 Pulse 固定版本的 77 个内置 provider 对照本地 9 个已接入项，覆盖全部 68 个未接入 provider，并补充 Qoder 国内站。已有 Claude、Codex、OpenCode Go、Kimi Code、Z.ai、MiniMax 国内版、SuperGrok、DeepSeek、Qoder 国际版不重复建接入票。

62 张为有远程路径参考的端到端接入候选，7 张为可行性验证。候选不等于真实账号验证通过。验证票只有产出结论的验收要求，正式接入须在可行性通过后另拆实施票。

每张接入票均覆盖账号配置、凭证、双端独立刷新、展示、小组件、适用提醒、演示数据、图标、测试和真实验收。金额余额、积分、token、GPU 时长与套餐配额使用各自单位。无真实凭证时保留未验收状态。

发布方式：沿用仓库已确认的本地 tracker，正式工单位于 `issues/`。`ready-for-agent` 表示工单已准备好；只有所有阻塞票完成后才可领取，不代表实现或真实验收已完成。

依赖只表达计划中明确复用的能力：12 随 New API 交付按账号配置地址；40 随 StepFun 交付隔离的网页登录与 Cookie 路径；44 随 Devin 交付网页存储凭证提取；60 随 Cursor 交付 Cursor 授权。共享能力与首个真实 provider 一同验收，不另开空壳基础设施票。

修正先前调研：Aixy、ClawRouter 的上游实现仅使用固定托管地址，不依赖 12；GitKraken 使用会话 access token，需要明确失效与重新配置。

## 编号、交付与阻塞

1. **[智谱国内版套餐额度接入](issues/01-zhipu.md)**

   **Blocked by:** 无。**What it delivers:** 用户输入国内 Coding Plan Key 后，在 iPhone、Watch 与小组件查看国内账号的套餐额度。

2. **[MiniMax 国际版套餐额度接入](issues/02-minimax-international.md)**

   **Blocked by:** 无。**What it delivers:** 用户添加 MiniMax 国际服务账号，两端独立查询套餐额度，与国内版同时使用。

3. **[GitHub Copilot 设备授权与额度查询](issues/03-copilot.md)**

   **Blocked by:** 无。**What it delivers:** 用户从 iPhone 完成 GitHub 设备授权，同步后可在 Watch 独立查看 Copilot 额度。

4. **[Moonshot API 钱包余额接入](issues/04-moonshot.md)**

   **Blocked by:** 无。**What it delivers:** 用户明确选择 Moonshot 国内或国际账号并输入 Key，两端查看对应币种的 API 钱包余额。

5. **[阿里百炼 Coding Plan 额度接入](issues/05-alibaba-coding-plan.md)**

   **Blocked by:** 无。**What it delivers:** 用户选择百炼国内或国际服务并提供可用凭证，在双端查看 Coding Plan 三个额度周期。

6. **[Factory 套餐额度接入](issues/06-factory.md)**

   **Blocked by:** 无。**What it delivers:** 用户输入 Factory Key，在双端查看账号采用的计费模式及对应套餐额度。

7. **[Synthetic 多窗口额度接入](issues/07-synthetic.md)**

   **Blocked by:** 无。**What it delivers:** 用户输入 Synthetic Key，在双端分别查看 5 小时、每周和搜索额度。

8. **[V2EX AI Chat 额度接入](issues/08-v2ex.md)**

   **Blocked by:** 无。**What it delivers:** 用户输入个人访问 Token，在双端查看 AI Chat 滚动额度及购买的补充包。

9. **[Poe points 余额接入](issues/09-poe.md)**

   **Blocked by:** 无。**What it delivers:** 用户输入 Poe Key，在双端及小组件查看剩余 points。

10. **[Vercel AI Gateway 钱包余额接入](issues/10-vercel-ai-gateway.md)**

   **Blocked by:** 无。**What it delivers:** 用户输入 AI Gateway Key，在双端查看美元余额并配置低余额提醒。

11. **[ElevenLabs 字符额度接入](issues/11-elevenlabs.md)**

   **Blocked by:** 无。**What it delivers:** 用户输入具有 user_read 权限的 Key，在双端查看账期字符用量与重置时间。

12. **[New API 自定义地址与余额查询](issues/12-new-api.md)**

   **Blocked by:** 无。**What it delivers:** 用户添加自定义网关地址和 Key，在双端查询 New API 钱包余额；同一提供商可配置多个服务器。

13. **[sub2api 分组额度与余额接入](issues/13-sub2api.md)**

   **Blocked by:** 12。**What it delivers:** 用户配置 sub2api 地址和分组 Key，在双端查看该分组实际提供的余额、配额、订阅或限流窗口。

14. **[Bifrost 虚拟 Key 预算接入](issues/14-bifrost.md)**

   **Blocked by:** 12。**What it delivers:** 用户配置 Bifrost 网关与虚拟 Key，在双端查看 Key、上游提供商和模型的预算窗口。

15. **[LiteLLM 用户与团队预算接入](issues/15-litellm.md)**

   **Blocked by:** 12。**What it delivers:** 用户配置 LiteLLM 地址与虚拟 Key，在双端分别查看对应用户及团队预算。

16. **[Command Code 美元余额与限额](issues/16-command-code.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Key 后查看美元余额和服务明确给出的用量限额。

17. **[Amp 套餐额度与余额](issues/17-amp.md)**

   **Blocked by:** 无。**What it delivers:** 输入 access token 后查看 Free、Agent、Orb 额度和个人美元余额。

18. **[Atlas Cloud 钱包余额](issues/18-atlas-cloud.md)**

   **Blocked by:** 无。**What it delivers:** 输入具有余额读取权限的 Key 后查看账户余额并配置低余额提醒。

19. **[Chutes 订阅额度](issues/19-chutes.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Key 后分别查看滚动窗口和月度订阅额度。

20. **[ClinePass 多周期额度](issues/20-clinepass.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Key 后查看 5 小时、每周及每月额度。

21. **[Codebuff Key 模式 credits](issues/21-codebuff.md)**

   **Blocked by:** 无。**What it delivers:** 输入 API Key 后查看可查询的 credits 余额及有完整分母的额度窗口。

22. **[DeepInfra 钱包与支出上限](issues/22-deepinfra.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Key 后查看可用美元余额和服务实际配置的支出上限。

23. **[DevPass 套餐与 Key 限额](issues/23-devpass.md)**

   **Blocked by:** 无。**What it delivers:** 输入 LLM Gateway Key 后查看 premium 每周额度、套餐 credits 与 Key 限额。

24. **[GitKraken AI 个人与组织额度](issues/24-gitkraken.md)**

   **Blocked by:** 无。**What it delivers:** 输入 GitKraken 账户会话 token 后查看个人额度和对应组织共享额度。

25. **[Hugging Face ZeroGPU 额度](issues/25-hugging-face.md)**

   **Blocked by:** 无。**What it delivers:** 输入用户 token 后查看 ZeroGPU 已用与剩余 GPU 时长。

26. **[Hyper Hypercredits 余额](issues/26-hyper.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Key 后在手机、Watch 和小组件查看 HC 余额。

27. **[IBM Bob 团队 Bobcoins 预算](issues/27-ibm-bob.md)**

   **Blocked by:** 无。**What it delivers:** 输入受支持凭证后查看各实例和团队的 Bobcoins 使用与预算。

28. **[Kilo Code 钱包与 Kilo Pass](issues/28-kilo-code.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Key 后查看美元余额与 Kilo Pass 当期额度。

29. **[Neuralwatt 订阅与钱包](issues/29-neuralwatt.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Key 后分别查看 kWh 订阅额度、Key 支出限额和美元余额。

30. **[v0 账期额度与限流](issues/30-v0.md)**

   **Blocked by:** 无。**What it delivers:** 输入 v0 Platform Key 后查看账期 credits 和消息限流窗口。

31. **[Venice USD 与 DIEM 余额](issues/31-venice.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Key 后查看账号实际消费的 USD 或 DIEM 余额。

32. **[Warp 套餐与附加 credits](issues/32-warp.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Warp Key 后查看套餐及附加 credits。

33. **[xKiro 配额与钱包](issues/33-xkiro.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Key 后查看 5 小时、每周、每日免费 token 和钱包余额。

34. **[ZenMux 管理额度与余额](issues/34-zenmux.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Management Key 后查看 5 小时、7 天额度及按量钱包余额。

35. **[Aixy 托管网关预算](issues/35-aixy.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Aixy Key 后查看当前 Key 或项目适用的预算。

36. **[ClawRouter 托管预算](issues/36-clawrouter.md)**

   **Blocked by:** 无。**What it delivers:** 输入 Key 后查看托管 ClawRouter 的已配置月度预算。

37. **[LLM API Key Proxy 分组额度](issues/37-llm-proxy.md)**

   **Blocked by:** 12。**What it delivers:** 配置服务器地址和 Key 后查看每个上游的各配额组。

38. **[xAI API 团队预付余额](issues/38-xai-api.md)**

   **Blocked by:** 无。**What it delivers:** 配置 Team ID 与 Management Key 后查看该团队美元余额。

39. **[火山方舟 Coding 与 Agent Plan](issues/39-volcengine.md)**

   **Blocked by:** 无。**What it delivers:** 输入 AK/SK 后由手机及 Watch 直接签名查询 Coding 和 Agent Plan。

40. **[StepFun 套餐与网页登录](issues/40-stepfun.md)**

   **Blocked by:** 无。**What it delivers:** 在 iPhone 完成 StepFun 网页登录，将账户会话同步后由 Watch 独立查询套餐。

41. **[小米 Coding Plan 套餐与余额](issues/41-xiaomi-coding-plan.md)**

   **Blocked by:** 40。**What it delivers:** 从 iPhone 登录 MiMo 控制台后在双端查看月度额度与余额。

42. **[Qoder 国内版网页登录与额度](issues/42-qoder.md)**

   **Blocked by:** 40。**What it delivers:** 用户添加 Qoder 国内站账号后在手机和 Watch 查看个人与团队 credits。

43. **[Ollama Cloud 账户额度](issues/43-ollama-cloud.md)**

   **Blocked by:** 40。**What it delivers:** 从 iPhone 登录 Ollama 后在双端查看云端账号额度窗口。

44. **[Devin 网页账户额度](issues/44-devin.md)**

   **Blocked by:** 40。**What it delivers:** 从 iPhone 登录 Devin 后在双端直接查询每日和每周额度。

45. **[Abacus AI Compute points](issues/45-abacus.md)**

   **Blocked by:** 40。**What it delivers:** 从 iPhone 登录 Abacus 后查看 compute points 额度与账期日期。

46. **[Augment Code 当期 credits](issues/46-augment.md)**

   **Blocked by:** 40。**What it delivers:** 从 iPhone 登录 Augment 后在双端查看本账期 credits。

47. **[LongCat Token 包与燃料包](issues/47-longcat.md)**

   **Blocked by:** 40。**What it delivers:** 登录 LongCat 后查看当前 Token 包和补充燃料包。

48. **[Manus 每日与每月 credits](issues/48-manus.md)**

   **Blocked by:** 40。**What it delivers:** 登录 Manus 后查看每日恢复额度、月度额度与总 credits。

49. **[Mistral API 与 Vibe 额度](issues/49-mistral.md)**

   **Blocked by:** 40。**What it delivers:** 登录 Mistral 后查看 API、Vibe 额度及钱包余额。

50. **[Notion AI 工作区额度](issues/50-notion-ai.md)**

   **Blocked by:** 40。**What it delivers:** 登录 Notion 并明确选择工作区，在双端查看该工作区的滚动与账期额度。

51. **[Perplexity API credits](issues/51-perplexity.md)**

   **Blocked by:** 40。**What it delivers:** 从 iPhone 登录 Perplexity 后查看 API credits 余额。

52. **[Qwen Cloud 套餐额度](issues/52-qwen-cloud.md)**

   **Blocked by:** 40。**What it delivers:** 登录 Qwen Cloud 后在双端查看 5 小时、每周和每月套餐额度。

53. **[Raycast AI credits](issues/53-raycast-ai.md)**

   **Blocked by:** 40。**What it delivers:** 从 iPhone 登录 Raycast 后查看 AI credits 使用和续期时间。

54. **[Replicate 预付钱包](issues/54-replicate.md)**

   **Blocked by:** 40。**What it delivers:** 登录 Replicate 后查看预付余额并配置低余额提醒。

55. **[Sakana AI 额度与余额](issues/55-sakana.md)**

   **Blocked by:** 40。**What it delivers:** 登录 Sakana 控制台后查看 5 小时、每周额度及明确标币种的余额。

56. **[T3 Chat 多周期额度](issues/56-t3-chat.md)**

   **Blocked by:** 40。**What it delivers:** 登录 T3 Chat 后在双端查看四小时和月度额度。

57. **[TypeSafe 余额与套餐](issues/57-typesafe.md)**

   **Blocked by:** 40。**What it delivers:** 用户在手机建立 TypeSafe 控制台会话后查看余额与套餐。

58. **[Zed 编辑预测与支出限额](issues/58-zed.md)**

   **Blocked by:** 40。**What it delivers:** 登录 Zed 网页账户后查看编辑预测用量与实际配置的支出上限。

59. **[ZoomMate credits 预算](issues/59-zoommate.md)**

   **Blocked by:** 40。**What it delivers:** 登录 Zoom 后在双端查询 ZoomMate credits 预算和账期。

60. **[Cursor 移动端授权与额度](issues/60-cursor.md)**

   **Blocked by:** 无。**What it delivers:** 从 iPhone 完成 Cursor 账号登录后在双端查看 Cursor Models 和其他模型额度池。

61. **[Grok Bot 独立周额度](issues/61-grok-bot.md)**

   **Blocked by:** 60。**What it delivers:** 使用 Cursor 账号授权后，在独立 Grok Bot 卡片查看其每周额度。

62. **[Windsurf 网页额度](issues/62-windsurf.md)**

   **Blocked by:** 44。**What it delivers:** 从 iPhone 登录 Windsurf 后在双端查看每日和每周额度。

63. **[Gemini 移动端独立授权可行性](issues/63-gemini.md)**

   **Blocked by:** 无。**What it delivers:** 验证不借用 CLI 短期 token 的 Google 授权、续期和各模型额度查询。

64. **[Kiro 远程额度查询可行性](issues/64-kiro.md)**

   **Blocked by:** 无。**What it delivers:** 验证能否在不运行 Kiro CLI ACP 的情况下由手机和 Watch 查询订阅额度。

65. **[Antigravity 独立查询可行性](issues/65-antigravity.md)**

   **Blocked by:** 无。**What it delivers:** 验证是否存在脱离编辑器语言服务器的远程额度与授权路径。

66. **[Alibaba Token Plan 移动端可行性](issues/66-alibaba-token-plan.md)**

   **Blocked by:** 无。**What it delivers:** 验证无需 bl CLI 的登录、地区绑定与 Token Plan 查询。

67. **[Nous Portal 独立会话可行性](issues/67-nous-portal.md)**

   **Blocked by:** 无。**What it delivers:** 验证用户可为 TokenPulse 建立独立 Nous 会话并查询授予及购买的 credits。

68. **[JetBrains AI 远程额度可行性](issues/68-jetbrains-ai.md)**

   **Blocked by:** 无。**What it delivers:** 验证是否存在不依赖 IDE 本地额度文件的账户级查询。

69. **[OpenAI API 钱包可用接口验证](issues/69-openai-api.md)**

   **Blocked by:** 无。**What it delivers:** 核验当前可用凭证能否获取真实预付余额，并明确余额与组织花费的边界。

## 批准与执行顺序

- 用户于 2026-10-02 批准 69 张票的完整范围、粒度和阻塞关系。
- 按依赖推进：12 → 13/14/15/37；40 → 41–59；44 → 62；60 → 61。
- 初始可领取 44 张：01–12、16–36、38–40、60、63–69。这些票之间没有强制前后顺序。
- 63–69 是可行性验证票；通过后才另拆对应正式接入实施票，不将调查结论当成已接入。
- 每张票的验收清单与状态为执行依据；保持尚未完成的条目未勾选。

## Coverage

77 个上游 provider = 本地已有 9 个 + 未接入 68 个。69 张 tickets = 68 个未接入项 + Qoder 国内站扩展；62 张接入候选 + 7 张可行性验证。

未对 CLIProxyAPI 与上游 LLM API Key Proxy 作兼容性假设；能代理模型调用不等于实现同样的额度查询契约。
