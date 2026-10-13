# TokenPulse 国际化：简体中文与英文

状态：实施中。用户在审阅规格、10 票拆分并补充英文术语偏好后指示“继续”；据此记录批准，发布本地规格与逐票工单，当前01、03、04、06、07完成，02、05、08、09验收收尾，10只读覆盖预检已准备。

## Problem Statement

TokenPulse 的界面、额度状态、授权指引与通知目前大量直接使用中文。系统区域设置已经参与部分数字和日期格式化，但没有完整的翻译资源，英文用户难以完成服务账号配置和理解提醒。不同入口可能出现中文、英文与硬编码单位混用；如果直接翻译已存储的窗口名称或使用名称匹配业务规则，还可能影响缓存、通知去重和服务账号身份。

## Solution

建立可扩展的本地化基础，首期交付简体中文（zh-Hans）和英文（en），覆盖 iPhone、Apple Watch、两端小组件、辅助功能及应用生成的通知。语言遵循各设备的系统与应用语言选择，日期、数字和货币格式遵循适用的区域设置。未支持的语言回退英文；中文用户继续看到完整中文体验。

首期采用简体中文与英文，其他语种暂不纳入。中文界面允许保留 API Key、Token、OAuth、Provider 等常用英文术语以及品牌和模型名；操作、说明和错误提示仍使用中文。这些英文术语不算漏翻译，不为全中文而生硬翻译。首期不加入自建语言选择器。翻译仅改变展示，不改变提供商身份、服务账号、额度语义、金额、凭证、同步或提醒历史。Codex 重置预告保留“没有有效预告就整块隐藏”的现有行为。

## User Stories

1. As an English-speaking user, I want the app navigation in English, so that I can find accounts and settings.
2. As a Simplified Chinese user, I want complete Chinese translations, so that internationalization preserves my existing experience.
3. As a user of an unsupported language, I want a complete English fallback, so that I never see raw localization keys.
4. As an iPhone user, I want the app to follow my effective system or app language, so that I can use my preferred language without another setting.
5. As an Apple Watch user, I want text to follow my watch’s effective language, so that my watch remains independently usable.
6. As a multilingual user, I want devices with different languages to share the same service accounts, so that presentation does not change my data.
7. As a new user, I want localized empty states and demo entry points, so that I understand how to begin.
8. As a user adding a service account, I want localized field labels, validation and authorization instructions, so that I can connect a provider correctly.
9. As a user completing device authorization, I want translated guidance with unchanged verification codes and URLs, so that authorization continues to work.
10. As a user selecting a provider, I want recognizable brand names and multilingual search aliases, so that I can find the same provider in either language.
11. As a user browsing providers, I want sorting and section navigation to match the displayed list, so that the alphabet index lands in the correct section.
12. As a user managing multiple service accounts, I want my custom account names preserved verbatim, so that I can recognize my accounts after switching languages.
13. As a quota user, I want localized period and status labels, so that I can distinguish short-period, weekly and monthly allowances.
14. As a quota user, I want missing, unlimited, exhausted and stale states translated distinctly, so that unknown data is never mistaken for zero or available quota.
15. As a wallet user, I want localized monetary formatting with the actual currency identified, so that regional settings do not imply currency conversion.
16. As a service-credit user, I want points and provider-specific units preserved accurately, so that non-monetary balances are not presented as cash.
17. As a budget user, I want budget and wallet terminology to remain distinct in both languages, so that I do not confuse spending limits with available money.
18. As a user checking recovery times, I want localized dates and times, so that I understand when to check again.
19. As a user viewing date-only boundaries, I want the original calendar date preserved across time zones, so that formatting does not invent a reset time or shift the date.
20. As a user reading counts, I want correct singular and plural forms, so that messages sound natural for zero, one and many items.
21. As a user with regional number preferences, I want correct separators and percentage formatting, so that displayed usage remains readable and numerically accurate.
22. As a user receiving quota alerts, I want localized titles and bodies, so that I can understand the affected service account and quota window.
23. As a user receiving low-balance reminders, I want localized amounts and currency descriptions, so that I understand the threshold that was reached.
24. As a user receiving reset reminders, I want expected and confirmed resets distinguished in my language, so that a forecast is not presented as a verified recovery.
25. As a user changing language, I want future pending reminders updated without duplicate alerts, so that switching language does not reset notification history.
26. As a user following Codex reset announcements, I want localized explanatory labels while source text remains attributed and unchanged, so that I can distinguish app guidance from third-party statements.
27. As a user without an active Codex reset preview, I want its entire section hidden in either language, so that an empty announcement does not consume space.
28. As a widget user, I want localized widget names, configuration, placeholders and quota states, so that widgets are useful outside the main app.
29. As an Apple Watch complication user, I want concise translated content, so that the limited display area remains readable.
30. As a VoiceOver user, I want translated accessibility labels, values and hints, so that controls and quota readings make sense when spoken.
31. As a user with larger text sizes, I want longer translations to fit or wrap appropriately, so that important information and actions remain available.
32. As an offline user, I want cached quota data presented in the current language, so that switching language does not require provider access.
33. As an existing user upgrading the app, I want stored accounts, authorizations and reminder records preserved, so that internationalization does not require reconnecting providers.
34. As a user encountering a failure, I want localized recovery guidance, so that I can distinguish authorization, network, storage and synchronization problems.
35. As a maintainer, I want missing translations and malformed interpolation detected before release, so that adding a provider does not silently reintroduce mixed-language UI.

