# Central 1.11.0 静态证据复核

只读下载官方发布包；不安装、不启动它，也不读取 IDE、CLI state、Keychain 或任何用户凭证。两个 Go inspector 只使用标准库解析 ELF `.gopclntab` / `.typelink` / `.rodata`，先检查固定 binary SHA-256，拒绝其它输入。它们是本次编写并审阅的读取工具，不是从发布包运行的代码。两个文件应分别 `go run`，不能按目录一起构建（各自 main）。

```sh
mkdir -p /tmp/tokenpulse-jetbrains-static
curl -fsSL https://jetbrains-central-cli.s3.eu-west-1.amazonaws.com/central/1.11.0/central_1.11.0_linux_x86_64.tar.gz -o /tmp/tokenpulse-jetbrains-static/central_1.11.0_linux_x86_64.tar.gz
shasum -a 256 /tmp/tokenpulse-jetbrains-static/central_1.11.0_linux_x86_64.tar.gz
# archive 34c7e468870fdc57d60261034760f72b85c4a9e3f2dbfb9dec006b413f62ae4c
# First list entries: only README.md and central, no path traversal.
tar -tzf /tmp/tokenpulse-jetbrains-static/central_1.11.0_linux_x86_64.tar.gz
tar -xzf /tmp/tokenpulse-jetbrains-static/central_1.11.0_linux_x86_64.tar.gz -C /tmp/tokenpulse-jetbrains-static
shasum -a 256 /tmp/tokenpulse-jetbrains-static/central
# binary 07d76becc367762e31f59ecbf744a967ce5ef1cbf395b4fc05835e6fb244a042
go version -m /tmp/tokenpulse-jetbrains-static/central
go run .scratch/provider-expansion/research/68-static-tools/functions.go /tmp/tokenpulse-jetbrains-static/central > /tmp/tokenpulse-jetbrains-static/functions.json
go run .scratch/provider-expansion/research/68-static-tools/types.go /tmp/tokenpulse-jetbrains-static/central > /tmp/tokenpulse-jetbrains-static/types.json
```

`evidence.json`保存固定版本、字段/JSON tag 与相关函数的静态地址/原文件行号。可用已知系统 objdump 读取选定地址；不得运行 central 本体。例如（Apple LLVM objdump 支持本 ELF）：

```sh
objdump -d --start-address=0x8e2620 --stop-address=0x8e2760 /tmp/tokenpulse-jetbrains-static/central
objdump -d --start-address=0x8e3aa0 --stop-address=0x8e4620 /tmp/tokenpulse-jetbrains-static/central
objdump -d --start-address=0x8e2440 --stop-address=0x8e2620 /tmp/tokenpulse-jetbrains-static/central
objdump -d --start-address=0x8eb000 --stop-address=0x8eb080 /tmp/tokenpulse-jetbrains-static/central
```

这些片段分别是 GetQuota、platformPost、Refresh、canUseJBAIFastRefresh。RIP-relative 地址指向 ELF rodata 内的路径/头名称，后续寄存器值给字符串长度；不能把 strings 中拼接的相邻文本当作一条 URL。金额转换需要同时查看 jbai.init 的 `0x186a0`（100000）与 QuotaAmount.Credits 调用 decimal.Div；refill 单位则看 FormatQuotaPeriod 的除 1000 和余数乘 1000000 后构造 time（UnixMilli 展开），不是按日期数量级猜测。

2026-10-03 实际重复提取后，两个 inspector JSON 与首次临时结果完全相同。此检查验证固定 artifact/提取可复现，不验证服务器接受凭证、授权或真实 quota。


## 初始导入、签发和展示运算补核

2026-10-03追加工具不修改既有quota提取：

```sh
python3 .scratch/provider-expansion/research/68-static-tools/auth-chain.py /tmp/tokenpulse-jetbrains-static/central
# 读取固定ELF常量与全局function-value slot，逐项比较固定值；不执行Central。
go run .scratch/provider-expansion/research/68-static-tools/auth-types.go /tmp/tokenpulse-jetbrains-static/central
# 只解析OAuth/request-response type tags，与types.go独立运行。
```

`auth-chain-evidence.json`固定production host、client ID、path及import/签发/fallback函数引用；`auth-types-evidence.json`固定OAuthTokens与Token/ExpiresAt结构；`display-and-mint-evidence.json`保存相关函数边界、原源文件行号与指令bytes SHA-256，方便系统objdump独立对照。

展示语义不能从字段名字猜：`writeQuotaOutput`在`0xc423a8`读Quota.current(offset0x10)，`0xc423dc`读maximum(offset0x20)，分别除相同scale；`0xc424ec`将二者相除，转Float并乘100绘制usage bar。tariff offsets0x38/0x48/0x58和topUp offsets0x68/0x78/0x88依次进入“current / maximum credits used (available remaining)”行。`0xc42476`只把两段available相加为主行remaining。TokenPulse只显示明确分段，不把aggregate再重复算成另一份额度。`jbai.init`的`0x186a0`(100000)与Credits/上述DivRound共享global0x16d2270，支持精确AI credits缩放，不是美元。

ProvideAccess在`0x8e1fc8`先取now+24h（`0x4e94914f0000`纳秒），`0x8e1fe8...0x8e1feb`对expiresAt做test/jle：<=0沿该默认值，>0按毫秒epoch展开。24h是官方客户端默认策略，不是服务端精确expiry证明。实现统一用于初始/重签和direct refresh；正数过期/超界仍拒绝。
