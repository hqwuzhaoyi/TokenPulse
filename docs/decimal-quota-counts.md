# Exact quota quantities

`QuotaWindow.exactCounts` optionally retains `DecimalQuotaCounts(used:remaining:total:)` for provider amounts reported as decimal strings. Existing caches omit it and continue to decode. It is a quota/credit budget quantity, not a WalletBalance. Parsers perform validated Decimal arithmetic and may independently derive a finite Double percentage for gauges and quota alerts.

`QuotaFormatting.exactCountSummary` displays exact remaining/total amounts with the window's stated unit, without routing through Double. Cards, details, Watch and widgets share that text. Legacy Double count windows remain compatible. Exact quantities do not imply a currency or create reset dates; each provider still owns those decisions. The maximum supported significant digits is the Foundation Decimal limit; provider parsers must reject values they cannot represent faithfully.