## Implementation Decisions

- **First delivery:** deliver zh-Hans and en as complete supported languages. Additional translations are separate follow-up work. Respect effective device/app language and locale; language is a device presentation preference rather than a synchronized service-account property.
- **Native resources:** use Xcode String Catalog resources and platform localization facilities, packaged for all applicable app, Watch and widget targets. Do not introduce an external translation service or custom localization framework.
- **Ownership:** views localize interface text; shared presentation/formatting responsibilities localize domain descriptions and values; notification planning/runtime localize generated notification content. Reuse these existing responsibilities instead of duplicating translations per provider or surface.
- **Stable identity:** provider identifiers, account identifiers, quota-window identifiers, credential scope, enum raw values, persistence keys and notification deduplication identities must remain independent of displayed language. Audit places that currently compare human-readable names or units before changing their presentation.
- **Existing data:** canonical semantic values stay stable; application-generated cached labels should resolve through semantic identity when available. Any compatibility handling must read existing snapshots without losing data, relogging in, rearming alerts or changing quota-window identity. Unknown provider text stays verbatim rather than being guessed or destructively rewritten.
- **Translation boundary:** localize app-owned field names, units and guidance. Preserve user-entered account names, provider/model/plan brand names, organization identifiers, server addresses, credentials, authorization codes and third-party announcement text. Provider-specific technical units retain their actual meaning.
- **Dynamic strings:** use localized interpolation and plural variants for complete phrases. Avoid concatenating language-dependent fragments and avoid deriving translation keys from untrusted provider text.
- **Formatting:** use locale-aware numeric, percentage, monetary and date presentation. Preserve Decimal precision, explicit currency, real measurement units and unknown values. No exchange-rate conversion. Preserve date-only precision and calendar boundaries; a date-only field must never gain an invented midnight timestamp or a shifted calendar date.
- **Provider selection:** retain existing multilingual aliases, selected state, existing-account grouping and native section index. Ensure section labels, ordering and index targets agree for each supported language, without changing provider identities or icons.
- **Language changes:** on next activation/reload, visible app content resolves in the effective language without refetching credentials or quota. Widget refresh follows system scheduling. Reconcile only future pending local notifications with translated content, retaining identifiers, delivery times and reminder ledger semantics; do not replay delivered notifications or mark past events as newly detected. Notification scheduling equality must account for content changes where needed, not just date/window identity.
- **Watch:** preserve independent device-side refresh and device-local authorization chains. A language difference between phone and watch must not require the phone to translate or query on the watch’s behalf.
- **Codex previews:** translate app-owned announcement/forecast labels, attribution text, fallback/error text and notification wrappers. Preserve source content and source link; distinguish AI prediction from an announced reset and actual execution. Hide the entire preview section when there is neither a pending announcement nor an unexpired watch.
- **Accessibility and layout:** localize spoken descriptions as well as visible text. Validate English text expansion, Dynamic Type, small Watch layouts and small widgets while retaining native controls and the existing glass presentation.
- **Scope of modules:** account setup/settings, provider selection, authorization guidance, quota presentation, demo states, notification output, widget configuration/content and Watch presentation all participate. Provider HTTP contracts and query behavior do not change.

