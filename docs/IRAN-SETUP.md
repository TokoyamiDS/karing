# Karing — Iran Setup Guide

Optimized settings for using Karing inside Iran (MTN Irancell, MCI Hamrahe Aval, Rightel), adapted from Patt's [fragment+fingerprint method](https://t.me/patt_channel_x/124) (Xray `finalmask`) to Karing's sing-box core.

## 1. Get working configs

Free, auto-updated every 24h, already tested through the Iranian firewall:

```
https://raw.githubusercontent.com/patterniha/Free-Configs/main/configs.txt
```

These links carry Xray-only parameters (`fp=unsafe`, `cs=`, `fm=`) that Karing ignores. Two options:

- **Recommended:** run the converter once on any PC:
  ```
  dart tools/free_configs_converter.dart --outdir=out
  ```
  then import `out/karing_links.txt` (copy → Add Profile → Paste) or host `out/singbox_subscription.json` somewhere private and add it as a subscription. The converter rewrites links for Karing: `unsafe`→`chrome` fingerprint, cipher suites preserved, TLS fragment fields enabled.
- **Direct:** add the URL above as a subscription. Nodes still work — you just lose the fragmentation benefit Karing can't express per-node.

## 2. Recommended settings (Settings → All)

| Setting | Value | Why |
|---|---|---|
| **TLS fragment** (Settings → TLS) | **On** | Splits the TLS ClientHello so DPI cannot read the SNI. This is the sing-box equivalent of Patt's `fm` fragment stage. |
| Fragment size | `5-94` | Patt's tested values for Cloudflare configs |
| Fragment sleep | `0-1` ms | Patt's `delays: ["0"]` |
| Mixed-case SNI | On | Second layer of SNI obfuscation |
| Padding | Off (or `1-1500` on upload-restricted ISPs) | Patt's second fragment stage approximation |
| uTLS fingerprint | `chrome` (set per-node) | `unsafe` is Xray-only; chrome is the closest sing-box equivalent |
| **DNS resolve mode** | `fakeip` | Fastest; avoids Iranian DNS hijacking of lookups |
| DNS (remote/resolver) | `1.1.1.1`, `8.8.8.8` via proxy | Keep local DNS (`+local` servers) for Iranian domains only |
| Region (Settings → Region) | Iran | Loads the preset rules: `geosite:ir`/`geoip:ir`/Arvancloud/Parspack → direct, ads-ir blocked |

## 3. DNS checker

Settings → Network check (the DNS screen) — use it to:

1. Test each DNS server's latency **through the proxy** vs direct. Iranian ISPs hijack plain UDP/53; prefer DNS-over-HTTPS (`https://...`) entries that show low direct latency, or route DNS through the tunnel.
2. Verify after connecting: Resolver/Outbound/Direct rows should all show success. If Direct fails but Outbound works, your tunnel is fine — your ISP DNS is polluted, which is expected.
3. Re-run whenever configs stop resolving; a dying free config usually shows up here first.

## 4. ISP-specific notes

