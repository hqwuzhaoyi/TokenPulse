# TokenPulse 隐私政策 / Privacy Policy

更新及生效日期 / Updated and effective: 2026-09-14

## 中文

本政策说明 TokenPulse 0.1.0 在 iPhone、Apple Watch 及小组件中的数据处理方式。隐私问题请联系 TokenPulse 开发者：**hqwuzhaoyi@gmail.com**。

### 1. 应用处理的信息及用途

TokenPulse 用于查看你主动连接的 AI 服务订阅额度。应用会在设备上处理和保存你设置的账号名称、提供商、账号或组织标识、订阅套餐、额度用量与重置时间、刷新时间和失败状态，以及排序、同步和提醒设置。这些信息用于展示额度、刷新账号、同步设备配置及发送本地提醒。

你输入或授权取得的 API Key、访问令牌、刷新令牌或会话凭证用于向对应服务认证。凭证存储在 Apple Keychain 中，不存入小组件额度快照或通知正文。第三方登录页面中输入的信息由相应提供商处理；TokenPulse 会保留完成额度查询所需的授权或会话凭证。

当前版本没有开发者运营的数据收集服务器，不内置广告、广告跟踪或第三方行为分析 SDK，也不会把你的凭证或额度数据发送到开发者服务器。应用不请求相机、麦克风、定位、通讯录或照片访问权限。

### 2. 第三方服务

当你添加、授权或刷新账号时，设备会通过 HTTPS 直接联系你选择的服务：Anthropic/Claude、OpenAI/ChatGPT/Codex、OpenCode Go、Z.ai、MiniMax 或 xAI/Grok。请求会携带该服务所需的凭证、账号或组织标识及查询参数；提供商也会接收到处理请求所需的网络信息，例如 IP 地址。TokenPulse 不会将某家服务的凭证用于查询其他提供商。

这些服务由各自提供商运营，其登录、订阅、日志、保存期限及数据处理地区受各自隐私政策和账号设置约束。TokenPulse 中删除账号不会删除提供商的原始账号、订阅或服务端数据。你可以在提供商处撤销授权或删除 API Key。

### 3. 本机存储与 iCloud

账号配置、额度快照和提醒记录保存在设备上。iCloud 同步默认开启，可在「设置」中关闭。在 Apple 账号和设备设置允许时，账号配置、额度快照、提醒设置和提醒去重记录通过 Apple iCloud 同步；凭证使用 Apple 的可同步 Keychain 项在你的设备之间同步。这些数据不经过开发者服务器。

关闭应用内同步会停止本机主动发起的应用同步，但不会删除已存在于其他设备、iCloud 或 Keychain 中的数据。Apple 的存储、安全、备份和同步机制适用其自身条款及你的系统设置。

### 4. 提醒、小组件和 Apple Watch

应用会申请通知权限，以发送额度告警和重置提醒；你可在应用及系统设置中关闭通知。账号名称、额度和重置信息可能出现在通知中心、锁屏小组件、主屏幕或手表表盘上，其他能查看这些屏幕的人也可能看到。你可以移除小组件、调整账号选择或关闭通知预览。

### 5. 演示模式

演示模式使用本机示例账号和模拟额度，不需要真实服务凭证，也不会向第三方提供商查询或将演示数据同步至 iCloud。演示设置和示例数据使用独立本机存储；演示通知仍使用系统通知权限。退出演示会取消尚未触发的演示提醒，并恢复真实账号界面；示例数据可保留供下次演示使用。

### 6. 保存、删除及你的选择

账号数据在你使用功能期间保存在设备及已启用的 Apple 同步存储中。在 TokenPulse 删除账号会移除其活动额度缓存，并尝试删除对应 Keychain 凭证和取消待发送提醒；如清理失败，应用会提示重试。启用同步时，删除状态会在后续同步中传播。

为防止离线设备重新带回已删除账号，含删除时间的账号配置可能继续保留；历史提醒去重记录也可能保留。应用不会自动清除通知中心中已经送达的通知。卸载应用不保证删除 Keychain、Apple 备份或云端副本。你可以手动清除已送达通知、在第三方提供商撤销授权，并通过 Apple 系统设置管理同步与备份。如需了解本机残留记录的清理方式，可联系开发者；开发者不能远程访问或清除你的个人设备和 iCloud 数据。

### 7. 支持、诊断及政策网页

如果你主动发送支持邮件或反馈，开发者会收到你提供的联系方式和内容，用于答复及排查问题。请勿发送 API Key、密码或访问令牌。你可通过上述邮箱请求删除你提供的支持资料；请求将按适用要求处理。

Apple 可能根据你的系统、TestFlight 和诊断共享设置收集并向开发者提供崩溃报告、测试反馈及测试指标。TokenPulse 不额外内置行为分析 SDK。本政策网页由 GitHub 托管；访问网页时，GitHub 会按其自身隐私政策处理网页请求信息。

