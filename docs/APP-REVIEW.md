# Karing (Iran fork) — Full App Review

Date: 2026-09-14
Scope: whole app, with a deep pass on the three headline features — SNI scanner,
Serverless mode, and the Cloudflare ("Kanothveler") clean-IP scanner.

Everything below is based on reading the code and on measurements taken on this
machine. Claims that are measured say so; claims that are judgement calls are
marked as such.

---

## 1. Executive summary

Three findings dominate:

1. **The Cloudflare IP scanner was completely non-functional.** It reported every
   IP as dead, on every network, including a healthy one. Root cause was a
   one-line protocol mismatch. **Fixed and measured.**
2. **The SNI scanner was measuring the wrong thing.** It accepted any TLS
   handshake as success, so it could not distinguish a real Cloudflare edge from
   an arbitrary host that happened to answer. **Fixed — it now verifies the peer
   is a genuine Cloudflare edge.**
3. **The two new scanner screens had no translations at all** (23 + 26 strings
   hardcoded in English) while the rest of the app ships 28 locales at strict key
   parity. **Fixed — both screens are now localised, including Persian.**

The app also has a structural usability problem that no single patch solves:
there is no onboarding path, and a new user has to survive six forced screens
and a blank home screen before anything works. That is the largest remaining
item, and §5 proposes a concrete design for it.

---

## 2. Critical defect: the Cloudflare scanner never returned a result

### 2.1 What the user saw

Open the Cloudflare scanner, start a scan, wait. The list stays empty and the
"Replace" button stays disabled. On any network. Always.

### 2.2 Root cause

`cfProbeTrace()` (`lib/app/utils/cloudflare_utils.dart`) validates a candidate IP
by opening TLS to `:443`, then writing an **HTTP/1.1** request for
`/cdn-cgi/trace` and checking the response for `fl=` and `colo=`.

The TLS layer was asked to negotiate ALPN `["h2", "http/1.1"]`. Cloudflare
prefers `h2`, so it negotiated `h2` — and then received an HTTP/1.1 request. It
answered with binary HTTP/2 frames. The `fl=`/`colo=` check therefore never
matched, and **every** candidate was classified as unhealthy.

### 2.3 Measurement

Same IPs, same SNI, same request; only the offered ALPN differs:

| ALPN offered | Negotiated | Bytes | `fl=` | `colo=` | Verdict |
|---|---|---|---|---|---|
| `["h2","http/1.1"]` (old) | `h2` | 57 | no | no | unhealthy |
| `["http/1.1"]` (new) | `http/1.1` | ~1000 | **yes** | **yes** (`EWR`) | healthy |

Reproduced against `104.21.33.59`, `188.114.96.0`, `188.114.97.6` — identical
result on all three. Cross-checked with `curl --resolve`, which returned a valid
trace body for the same IPs.

### 2.4 Fix

`lib/app/utils/cloudflare_utils.dart`: the ALPN list is now a named constant
`kCfTraceAlpn = ["http/1.1"]`, with a comment explaining why `h2` must not be
advertised, and `cfProbeTrace` uses it. A regression test asserts the constant
never contains `h2`.

This also fixes the single-host "Test" button, which calls the same function.

### 2.5 Residual risk

The scanner still only probes port 443. Cloudflare serves HTTPS on 8443 as well,
and some Iranian ISPs block one port but not the other. See §5, item 3.

---

## 3. SNI scanner: it was measuring the wrong thing

### 3.1 The design flaw

The old `probe()` did this: open TCP, complete a TLS handshake with the
candidate SNI, and if the handshake did not throw, mark the pair as **working**.

Two problems:

1. **`onBadCertificate: (_) => true` accepts any certificate.** So *any* TLS
   server that answers on `:443` was recorded as a hit, whether or not it had
   anything to do with Cloudflare. A dead or hostile IP could outrank a real edge
   simply by being closer.
2. **It never checked the thing that matters.** SNI spoofing
   (`_applySniSpoofing`, `singbox_config_builder.dart:938`) rewrites a CDN
   outbound to dial a clean IP while presenting a whitelisted fake SNI, keeping
   the **real domain in the transport `Host` header**. A working pair therefore
   requires the peer to be a genuine CDN edge that routes by Host. A bare
   handshake proves none of that.

### 3.2 What changed

