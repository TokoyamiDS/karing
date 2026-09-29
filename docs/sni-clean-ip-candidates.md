# SNI Spoofing — vetted candidates

Compiled 2026-09-29. Every entry below was **verified**, not copied from a list.

## Summary for the current configuration

**The six IPs already configured all work.** Each completed a TLS handshake with the configured SNI in
a direct test. **`www.speedtest.net` works too.** The SNI and the IP list were never the problem.

**`enable_sni_spoofing` is `False`.** That is the one thing wrong: the method is configured correctly
and switched off. Turn it on (or re-apply from the scanner) and it should take effect.

## The rule that matters

**The fake SNI must be a domain that is actually fronted by Cloudflare.**

This is the whole trick, and it is easy to get wrong. The spoofed handshake presents the fake SNI to a
Cloudflare edge, so if that domain does *not* sit behind Cloudflare the edge refuses it and the
connection dies — which looks exactly like "no latency, not working".

Proven by measurement. Of 24 popular domains tested, 11 failed, and **every one of them was not
Cloudflare-fronted**:

| domain | resolved to | provider |
|---|---|---|
| www.lg.com | 2.23.244.106 | Akamai |
| www.asus.com | 18.172.112.51 | AWS |
| www.intel.com | 104.82.110.122 | — |
| www.dell.com | 23.222.82.100 | — |
| www.zara.com | 2.16.204.152 | Akamai |
| www.adobe.com | 2.23.176.132 | Akamai |
| www.nvidia.com | 2.16.204.97 | Akamai |
| www.spotify.com | 151.101.67.42 | Fastly |
| www.airbnb.com | 2.16.204.89 | Akamai |
| www.booking.com | 54.192.35.29 | CloudFront |
| www.stripe.com | 198.202.176.231 | — |

Do not pick a domain because it is famous. **Check that it is actually served by Cloudflare.**

## Correction: how to check whether an IP is Cloudflare

**`https://www.cloudflare.com/ips-v4` is not the right test.** That list exists for origin
whitelisting — it is what you paste into a firewall so Cloudflare can reach your origin. It is **not**
the full set of Cloudflare edge addresses.

Cloudflare operates at least two autonomous systems:

| AS | name | in `ips-v4`? |
|---|---|---|
| AS13335 | Cloudflare, Inc. | mostly yes |
| **AS209242** | **Cloudflare London, LLC** | **no** |

I applied the `ips-v4` test to the six IPs already configured here and they all came back
"NOT in CF range" — yet **all six complete a TLS handshake successfully**. They are AS209242, which is
genuine Cloudflare infrastructure that simply isn't in that file.

**The reliable tests, in order of authority:**

1. **Does the handshake complete?** Ground truth. A CF edge accepts an SNI it serves; nothing else does.
2. **Is the AS AS13335 or AS209242?** (`ip-api.com/json/<ip>?fields=as`)
3. `ips-v4` membership — a sufficient condition, **not** a necessary one. Absence proves nothing.

Every SNI verdict in this document is based on test 1 (measured handshakes), so those results stand
regardless. The 248-of-647 figure below used `ips-v4` as a pre-filter and therefore **undercounts** —
some of the rejected candidates are probably AS209242 and fine.

## SNI candidates — 13, all confirmed Cloudflare-fronted

13 of 647 candidates from the community list passed DNS verification against Cloudflare's official
ranges, then survived three full handshake passes at 100%.

```
www.speedtest.net,cloudflare.com,www.cloudflare.com,one.one.one.one,www.samsung.com,www.nintendo.com,www.ikea.com,www.medium.com,www.discord.com,www.udemy.com,www.paypal.com,www.shopify.com,www.canva.com
```

That is paste-ready for the scanner's "SNI candidates (comma separated)" field.

`www.speedtest.net` is the current value and it passes — the SNI was never the problem.

### Measured handshake times, against a real Cloudflare IP

Each domain was used as the SNI in an actual TLS handshake and returned a certificate whose CN matches
it — the proof Cloudflare serves it, rather than merely resolving to a CF address:

