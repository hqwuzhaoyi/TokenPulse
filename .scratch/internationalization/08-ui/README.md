# Watch Simulator QA

Device: `8FE5402A-2B44-4AB3-8A13-EF6E9279C33C`, TokenPulse i18n Watch, SE 3 40mm, watchOS 26.5, 324×394 pixels. Dedicated simulator created by central lead. No user old device was erased or changed. No physical Watch was tested.

`capture-results.json` records actual simctl launch argument lists, process IDs and screenshot return codes; `capture.py` reproduces capture of the isolated Debug fixtures. Baseline images used `/tmp/tokenpulse-i18n-watch-fixture.app`. All 12 captured baseline fixtures (en/zh-Hans × empty/long/long-large/error/nous/jetbrains), plus initial demo and Nous images, were opened with view_image and inspected.

## Observed baseline results

- Both language resources render real Watch views. Brand names and the sample user account name appear verbatim. The initial Nous screenshots do not yet show a code because no Start tap completed.
- The mixed-language long account name wraps at normal size. At maximum accessibility size, content is much taller than the screen; those pages already use native ScrollView. Actual scroll gestures have not been completed.
- Nous initial instruction appears in both languages. Chinese Start button is on the initial viewport; English Start is below the long instruction. JetBrains native Form wraps the instructions and continues below the screen.
- English empty-state button appeared partly below the initial viewport. Added an explicit native ScrollView around the existing ContentUnavailableView so it can be reached by scrolling. No action was added.
- The baseline Gauge showed truncated `5-Ho...` / `5 小...` text and its left edge touched the display boundary. The minimal fix moves window text to a wrapping caption above the Gauge and adds 8pt horizontal padding. VoiceOver remains on the Gauge with full localized label/value. Fix screenshots are pending the lead's rebuilt app.
- Old `error` fixture initial screenshots do not expose the error label because it is farther down the page. Added Debug-only initial scroll-to-label for state inspection; no gesture is claimed.
- Added `nous-waiting` Debug fixture, using the original NousDeviceLoginModel.start with the existing pure stub, and initial scroll-to-code. This tests real waiting layout without claiming that Start was tapped.

## Native touch investigation — failed, no tap success

No registered CUA tool was available. `simctl io` on this Xcode supports enumeration, screenshot/video and screen configuration, with no tap/swipe command. No idb/idb_companion/fbsimctl/maestro/cliclick/AXe was installed. The local watchOS runtime developer framework directory contains StoreKitTest, not a Watch XCTest UI runner framework. Mac auxiliary access was already reported denied by the lead; it was not changed or requested here.

Local ObjC runtime inspection found Apple's SimulatorKit `SimDeviceLegacyHIDClient` and exported `IndigoHIDMessageForMouseNSEvent`. A scratch diagnostic tool selected only the dedicated Watch UUID and attempted native touch-down/up and swipe events. Every attempted send returned `SimulatorKit.SimDeviceLegacyHIDClient.HIDError.machPortInvalid`; **no event completed, no button action or scroll is counted as tested**.

An attempted connection of the Watch LegacyHID port observed a CoreSimulatorService connection interruption and the Watch transitioned to Shutdown. The investigation was stopped immediately; the lead was notified. Only the dedicated Watch was rebooted; no other device was shut down or erased. A subsequent normal simctl launch/capture batch succeeded. The failed diagnostic source is labelled do-not-run and is not a supported helper. No more private port attempts are authorized by this workflow.

Relevant diagnostic files: `inspect-hid.m`, `hid-runtime-methods.txt`, `simulatorkit-disassembly.txt`, `watch-hid.m`. The helper's stderr failures are preserved in tool/session evidence; stdout event logs have no success lines. A native ObjC exception from one signature probe generated `/Users/wuzhaoyi/Library/Logs/DiagnosticReports/tokenpulse-watch-hid-2026-10-12-001718.ips`. No change to product auth or query code resulted from this investigation.

## Remaining actual interaction and accessibility checks

Use the dedicated Watch window in Simulator with normal human mouse/crown controls, or a supported CUA/HID provider that can target this device without changing Mac access settings.

1. Launch en/zh-Hans `empty`, scroll to Try Demo, click it, then Complication Settings → Exit Demo; verify original empty state returns.
2. Launch `demo`, scroll to Refresh, click, and verify local demo values update with the same account identity. Swipe between Claude, wallet and Codex pages; open settings, choose another complication account, verify the selected checkmark and preserved account IDs.
3. Launch `error`, inspect the cached data and credential recovery label, click Refresh and verify DemoQuotaClient clears failure; this is separate from the fixture's initial programmatic viewport.
4. Launch `nous`, scroll if needed, click Start Authorization; verify original model produces TEST-CODE, host and waiting state. Click Open Authorization Page (fixture handles URL with no external network), then Cancel; no credentials are saved.
5. Launch `long` plus `-TokenPulseWatchLargeType`; scroll through the full unchanged user name, quota values and actions. Verify native hit targets and content remain usable at 40mm.
6. Turn on VoiceOver on a disposable test context only if separately authorized, or use a supported accessibility inspector: listen to full Gauge name/state, refresh progress/hint, selection state and TEST-CODE. Source labels were added, but no VoiceOver listening or complete accessibility-tree review was performed here.

XCTest model/cache assertions and screenshot checks do not replace these actions. 08 cannot be reported as fully touch/VoiceOver accepted from these baseline images alone.