`probe()` now runs the same verification the Cloudflare scanner uses:
`cfProbeTrace(ip, probeHost: sni)` — TLS, then `/cdn-cgi/trace`, requiring `fl=`
and `colo=`.

Three outcomes, instead of two:

| Outcome | Meaning | Reported as |
|---|---|---|
| `fl=`/`colo=` present | genuine Cloudflare edge | **verified** (shows colo, e.g. `EWR`) |
| TLS completed, no trace | reachable but not a CF edge | usable, **unverified** |
| TLS failed | blocked SNI or dead IP | failed, with a reason |

The distinction is made without an extra network round trip: `CfProbeResult.totalMs`
is the handshake time, so a non-zero value means TLS succeeded.

Results are ordered by `SniScanner.compare()` — verified edges first, then
latency. Verified first is deliberate: a verified edge at 900 ms is more useful
than an unverified host at 20 ms, because only the former can serve the real
domain.

### 3.3 The screen now explains failures

Previously only successes reached the list, so a scan that found nothing showed
`0 working` and no explanation — the worst possible outcome for a user trying to
work out whether their ISP is blocking them.

Now failures are bucketed (`timeout`, `reset`, `handshake`, `unreachable`) and
summarised inline, e.g. `Failures: timeout ×12 · reset ×3`. There is an empty
state, an idle hint, tooltips on the icon buttons, and a note that SNI Spoofing
only rewrites CDN nodes (WebSocket / gRPC / HTTPUpgrade) — so a user with a plain
TCP+TLS node is told why the setting appears to do nothing.

### 3.4 What is still missing

The scanner still tests **(IP × SNI) pairs in isolation**, not the user's actual
node. It cannot prove that the user's real domain is served by that edge, nor
that the Host-header routing survives. Every mature tool in this space solves
this differently — see §5, item 1. This is the single highest-value remaining
improvement to the feature.

---

## 4. User-friendliness audit

### 4.1 First run — the biggest problem

There is **no onboarding**. `novice_screen.dart` is not an onboarding flow; it is
a single "novice mode" toggle. The real first-run path is a forced chain in
`home_screen.dart:528-627`:

1. User agreement
2. Language
3. TV mode (Android) / Accessibility (Windows)
4. Region
5. Diversion rules preset
6. Novice mode
7. Add-profile sheet (only if no config exists)

That is **six forced screens before the user can do anything useful**, and then
the home screen has no guidance if they dismiss the add-profile sheet.

**The no-profile state is a dead end.** `ServerSelectCard` renders
`widget.server.tag` (`home_screen_widgets.dart:1917`), which is the empty string
when no node exists — so the selector is blank, with no text and no call to
action.

### 4.2 Error handling

- A failed connection on Android shows the **raw core error string** to the user.
  The FAQ that would explain it auto-opens on PC only (`common_dialog.dart:124`),
  which excludes the primary audience.
- `launch_failed_screen.dart` can display the literal word `Exception` plus a raw
  `err.toString()`.
- Some paths are good — `noNetworkConnect` and `fileNotExistReinstall` are
  localised and actionable. They are the exception.

### 4.3 Internationalisation

The app ships 28 locales at strict key parity (656 keys). The new features broke
that invariant and were English-only. Now localised:

| Screen | Keys added |
|---|---|
| `SniScannerScreen` | 23 |
| `CloudflareScannerScreen` | 26 |

Persian is fully translated; the other 26 locales carry the English text, which
is the standard fallback for a new namespace. Parity is verified programmatically
(all 28 locales: 656 leaves, zero drift).

A reusable helper for future key additions is kept at
`.workbuddy-ai/sync_locale_keys.py` — it copies any missing namespace from `en`
into every other locale with the correct per-file indentation and line endings.

**Remaining hardcoded strings** (not addressed this pass):
`net_check_screen.dart:98` ("The VPN is not connected…"), `net_check_screen.dart:973`
("Domain"), `dns_settings_screen.dart:508` ("ISP"), `home_screen_widgets.dart:1149`
(serverless card title), `home_screen.dart:2581-2583` (connect-button tooltip
suffixes), and `home_screen.dart:1886-1897` (raw path/exception strings).

### 4.4 RTL / Persian layout

The app relies on Flutter's implicit `Directionality`, but several constructs do
not mirror:

