# TokenPulse

**简体中文** · [English](README.en.md)

在 iPhone 和 Apple Watch 上，一处查看 **78 个 AI Provider** 的套餐额度与余额。

**[通过 TestFlight 安装](https://testflight.apple.com/join/jrHbrKmH)** · iOS 17+ · watchOS 10+

## 功能

- **多服务、多账号**：查看套餐额度、API 钱包、预算、服务积分和 GPU 时长；通过搜索与分组快速找到 Provider。
- **额度与余额提醒**：按账号设置额度阈值、低余额和重置提醒。
- **Codex 重置预告**：接入 [Codex Resets](https://codex-resets.com/)，提供重置公告与预测提醒；没有有效预告时自动隐藏。
- **Apple Watch 与小组件**：设备取得所需授权后可独立刷新，支持 iPhone 主屏幕、锁屏、Watch 表盘和智能叠放。
- **中英文界面**：跟随设备语言，日期和数字按区域设置显示；保留 API Key、Token、OAuth 等常用术语。
- **可选 iCloud 同步**：同步账号配置与额度数据，凭证保存在 Keychain；部分服务需要每台设备独立授权。

## 开始使用

1. 安装后点击 **体验演示**，无需账号或 API Key 即可试用。
2. 点击 **＋**，搜索 Provider，按提示登录或填写 API Key。
3. 在 **设置** 中开启需要的通知和同步，再添加小组件；Watch 可通过齿轮入口选择表盘账号。

后台刷新、同步和组件更新由系统调度，不保证提醒即时到达。Codex 的 AI 重置预测不代表官方承诺。

## 提供商与登录方式

包括 Claude、Codex、GitHub Copilot、Cursor、Gemini、Kiro、Kimi Code、DeepSeek、MiniMax、智谱、OpenCode、New API 等。

→ [完整 Provider 列表与登录要求](docs/providers.md)

## 本地开发

使用 **Xcode 26.x / Swift 6** 打开项目，为各 target 配置自己的开发团队、App Groups、Keychain Sharing 和 iCloud。

```sh
git clone https://github.com/hqwuzhaoyi/TokenPulse.git
cd TokenPulse
open TokenPulse.xcodeproj
```

选择 `TokenPulse` 或 `TokenPulseWatch` scheme 运行。详见 [构建与测试说明](docs/development.md)。欢迎提交 Issue 或 PR。

## 许可证与致谢

代码采用 [Apache License 2.0](LICENSE)。第三方资源的来源与许可见 [NOTICE](NOTICE) 和 [图标声明](TokenPulse/Resources/ProviderIconNotices.txt)。

感谢 [Pulse](https://github.com/qunqin24/Pulse)、[Lobe Icons](https://github.com/lobehub/lobe-icons) 和 [OpenAI Codex](https://github.com/openai/codex)。

## 社区与友链

有想法、功能建议或使用问题，欢迎加入 [Telegram 交流群](https://t.me/+pxMdrhguRVkyZGFl)，一起聊聊。

[LINUX DO 社区](https://linux.do/)