### 8. 政策更新

如果数据处理方式发生变化，本政策会更新并标明新日期。你可以通过上述联系方式询问本政策及相关数据处理问题。

---

## English

This policy describes how TokenPulse 0.1.0 handles information on iPhone, Apple Watch, and widgets. For privacy questions, contact the TokenPulse developer at **hqwuzhaoyi@gmail.com**.

### 1. Information and purposes

TokenPulse displays subscription quotas for AI services you choose to connect. It processes and stores account names you enter, providers, account or organization identifiers, subscription plans, quota usage and reset times, refresh timestamps and errors, and ordering, synchronization, and reminder settings. This information supports quota display, refreshes, device synchronization, and local notifications.

API keys, access tokens, refresh tokens, or session credentials that you supply or authorize are used to authenticate with the corresponding provider. Credentials are stored in Apple Keychain, not in widget quota snapshots or notification bodies. Information entered on a provider's sign-in page is handled by that provider; TokenPulse retains the authorization or session credentials needed to retrieve quotas.

The current app has no developer-operated data collection backend and contains no advertising, advertising tracking, or third-party behavioral analytics SDK. It does not send your credentials or quota information to a developer server. It does not request camera, microphone, location, contacts, or photo-library access.

### 2. Third-party services

When you connect, authorize, or refresh an account, your device contacts the selected provider directly over HTTPS: Anthropic/Claude, OpenAI/ChatGPT/Codex, OpenCode Go, Z.ai, MiniMax, or xAI/Grok. Requests include the credentials, account or organization identifiers, and query parameters needed by that service. Providers also receive network information needed to handle requests, such as your IP address. TokenPulse does not use one provider's credentials to query another provider.

Each provider operates its own service. Its privacy policy and your account settings govern sign-in, subscriptions, logs, retention, and processing locations. Removing an account from TokenPulse does not delete the provider account, subscription, or server-side data. You can revoke authorization or delete API keys with the provider.

### 3. Local storage and iCloud

Account configurations, quota snapshots, and reminder records are stored on your device. iCloud synchronization is enabled by default and can be disabled in Settings. When permitted by your Apple account and device settings, Apple iCloud synchronizes account configurations, quota snapshots, reminder preferences, and notification deduplication records. Credentials use Apple's synchronizable Keychain storage across your devices. This data does not pass through a developer server.

Turning off the app's synchronization stops locally initiated app synchronization; it does not delete existing data on other devices, in iCloud, or in Keychain. Apple's terms and your system settings govern its storage, security, backup, and synchronization services.

### 4. Notifications, widgets, and Apple Watch

The app requests notification permission for quota alerts and reset reminders. You can disable notifications in the app or system settings. Account names, quota information, and reset times may appear in Notification Center, lock-screen or home-screen widgets, and watch faces, where others viewing the screen may see them. You can remove widgets, change selected accounts, or disable notification previews.

### 5. Demo mode

Demo mode uses local sample accounts and simulated quotas. It requires no real provider credentials, makes no quota queries to providers, and does not synchronize demo data to iCloud. Demo data and preferences use separate local storage. Demo notifications still use system notification permission. Exiting cancels pending demo reminders and restores the real-account interface; sample data may remain for a later demo session.

### 6. Retention, deletion, and choices

Account information remains in local and enabled Apple synchronization storage while you use these features. Deleting an account in TokenPulse removes its active quota cache and attempts to delete its Keychain credentials and cancel pending reminders. The app offers a retry if cleanup fails. When synchronization is enabled, the deletion state propagates during subsequent synchronization.

Account configurations containing a deletion timestamp may remain to prevent an offline device from restoring a deleted account. Historical reminder deduplication records may also remain. The app does not automatically remove notifications already delivered to Notification Center. Uninstalling does not guarantee deletion of Keychain items, Apple backups, or cloud copies. You can clear delivered notifications, revoke provider access, and manage synchronization and backups in Apple settings. Contact the developer for information about clearing residual local records; the developer cannot remotely access or erase your personal device or iCloud data.

### 7. Support, diagnostics, and this webpage

If you voluntarily send support email or feedback, the developer receives the contact information and content you provide to respond and investigate. Do not send API keys, passwords, or access tokens. You may request deletion of support material you supplied by contacting the email above; requests are handled according to applicable requirements.

Depending on your system, TestFlight, and diagnostic-sharing settings, Apple may collect and provide crash reports, testing feedback, and testing metrics to the developer. TokenPulse includes no additional behavioral analytics SDK. GitHub hosts this policy webpage and handles webpage request information under its own privacy policy.

### 8. Updates

This policy will be updated with a new date when the described practices change. Contact the developer with questions about this policy or the handling of your information.
