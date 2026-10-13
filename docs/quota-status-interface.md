# Provider-confirmed categorical quota state

`QuotaSnapshot.quotaStatusText` and the mirrored optional `WidgetAccountSnapshot.quotaStatusText` hold a static, provider-confirmed categorical state such as “the plan does not include a personal allowance”. Provider parsers choose fixed text from validated flags; never relay arbitrary HTML from a service. Older caches continue to decode without the field and the existing `isNoPlan` remains compatible.

The account card, detail/settings and Watch show the status alongside all numeric windows. Widget metrics use the categorical status when there are no actual windows; valid quota/wallet metrics remain visible when a status accompanies data, and the widget's account footer carries the status. A successful authoritative absence can therefore clear obsolete quotas while remaining a successful query/auth validation. Unknown or malformed replies must still fail, rather than becoming a categorical claim.

Persistence follows the existing complete snapshot and WidgetSnapshotStore state projection. The field does not change wallet partial-failure timestamps, credentials, periods or reset inference.