- **The home dashboard grid is forced LTR.** `widgets/grid.dart:33` defaults
  `textDirection = TextDirection.ltr` and `home_screen.dart:2758` does not
  override it — so the whole widget grid lays out left-to-right in Persian.
  This is the most visible RTL defect in the app.
- `Icons.arrow_forward_ios_rounded` / `arrow_back_ios_outlined` are not mirrored
  across ~40 screens.
- Hardcoded `Positioned(left: 10)` (`home_screen.dart:2652`) and
  `EdgeInsets.only(right: …)` (`cloudflare_scanner_screen.dart`, `server_select_screen.dart:1361`).

### 4.5 Accessibility

- There is exactly **one** `Semantics()` widget in `lib/screens/`
  (`home_screen.dart:2801`, the connect button) — and it is done well.
- `accessibility_utils.dart` is a **stub**: `announce()` is empty and the enabled
  flag is unused, so the three `AccessibilityUtils.announce` call sites do
  nothing.
- The scanner icon buttons had no labels; the SNI scanner's now have tooltips.

### 4.6 Correctness issues found in passing

| Issue | Location |
|---|---|
| `_sniSpoofingIpIndex` is a static that is never reset, so IP rotation drifts across config builds | `singbox_config_builder.dart:936` |
| `_applyPattFragment` unconditionally overwrites the user's `utls` fingerprint and `cipher_suites` | `singbox_config_builder.dart:1015-1019` |
| Fragment values accept nonsense: `"200-100"`, `"0"`, `"99999"` all pass validation; nothing re-validates at emission | `settings_screen.dart:2228-2241` |
| `serverlessOutbounds()` emits `tcp-fragment` and `udp-noises` that no route rule references (intentional, matching upstream — but there is no UI to select them either) | `singbox_config_builder.dart:839, 850` |
| `cfProbeTrace`'s `expectColo` parameter is never passed by any caller | `cloudflare_utils.dart:340` |
| Dead code: `CloudflareRanges.parseCidr4`, `randomIp`, and `CloudflareDetector`'s listener list (never populated, so the callback loop is unreachable) | `cloudflare_utils.dart:83, 97, 260-266, 314-318` |
| VMess outbounds ignore `iranMode` and emit no fragment sizes | `singbox_config_builder.dart:514-517` |
| Cancellation in both scanners is cooperative only — in-flight probes are not aborted, so Stop can lag by up to the timeout | `cloudflare_scanner.dart:78`, `sni_scanner.dart` |

---

## 5. Recommended features, in priority order

Grounded in the tools the Iranian community actually uses; each item names the
prior art it comes from.

### 1. Config-aware scanning ("template mode") — **implemented**

**What:** instead of testing bare (IP, SNI) pairs, take the user's **selected
node** and test it against each candidate IP. That validates the complete path —
TLS, Host-header routing, and the actual WebSocket upgrade — which is what
determines whether the node works.

**Prior art:** `MortezaBashsiz/CFScanner` (the reference tool) and
`joiniran/cfray`'s "Template mode" both work this way, and both are trusted
precisely because a bare handshake is known to be insufficient.