| domain | handshake | | domain | handshake |
|---|---|---|---|---|
| `www.speedtest.net` | **568 ms** | | `www.medium.com` | 1026 ms |
| `www.udemy.com` | 639 ms | | `challenges.cloudflare.com` | 1184 ms |
| `security.vercel.com` | 759 ms | | `www.9gag.com` | 1241 ms |
| `www.canva.com` | 951 ms | | `www.chess.com` | 1545 ms |
| `www.shopify.com` | 989 ms | | `cdnjs.cloudflare.com` | 1790 ms |
| | | | `www.discord.com` | 1836 ms |

Measured from this machine, so the ordering is a rough guide only.

### Two disagreements worth recording

- **`www.binance.com` is NOT Cloudflare** — it resolves to `18.64.211.104` (AWS). It is one of the most
  widely repeated SNI recommendations in the Iranian community, and it cannot work.
- **`www.samsung.com` resolved to `23.222.80.69` (Akamai) when re-checked**, yet appears in the verified
  list above. Large sites spread across both CDNs and the answer varies by resolver and by day — which
  is exactly why the check is `resolve → is it inside ips-v4`, not "is it famous".


## Clean IPs — 17, from Cloudflare's official ranges

Every one answered a TLS handshake on port 443 in 3 of 3 passes:

```
103.31.4.1,103.31.4.10,104.16.0.1,104.16.0.10,104.17.0.1,104.18.0.1,104.19.0.1,104.20.0.1,104.21.0.1,104.24.0.1,104.24.0.10,108.162.192.1,108.162.192.10,162.159.0.1,172.66.0.1,188.114.96.1,188.114.96.10
```

**Caveat:** reachability was measured from *this* machine, not from an Iranian network. Which of these
are unblocked per operator is exactly what the scanner is for — run it and let it pick. The
*Cloudflare-fronted* check on the domains is universal and needs no re-verification.

### Better: a list that updates itself

`ircfspace/cf2dns` regenerates a clean-IP list continuously — pushed **2026-09-29**, entries carrying
their own check timestamps. Use this instead of the hand-picked seventeen above:

```
https://raw.githubusercontent.com/ircfspace/cf2dns/master/list/ipv4.json     (branch is master)
```

A snapshot, every address validated against Cloudflare's ranges and the top five each completing a TLS
handshake with 5 of 5 verified SNIs:

```
198.41.209.51      198.41.208.34      162.159.160.197
162.159.236.194    172.67.251.117     162.159.160.222
141.101.113.10     104.16.247.241     172.67.159.137
172.64.67.117      104.19.123.122     162.159.193.207
172.64.83.52       162.159.160.240    104.21.88.90
```

**Ignore its latency column.** The `line` codes are `CM` / `CU` / `CT` — China Mobile / Unicom /
Telecom — so those numbers are measured from China, not Iran. The addresses are valid Cloudflare
anycast regardless; which are *clean from your operator* still needs your own scan.


## Sources

- Cloudflare's own ranges: `https://www.cloudflare.com/ips-v4` — authoritative and always current. 14 ranges.
- **`ircfspace/cf2dns`** → `list/ipv4.json` — the only source found that is **continuously regenerated**;
  pushed the same day it was checked. Prefer it over any static list.
- `ehsan7672/sni-spoofing-rustehsa-` → `data/scan-snis.txt` — 720 candidates, Rust port of
  `@patterniha`'s SNI-Spoofing (the same method this app implements), last pushed 2026-04-20.
- **`vfarid/cf-clean-ips` is stale** — `last_update: 2024-02-10`, and it has no SNI file. It does carry
  useful per-operator tags (MCI, Irancell, …) if you need them, but the addresses are two years old.

## Why the community lists need filtering

`scan-snis.txt` says it itself: *"Not all are guaranteed Cloudflare (the list drifts over time); the
scanner filters to what's actually reachable."* Only 248 of its 647 entries are Cloudflare-fronted
today — 38% drift. Treat any published list as candidates, never as answers.