- **MTN Irancell / upload-restricted networks:** keep TLS fragment ON at all times; it also lifts the upload restriction on Cloudflare-CDN configs. If upload still throttles, enable Padding `1-1500`.
- **MCI:** fragment values above work; if you get instant disconnects, raise sleep to `10-20`.
- **All ISPs:** block QUIC in the diversion rules (add a rule: port 443 + protocol udp → block) so browsers fall back to TCP/TLS where fragmentation applies. Karing's core supports UDP 443 passing QUIC, which DPI can throttle and fragmentation cannot help.
- **Testing many configs at once** saturates the network (Patt's advice): test until you find several working ones, cancel the remaining tests, connect.

## 5. Route preset (Iran)

The Iran region preset ships with:

- `geosite:ir` + `geoip:ir` + `geoip:iranserver` + `geoip:parspack` + `geoip:arvancloud` → **direct**
- `category-ads-ir` + global malware/phishing → **block**
- Everything else → proxy

Enable it in Diversion rules by selecting the Iran preset group.

## 6. Serverless mode (no server needed)

The switch **Settings → Serverless (Iran)** (also the long-press on the connect
button, and the Serverless card on the home screen) skips proxies entirely and
reproduces [patterniha/Serverless-for-Iran](https://github.com/patterniha/Serverless-for-Iran)
**v50** (`Serverless-fragA.jsonc`) on the sing-box core:

| Upstream | Karing |
|---|---|
| `tcp-fragment-tls` direct outbound, `finalmask` splits the ClientHello `6/98/1` at 0 ms | same mask on a `direct` + `finalmask` outbound (`tcp-fragment-tls`), applied to sniffed TLS and TCP/443 |
| second mask stage (`114/1` after the hello) | not emitted: one mask per direct outbound in the core |
| inbound `sniffing` with `destOverride: tls,http,quic` | route rule `{"action":"sniff","sniffer":["tls","http","quic"]}` |
| `udp protocol quic` + `udp port 443` → block | same, so browsers drop to TCP/443 where the mask applies |
| `ip: 10.10.34.0/24, 2001:4188:2:600::/64` → block | same (DPI honeypots) |
| `tcp-direct` / `udp-direct` catch-alls | the plain `direct` outbound is route `final` |
| `tcp-fragment` (1-byte splits) and `udp-noises` (24 × `1200-1230` byte noise) | emitted but unreferenced, exactly as upstream keeps them — point the matching rule at one to try it |

Serverless needs no subscription: connect with nothing selected. Iranian and
private destinations stay direct through the Iran region preset (§5), and the
mode is mutually exclusive with SNI spoofing.

## 7. How the connection actually works

Worth reading once, because the clean IP is easy to misread as "the server you
connect to".

**A profile config is a recipe, not an endpoint.** Nothing ever connects *to* a
config. The config tells the core how to dial; the core then opens a real TCP
connection to a real address.

**The scanner does not tunnel anything.** The SNI/Cloudflare scanners are
measuring instruments: they open a real TCP+TLS connection from your device to a
candidate IP, check what answers, and close it. No traffic is forwarded and no
address is assigned. They also deliberately bypass the tunnel — while the VPN is
running, probes go through the loopback `scan-in` inbound, which the core routes
straight to its `direct` outbound as the first rule, so results always describe
the physical path.

**With SNI spoofing on, the connection is:**

```
your device  ->  clean IP:443 (a CDN edge)  ->  your node behind the CDN
```

The clean IP is the **entry hop only**. Two different names travel at two
different layers, which is what gets it past DPI:

| Layer | Carries | Read by |
|---|---|---|
| TLS ClientHello | `SNI = chatgpt.com` (a whitelisted name) | the DPI — allowed through |
| inner HTTP request | `Host = your-real-domain` | the CDN — routes to your node |

The certificate is issued for the front name, not your domain, which is why the
outbound sets `insecure = true`. This is the same idea as domain fronting, and
it is why the front name and your node must be served by the **same** CDN: the
edge has to know both. Cloudflare satisfies this trivially (any CF edge serves
any CF zone); other CDNs often do not — which is exactly why the scanner now
confirms the IP is a genuine Cloudflare edge before recommending it.

**Your visible IP is not the clean IP.** It is your node's exit IP. The clean IP
never appears as your public address.

| Mode | What your device dials | Your visible IP |
|---|---|---|
| Plain proxy | your node, directly | the node's exit IP |
| SNI spoofing | clean IP = CF edge | the node's exit IP |
| Serverless | nothing — direct to the site | **your own ISP IP** |

Serverless is the one to be careful with: there is no server at all. Traffic
leaves your device directly with the TLS ClientHello fragmented so the DPI
cannot read the SNI. It only helps against destinations blocked *by SNI
inspection* — it does not change your IP and does not help against IP-based
blocking.

**Applying a scan result writes global settings, not per-node ones.** The winning
fake SNI and the list of clean IPs are stored once and then re-applied to every
CDN outbound each time the config is built, rotating through the IP list. So one
scan affects all CDN nodes at once, and nothing changes until you reconnect.

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| Connects, no data | Config dead — free configs rotate; re-run the converter or update the subscription |
| Works on WiFi, dead on mobile data | Your mobile ISP blocks that Cloudflare IP; try another node (they're mostly all `172.67.x.x`) |
| Telegram doesn't connect | Add Telegram rule to proxy, or use a config whose exit allows Telegram |
| Very slow | Test multiple nodes with the delay test, pick lowest; try toggling fragment off to compare |
| Upload stuck | Fragment ON + Padding ON; also block UDP 443 |
