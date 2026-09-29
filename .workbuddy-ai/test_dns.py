"""Measure every DNS resolver the app is configured with.

Sends a real A query and times it. UDP resolvers are queried over :53, DoH
resolvers over HTTPS. Nothing here changes the machine's DNS settings.
"""
import os
import socket
import ssl
import struct
import time
import urllib.request

for k in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy",
          "ALL_PROXY", "all_proxy", "NO_PROXY", "no_proxy"):
    os.environ.pop(k, None)

DOMAIN = "www.google.com"
# tag, kind, address  (from core_config.json)
RESOLVERS = [
    ("dns-remote-1", "https", "120.53.53.53"),
    ("dns-remote-2", "https", "1.12.12.12"),
    ("dns-direct-3", "udp", "94.140.15.15"),
    ("dns-direct-4", "udp", "94.140.14.14"),
    ("dns-direct-5", "udp", "8.8.8.8"),
    ("dns-direct-6", "udp", "1.1.1.1"),
    ("dns-direct-9", "udp", "8.8.4.4"),
    ("dns-direct-10", "udp", "180.184.2.2"),
    ("dns-direct-11", "udp", "180.184.1.1"),
]


def build_query(domain):
    tid = 0x1234
    flags = 0x0100  # standard query, recursion desired
    header = struct.pack(">HHHHHH", tid, flags, 1, 0, 0, 0)
    q = b"".join(bytes([len(p)]) + p.encode() for p in domain.split(".")) + b"\x00"
    return header + q + struct.pack(">HH", 1, 1)


def parse_answer(data):
    """Return the first A record, or None."""
    if len(data) < 12:
        return None
    ancount = struct.unpack(">H", data[6:8])[0]
    if ancount == 0:
        return None
    i = 12
    while i < len(data) and data[i] != 0:  # skip qname
        i += data[i] + 1
    i += 5  # null + qtype + qclass
    for _ in range(ancount):
        if i + 12 > len(data):
            return None
        if data[i] & 0xC0 == 0xC0:
            i += 2
        else:
            while i < len(data) and data[i] != 0:
                i += data[i] + 1
            i += 1
        rtype, _, _, rdlen = struct.unpack(">HHIH", data[i:i + 10])
        i += 10
        if rtype == 1 and rdlen == 4:
            return ".".join(str(b) for b in data[i:i + 4])
        i += rdlen
    return None


def udp_query(server, domain=DOMAIN, timeout=4.0):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    try:
        t0 = time.time()
        s.sendto(build_query(domain), (server, 53))
        data, _ = s.recvfrom(512)
        ms = int((time.time() - t0) * 1000)
        return ms, parse_answer(data)
    except Exception as e:
        return -1, "FAIL:%s" % str(e)[:40]
    finally:
        s.close()


def doh_query(server, domain=DOMAIN, timeout=6.0):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    url = "https://%s/dns-query?dns=%s" % (server, _b64(build_query(domain)))
    try:
        t0 = time.time()
        req = urllib.request.Request(url, headers={"Accept": "application/dns-message"})
        data = urllib.request.urlopen(req, timeout=timeout, context=ctx).read()
        ms = int((time.time() - t0) * 1000)
        return ms, parse_answer(data)
    except Exception as e:
        return -1, "FAIL:%s" % str(e)[:40]


def _b64(b):
    import base64
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def main():
    print("query: %s\n" % DOMAIN)
    print("%-14s %-6s %-16s %-9s %s" % ("tag", "kind", "server", "rtt", "answer"))
    print("-" * 72)
    for tag, kind, addr in RESOLVERS:
        ms, ans = doh_query(addr) if kind == "https" else udp_query(addr)
        print("%-14s %-6s %-16s %-9s %s" % (
            tag, kind, addr, ("%dms" % ms) if ms > 0 else "FAIL", ans))


if __name__ == "__main__":
    main()