## Testing Decisions

- **用户范围更新（2026-10-13）：** 2026-10-13 用户明确指示“跳过这个”，豁免本轮 iPhone 与 Watch 的 VoiceOver 实际听辨及语音导航验收。此项记为用户豁免，未执行、未声称测试通过。已完成的辅助功能标签/AX 检查保留；不豁免普通 Watch 触控、Crown、滚动、表盘宿主或最终中文锁屏复验。

- **Accepted primary seam:** validate user-visible presentation and notification output from known service-account/quota state under explicit language, locale, time-zone and time inputs. Reuse shared quota formatting/presentation and notification planning/runtime entry points; do not create separate public interfaces for every translated label or provider.
- **Good tests:** assert externally meaningful outcomes—readable supported-language text, correct amount/date semantics, preserved identity, notification behavior and usable controls. Avoid asserting catalog implementation structure, internal function calls or duplicating every translation as a unit-test expectation.
- **Prior art:** extend the project’s wallet presentation, quota date-precision, decimal-count, platform/widget and notification behavior tests. Use existing account-monitor scenarios where language changes interact with restored snapshots. Existing Codex reset-feed tests supply preview expiry and notification-deduplication scenarios.
- **Language/locale matrix:** zh-Hans and en, including English with US and non-US regional conventions, Simplified Chinese regional formatting, unsupported-language fallback, and non-default time zones. Explicitly test date-only boundaries separately from actual instants.
- **Semantic cases:** zero/one/many reset counts; missing, unlimited and exhausted quota; stale/partial-failure states; multiple currencies; non-monetary service credits; unknown units; fractional Decimal values; unchanged provider/organization/model names and account names.
- **Notifications:** verify localized titles/bodies, settings gates, no duplicate delivery after language changes, future pending notification replacement retaining event identity/time, and immutable already-delivered history. Include Codex announcement/forecast distinction and expired-watch suppression.
- **Compatibility:** load existing saved state and reminder records, switch languages and verify that data, service-account identity, credential scope, quota thresholds, reset boundaries and deduplication behavior remain unchanged without network access.
- **Visual acceptance:** review the same representative app screens, authorization flows, Watch views and widget families in both languages, including long text and large accessibility sizes. Check taps, section index, VoiceOver output and empty-preview hiding. Use demo/fixture data without exposing real credentials.
- **Resource/build check:** verify complete translations and interpolation/plural consistency for app-owned strings, distinguishing proper names and third-party content from missing translations. Build app, Watch and both widget targets to verify resource inclusion; preserve existing provider regression checks where affected.
- **Status:** these acceptance boundaries accompany the approved ticket breakdown; tests for this feature have not yet been implemented or run. User-approved English technical terms must not be flagged as untranslated text.

## Out of Scope

- Languages beyond Simplified Chinese and English in the initial delivery; full RTL layout certification belongs to a later language rollout, while the design should not hardcode text-direction assumptions.
- An in-app language picker or synchronization of one device’s language preference onto another device.
- Machine translation of provider responses, external webpages, announcements, user-entered names or credentials.
- New providers, changed API contracts, authentication/sync redesign, currency conversion, quota recalculation or server-side push infrastructure.
- A new visual design, changed navigation structure, altered notification thresholds or republishing old notifications.
- App Store marketing translations, website/documentation translation and a TestFlight/App Store release as part of writing this specification.

## Further Notes

- The user requested internationalization and creation of a specification; implementation has not been requested in this step.
- Existing project records establish repository-local tickets and the `ready-for-agent` state. This specification and its ten tickets follow that local convention; no GitHub issues were created.
- The device-side-refresh architectural decision remains in force: no Mac relay, translation backend or new external push service.
- Codex reset integration and empty-preview hiding are current working-tree changes. The specification must include them as part of the product surface without treating them as already committed or published to TestFlight.
- Language and locale can differ. Consistent translation does not mean forcing identical date/number formatting on every device, and language changes must not change the underlying quota data.
