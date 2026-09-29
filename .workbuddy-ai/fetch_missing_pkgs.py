"""Fetch the handful of packages the project's lockfile needs but the local
pub cache lacks.

pub.dev returns 403 from this machine, so the mirror is used instead. The
archives are unpacked straight into the pub.dev cache directory, which is
where an offline resolve looks for them.
"""
import io
import os
import tarfile
import urllib.request

MIRROR = "https://pub.flutter-io.cn"
CACHE = r"C:\Users\Teamcheh\AppData\Local\Pub\Cache\hosted\pub.dev"

MISSING = [
    "archive-4.0.9",
    "board_datetime_picker-2.8.6",
    "build-4.0.10",
    "build_config-1.3.2",
    "build_daemon-4.1.5",
    "hive_ce-2.19.3",
    "image_picker_android-0.8.13+21",
    "native_toolchain_c-0.19.3",
    "open_file-4.0.0",
    "path_provider_android-2.2.23",
    "pointer_interceptor-0.10.1+2",
    "re_highlight-0.0.3",
    "sqlite3_connection_pool-0.2.10",
]


def fetch(spec):
    url = "%s/api/archives/%s.tar.gz" % (MIRROR, spec)
    dest = os.path.join(CACHE, spec)
    if os.path.isdir(dest):
        return "already present"
    req = urllib.request.Request(url, headers={"User-Agent": "Dart pub"})
    data = urllib.request.urlopen(req, timeout=120).read()
    os.makedirs(dest, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tf:
        members = tf.getmembers()
        # pub archives are rooted at the package root; if they are not, strip
        # a single common leading directory.
        roots = {m.name.split("/")[0] for m in members if m.name}
        strip = ""
        if len(roots) == 1 and not any(
            m.name.split("/")[0] in ("lib", "pubspec.yaml") for m in members
        ):
            strip = roots.pop() + "/"
        for m in members:
            name = m.name
            if strip and name.startswith(strip):
                name = name[len(strip) :]
            if not name:
                continue
            target = os.path.join(dest, name)
            if not os.path.abspath(target).startswith(os.path.abspath(dest)):
                continue
            if m.isdir():
                os.makedirs(target, exist_ok=True)
            elif m.isfile():
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with open(target, "wb") as f:
                    f.write(tf.extractfile(m).read())
    return "%d KB" % (len(data) // 1024)


for spec in MISSING:
    try:
        print("%-34s %s" % (spec, fetch(spec)))
    except Exception as e:
        print("%-34s FAILED: %s" % (spec, str(e)[:60]))
