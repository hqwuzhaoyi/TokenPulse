# 63: Gemini Code Assist 原生授权与模型额度

**Status:** done

**Type:** integration

**What to build:** 自备 Google iOS OAuth client 的原生 PKCE 授权、离线刷新、项目发现和各模型 quota；不借用 CLI token/client/secret。

**Configuration prerequisite:** 用户在 Google Cloud 注册自己的 iOS OAuth client，bundle `com.tokenpulse.app`，配置授权同意与所需 scopes；需要可用 Code Assist 账户及服务认可的已激活项目。项目可手填，或采用服务返回的 managed project。强制 App Check / DPoP client 配置尚不支持。当前机器没有 client 注册和真实账号，不是实现验收门槛。

## Acceptance criteria（当前用户：实现 + 图标）

- [x] `.gemini` 注册与自备 client ID/project 表单，ASWebAuthenticationSession 动态 reverse-client callback、S256 PKCE、state/expiry/path/host/重复参数检查，不使用 WKWebView/loopback/OOB。
- [x] 官方 3 scopes，token endpoint 无 client secret，userinfo subject 绑定，标准省略 scope 的同授权处理，显式减少权限拒绝；离线 refresh 保留或更新 refresh token。
- [x] `loadCodeAssist`/`retrieveUserQuota` 直接 HTTPS，metadata 如实 UNSPECIFIED + TokenPulse，完整账户设置后才查询；不 onboard、不创建项目、不冒 CLI。
- [x] subject + client + 实际 project + local account 形成稳定 identity，token 更新不切 scope；新 client/project/subject/local account 不能复用旧 scope 缓存。
- [x] 每模型 limiting bucket 与其 reset 绑定，无假分母/ProFlash 合池/猜 24h；严格 fraction/amount/time，amount-only 保留 exact partial，不变成 fake0。
- [x] 多账号与替换/删除/缓存/提醒走既有 runtime；Watch 用已配置 public OAuth refresh 直接 HTTPS；App/Watch/widgets/demo 路由、PBX与图标许可齐全。
- [x] 6个共享授权回归 + 12个 Gemini 回归已添加；生产小模块 Swift6 语义检查及 iOS native UI typecheck 通过。完整 XCTest/build 由 root 集成统一执行，当前未声称通过。
- [x] 图标存在：Lobe Icons 固定 a94750e3… Gemini SVG，MIT、模板渲染与来源声明。
- [x] 不读取真实凭证、不借用 gh/CLI 登录、不使用远端代理。

## Evidence / 未进行的观察

[实施与来源报告](../research/63-gemini.md)。固定 Pulse `397c8fc4f1bd52180a452d2f3f0c099def97cf69` 和官方 Gemini CLI `fb972b2f87fe7d5b06d37eac711490162d98de2c`。

真实 Google 自备 client 注册、授权同意、quota entitlement、手机/Watch 跨 token 到期刷新、撤销和面板对照均未观察。服务可拒绝第三方 client，UI显示权限/支持错误；这些结果不能由合成 fixtures 证明。用户当前验收无需这些真实账号观察，不单独阻塞实现。

## Root 最终集成验证 — 2026-10-03

源码 `379d5dd` 已通过773项完整XCTest（0失败）及unsigned App/Watch/两端Widgets构建，本票图标映射存在。此前工作者“未跑完整Xcode”的描述是其交付时事实；本段记录root后续实际验证。当前实现+图标验收完成，真实账号/物理设备观察仍未伪勾。详见[第四批结果](../wave4-progress.md)与[Pi处理](../pi-wave4/README.md)。