## Verified artifact recheck

Central lead supplied `/tmp/tokenpulse-i18n-watch-verified.app`, with its debug dylib timestamp 2026-10-12 00:25:07 (after final source timestamp 00:23:02), following unsigned `08-layout-build.log` BUILD SUCCEEDED. Installed once on the same dedicated Watch. `installd` reported successful install at 00:26:51; the delayed request completed without a reinstall or device reset. A separate terminate request raced the successful installation and returned `found nothing to terminate`; no other device was targeted.

`capture-verified-results.json` records 14 successful actual launches/screenshots. All 14 images were opened with view_image: en/zh-Hans × demo/empty/error/nous-waiting/nous-waiting-large/long-large/jetbrains.

- `verified-en-demo.png` and `verified-zh-Hans-demo.png` confirm the Gauge fix: full `5-Hour Quota` / `5 小时额度` captions, inset uncut ring, same 36% sample usage.
- `verified-en-nous-waiting.png` / `verified-zh-Hans-nous-waiting.png` confirm the original Nous model plus stub produces the displayed TEST-CODE, translated native Open Authorization Page button and original host. This is programmatically loaded state, not a successful Start tap. Complete wait label / Cancel controls remain below this viewport.
- `verified-*-empty.png` show translated native unavailable content. The source now provides native ScrollView; actual scrolling to the partially visible Try Demo action remains untested.
- `verified-*-long-large.png` confirm the root large-type override and unchanged mixed-language user name, with content continuing below the screen. No lost data is inferred from a single viewport, and scroll usability remains unverified.
- `verified-*-error.png` still show the page header: the outer Debug ScrollViewReader did not move through TabView/Timeline to the footer. These images cannot count as visual confirmation of the credential error label.
- Waiting normal and large screenshots show the same font/layout (apart from clock/spinner state), so the modal large-type override was not visibly confirmed. Reported to the lead for an explicit Debug sheet environment if further verification is pursued.
- JetBrains native instructions remain readable and wrap in both languages; the rest of the form requires actual scrolling.

The remaining interaction, modal large-type and footer-view gaps remain explicit. No additional private HID experiment was made after the stop decision.

## Pending Debug viewport correction

The lead authorized two minimal fixture changes after the recheck: the `error` route now directly reuses private WatchAccountPage via a Debug-only factory and places its ScrollViewReader inside that route, with the same observed monitor and Refresh callback. The waiting/import sheet explicitly receives fixtureTypeSize instead of relying on modal inheritance. Production code paths, native semantics and authorization/query implementation are unchanged. Parse/diff checks passed; another real rebuilt-artifact capture is required before these two missing visual checks can be accepted. No additional HID investigation was started.

## Final viewport recheck

The next stable artifact `/tmp/tokenpulse-i18n-watch-final.app` had dylib timestamp 00:33:41, after source 00:33:23. Six actual launches/screenshots all returned 0 and were inspected with view_image (`capture-final-results.json`): en/zh-Hans × error/nous-waiting/nous-waiting-large.

- `final-en-error.png` and `final-zh-Hans-error.png` now show the real credential recovery label, collected time and Refresh action from WatchAccountPage. The direct production-page fixture fixed the footer viewport problem.
- `final-*-nous-waiting-large.png` now visibly use much larger type than the corresponding normal screenshots. The explicit modal environment fixed the inherited-font problem.
- At maximum type size, all code characters remained present but TEST-CODE wrapped (English at the hyphen, Chinese after D). With the lead's explicit approval, the code Text now uses `.lineLimit(1).minimumScaleFactor(0.5)` to keep it on one line; raw code, accessibilityValue and authorization behavior stay unchanged. Parse/diff checks pass; final enlarged-code screenshot recheck awaits the next central artifact.

Actual tap/scroll actions, full AX tree and VoiceOver listening remain unexecuted. These successful viewport fixes do not erase the remaining device-operation gaps described above.

## Code display final verification — frozen

The final stable artifact `/tmp/tokenpulse-i18n-watch-code-final.app` has dylib timestamp 2026-10-12 00:50:34 and includes the single-line code fix (source 00:37:59). It was installed once on the same dedicated Watch. `capture-code-final-results.json` records two actual successful launches and screenshots, each exit 0. Both were opened with view_image:

- `code-final-en-nous-waiting-large.png`
- `code-final-zh-Hans-nous-waiting-large.png`

**Both show the complete TEST-CODE on one line at maximum fixture accessibility size, with no truncation.** The translated native authorization-page action remains readable and wraps at large type. Raw model code and accessibilityValue were not changed. No build or private HID operation was run for this final check.

Report frozen. Visual fixes confirmed: Gauge full caption/inset ring; both-language credential error footer; modal large type; complete single-line enlarged code. Baseline and intermediate failures remain in this record. Remaining unpassed device acceptance: actual tap/crown/swipe/scroll actions, account-selection interaction, empty-state Demo/Exit interaction, refresh/cancel/open action interaction, full AX-tree review and VoiceOver listening. Source/model tests and programmatically positioned fixtures do not count as those operations. Human reproduction steps above remain applicable.


## 2026-10-13 Computer Use 恢复后的实际交互

见 [本轮记录](../08-cua-recheck.md)。两语实际演示/刷新/授权开始与取消已通过，旧完全未触控状态已被部分补验；剩余边界仍保留。
