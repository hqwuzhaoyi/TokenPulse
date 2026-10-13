# Neuralwatt

直接 Key 查询 https://api.neuralwatt.com/v1/quota。订阅 kWh、Key USD 支出限额与 USD 预付余额分别保存和显示；货币与数量使用 Decimal，缺失赠送/充值明细保持 nil。余额可为负，不把实际欠额改为零。只有明确 kwh_included 时绘制套餐百分比；旧二手实现的 used+remaining 推算总量未启用，符合票据“明确提供总额”的边界。

公开一手仓库 neuralwatt/neuralwatt-tools（873e63e15309e64c558a88ac82e8f1fde8f1328c）确认官方服务及 API base；quota 形状仍引用 [Pulse 397c8fc4](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/neuralwatt.md)，不是实际账号捕获。官方 tools tree 无可用品牌 SVG，采用原生 bolt.circle 通用能量图形。

测试覆盖三个计量系统、精度/负余额、未知字段、请求、混合 Widget 和独立提醒。真实账号、Watch 与 iCloud 尚未验收。
