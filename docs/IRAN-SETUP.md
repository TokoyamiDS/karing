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

## 6. Troubleshooting

| Symptom | Fix |
|---|---|
| Connects, no data | Config dead — free configs rotate; re-run the converter or update the subscription |
| Works on WiFi, dead on mobile data | Your mobile ISP blocks that Cloudflare IP; try another node (they're mostly all `172.67.x.x`) |
| Telegram doesn't connect | Add Telegram rule to proxy, or use a config whose exit allows Telegram |
| Very slow | Test multiple nodes with the delay test, pick lowest; try toggling fragment off to compare |
| Upload stuck | Fragment ON + Padding ON; also block UDP 443 |
