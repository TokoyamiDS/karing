"""Exercise the running core through its local mixed port.

Proxy mode only: talks to 127.0.0.1:<mixed port>, never touches TUN or the
system proxy. Uses the Clash API to switch nodes and measure delay.
"""
import json
import os
import ssl
import time
import urllib.parse
import urllib.request

# The shell exports a loopback HTTP_PROXY that would poison every request here.
for k in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy",
          "ALL_PROXY", "all_proxy", "NO_PROXY", "no_proxy"):
    os.environ.pop(k, None)

API = "http://127.0.0.1:18057"
MIXED_PORT = 18067
TRACE = "https://www.cloudflare.com/cdn-cgi/trace"
PROBE = "http://www.gstatic.com/generate_204"

_ctx = ssl.create_default_context()
_ctx.check_hostname = False
_ctx.verify_mode = ssl.CERT_NONE


def api(path):
    return json.load(urllib.request.urlopen(API + path, timeout=15))


def switch(name):
    req = urllib.request.Request(
        API + "/proxies/proxy",
        data=json.dumps({"name": name}).encode(),
        method="PUT",
        headers={"Content-Type": "application/json"},
    )
    urllib.request.urlopen(req, timeout=15).read()


def node_delay(name, timeout_ms=5000):
    q = urllib.parse.urlencode({"url": PROBE, "timeout": timeout_ms})
    try:
        return api("/proxies/%s/delay?%s" % (urllib.parse.quote(name), q)).get("delay")
    except Exception as e:
        return "ERR:%s" % str(e)[:60]


def through_proxy(url=TRACE, timeout=30):
    handler = urllib.request.ProxyHandler({
        "http": "http://127.0.0.1:%d" % MIXED_PORT,
        "https": "http://127.0.0.1:%d" % MIXED_PORT,
    })
    opener = urllib.request.build_opener(
        handler, urllib.request.HTTPSHandler(context=_ctx)
    )
    t0 = time.time()
    try:
        r = opener.open(url, timeout=timeout)
        body = r.read().decode("utf-8", "replace")
        ms = int((time.time() - t0) * 1000)
        if url == TRACE:
            d = dict(l.split("=", 1) for l in body.strip().split("\n") if "=" in l)
            return ms, d.get("ip"), d.get("loc"), d.get("colo")
        return ms, r.status, "", ""
    except Exception as e:
        return -1, "FAIL", str(e)[:70], ""


def main():
    sel = api("/proxies/proxy")
    nodes = [o for o in sel["all"] if o != "AutoSelect"]
    print("nodes:", len(nodes))
    for n in nodes:
        print("  delay %-45s %s ms" % (n[:45], node_delay(n)))

    print()
    for n in nodes:
        switch(n)
        time.sleep(1)
        ms, ip, loc, colo = through_proxy()
        print("%-45s %s  ip=%s loc=%s colo=%s" % (n[:45], ("%dms" % ms) if ms > 0 else "FAIL", ip, loc, colo))

    # restore auto-select
    switch("AutoSelect")


if __name__ == "__main__":
    main()