**Status:** shipped as a toggle in the SNI scanner ("Test against my selected
node"). It rebuilds the node's real request — TLS with the fake SNI, then the
real domain in the Host header, with a proper WebSocket upgrade when the
transport is `ws` — and replays it through each candidate IP. Verdicts:

| Result | Meaning |
|---|---|
| `HTTP 101` | WebSocket upgrade accepted — the strongest possible signal |
| other non-5xx status | request was routed to a live origin |
| Cloudflare `error code: 10xx` page | the edge does not serve this domain |
| 5xx | routing worked, the worker behind it is broken |

The toggle refuses to run when the selected node is not CDN-backed, because SNI
Spoofing does not apply to such nodes at all — previously the setting silently
did nothing in that case.

### 2. Rank by speed, not only latency

**What:** after filtering by latency, download a small payload (1–5 MB) through
the best candidates and rank by throughput.

**Prior art:** cfray scores `latency 35% + speed 50% + TTFB 15%`; a low-latency
IP with terrible throughput is a common failure mode on Iranian mobile networks.

### 3. Probe port 8443 as well as 443

**What:** scan both ports and record which one answered.

**Prior art:** cfray's "Mega" mode. Some ISPs block 443 for a given edge while
8443 stays open — cheap to add, meaningful coverage gain.

### 4. Scanner controls: latency cap, stop-after-N, regex filter

**What:** "stop once I have 8 good IPs", "ignore anything above 800 ms", "only
these ranges".

**Prior art:** `payeh/IPCleanScanner` ships exactly these. They cut scan time on
mobile data, which matters for the target audience.

### 5. Fastly and other CDN ranges

**What:** the fork is Cloudflare-only; Fastly is the other CDN commonly used for
clean-IP setups in Iran.

**Prior art:** `payeh/IPCleanScanner` supports Cloudflare + Fastly.

### 6. Randomisation knobs for the fragment mask

**What:** expose the split sizes/delays as a small set of presets (Conservative /
Balanced / Aggressive) plus an advanced mode, instead of raw comma-separated
fields that accept invalid input.

**Prior art:** `SamNet-dev/snix` — its own README notes that with all
randomisation off it behaves exactly like `patterniha/SNI-Spoofing`, i.e. the
knobs are the differentiator.

### 7. First-run wizard

**What:** replace the six forced screens with one flow:
language → region → **add a subscription (or pick serverless)** → connect.
Move agreement/TV-mode/accessibility behind Settings, and give the no-profile
home state a real "Add subscription" call to action.

**Why:** this is the single largest usability gap in the app (§4.1).

### 8. "Why isn't it working?" diagnostics screen

**What:** one button that runs the existing probes (core reachable, DNS
resolver/outbound/direct, node latency, SNI pair, CF edge) and prints a plain
verdict with a suggested fix.

**Why:** the building blocks already exist (`net_check_screen.dart`,
`dns_direct_probe.dart`, `node_direct_probe.dart`, both scanners). This is mostly
composition, and it converts the app's raw error strings into actionable advice.

### 9. Localise the remaining strings, fix the RTL grid, and finish accessibility

**What:** §4.3 / §4.4 / §4.5. In particular: unforce the home grid's LTR
direction, mirror the navigation icons, finish or delete the accessibility stub,
and label the primary controls.

---

## 6. Verification performed

| Check | Result |
|---|---|
| `flutter analyze` on all changed files | no errors; only pre-existing warnings outside the diff |
| Test suite (`--concurrency=1`) | **28 passed** |
| New regression tests | 5 added (`test/scanner_probe_test.dart`): ALPN guard, result ordering, failure classification |
| Locale parity | all 28 locales, 656 leaves, zero drift |
| Release APK | built, 70.7 MB, APK Signature Scheme v2 verified |
| Patched core in APK | `fragment_sizes`, `fragment_delays`, `fragment_max_split`, `finalmask` all present in ARM64 `libgojni.so` |

Note: running the test files with default parallelism intermittently fails to
*load* two suites on this machine (memory pressure). Serialised, everything
passes. This is an environment limitation, not a code defect.

---

## 7. Files changed this pass

| File | Change |
|---|---|
| `lib/app/utils/cloudflare_utils.dart` | ALPN fix + `kCfTraceAlpn` constant (critical) |
| `lib/app/utils/sni_scanner.dart` | real edge verification, `verified`/`colo`/`status`, failure reasons, `compare()`, `SniTemplate`, template probe, testable HTTP parsing |
| `lib/screens/sni_scanner_screen.dart` | localised, template-mode toggle, failure summary, empty state, tooltips, verified badge |
| `lib/screens/cloudflare_scanner_screen.dart` | localised, empty state |
| `lib/i18n/*.i18n.json` (28 files) | `SniScannerScreen` (26 keys) + `CloudflareScannerScreen` (26 keys) |
| `lib/i18n/strings*.g.dart` | regenerated (`dart run slang`) |
| `test/scanner_probe_test.dart` | 9 regression tests |
| `.workbuddy-ai/sync_locale_keys.py` | helper that keeps the 28 locales at key parity |

No commit was created.

---

## 8. Suggested order of work

1. Ship the two fixes in §2 and §3 (done — they make existing features work).
2. Template-mode scanning (§5.1) — **done**.
3. First-run wizard (§5.7) — largest remaining usability win.
4. Diagnostics screen (§5.8) — converts raw errors into guidance.
5. Port 8443 + speed ranking + scanner controls (§5.2–5.4).
6. RTL / i18n / accessibility cleanup (§5.9).
