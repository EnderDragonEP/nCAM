#!/usr/bin/env python3
"""Dash cam protocol tests (docs/camera-protocol.md, section 10).

Runs on a PC or in Termux; needs only Python 3. Join the camera's Wi-Fi first.

  python camtest.py              info + download + time   (T1-T4, T6-T8)
  python camtest.py info         read-only queries
  python camtest.py download     speed, Range/resume, thumbnail
  python camtest.py time         set the camera clock to this device's clock
  python camtest.py mode --yes   T5: playback mode test (may stop recording)
  python camtest.py idle         T9: 5 minutes of silence, then one request
  python camtest.py views        live view modes, switch speed, second stream
                                 (saves pictures to camtest-views-<date>/)

Everything is written to camtest-<date>.log next to where you run it.
"""
import argparse
import datetime
import http.client
import os
import re
import socket
import sys
import threading
import time
from urllib.parse import quote

VIDEO_EXT = (".mp4", ".mov", ".ts")
MB = 1024 * 1024


class Cam:
    def __init__(self, host, port, logfile):
        self.host, self.port, self.bind = host, port, None
        self.f = open(logfile, "w", encoding="utf-8", errors="replace")

    # ---------- logging ----------
    def out(self, msg=""):
        print(msg, flush=True)
        self.raw(msg)

    def raw(self, msg):
        self.f.write(msg + "\n")
        self.f.flush()

    def head(self, title):
        self.out("\n" + "=" * 8 + " " + title + " " + "=" * 8)

    # ---------- http ----------
    def conn(self, timeout=15):
        src = (self.bind, 0) if self.bind else None
        return http.client.HTTPConnection(self.host, self.port, timeout=timeout, source_address=src)

    def get(self, path, headers=None, limit=None, timeout=15):
        """Returns dict(status, headers, body, secs, err). Stops reading after `limit` bytes."""
        r = {"status": None, "headers": {}, "body": b"", "secs": 0.0, "err": None, "ttfb": 0.0}
        t0 = time.time()
        c = self.conn(timeout)
        try:
            c.request("GET", path, headers=headers or {})
            resp = c.getresponse()
            r["ttfb"] = time.time() - t0
            r["status"] = resp.status
            r["headers"] = dict(resp.getheaders())
            chunks, got = [], 0
            while limit is None or got < limit:
                want = 262144 if limit is None else min(262144, limit - got)
                b = resp.read(want)
                if not b:
                    break
                got += len(b)
                if limit is None or limit <= 4 * MB:
                    chunks.append(b)
                else:
                    chunks = [b[:16]] if not chunks else chunks
            r["body"] = b"".join(chunks)
            r["bytes"] = got
        except Exception as e:  # noqa: BLE001 - we want every failure in the log
            r["err"] = "%s: %s" % (type(e).__name__, e)
        finally:
            r["secs"] = time.time() - t0
            try:
                c.close()
            except Exception:  # noqa: BLE001
                pass
        r.setdefault("bytes", len(r["body"]))
        return r

    def cmd(self, cmd, par=None, s=None, show=True):
        path = "/?custom=1&cmd=%s" % cmd
        if par is not None:
            path += "&par=%s" % par
        if s is not None:
            path += "&str=%s" % quote(str(s), safe="")
        r = self.get(path)
        text = r["body"].decode("utf-8", "replace")
        self.raw("\n--- GET %s\nstatus=%s secs=%.2f err=%s\nheaders=%s\n%s" % (
            path, r["status"], r["secs"], r["err"], r["headers"], text))
        if show:
            one = re.sub(r"\s+", " ", text).strip()
            print("  cmd=%s%s%s -> http %s  %s" % (
                cmd, "" if par is None else " par=%s" % par, "" if s is None else " str=%s" % s,
                r["status"] if not r["err"] else r["err"], one[:160] + ("..." if len(one) > 160 else "")),
                flush=True)
        return text

    def rec_secs(self, show=True):
        v = tag(self.cmd(2016, show=False), "Value")
        try:
            n = int(v)
        except (TypeError, ValueError):
            n = -1
        if show:
            self.out("  recording: %s (cmd 2016 Value=%s)" % (
                "YES" if n > 0 else "no" if n == 0 else "unknown", v))
        return n

    # ---------- files ----------
    def list_files(self, show=True):
        text = self.cmd(3015, show=False)
        files = []
        for block in re.findall(r"<File>(.*?)</File>", text, re.S):
            fp = tag(block, "FPATH") or ""
            p = re.sub(r"^[A-Za-z]:", "", fp).replace("\\", "/")
            try:
                size = int(tag(block, "SIZE") or 0)
            except ValueError:
                size = 0
            files.append({"name": tag(block, "NAME") or "", "fpath": fp, "path": p, "size": size,
                          "time": tag(block, "TIME") or "", "attr": tag(block, "ATTR"),
                          "video": p.lower().endswith(VIDEO_EXT)})
        files.sort(key=lambda f: f["time"], reverse=True)
        if show:
            self.out("  cmd=3015 -> %d files, %.1f GB total, response %d bytes" % (
                len(files), sum(f["size"] for f in files) / 1024 ** 3, len(text)))
            dirs = {}
            for f in files:
                d = f["path"].rsplit("/", 1)[0] + "/"
                dirs.setdefault(d, [0, 0])
                dirs[d][0] += 1
                dirs[d][1] += f["size"]
            for d, (n, sz) in sorted(dirs.items()):
                self.out("    %-28s %5d files  %8.1f MB" % (d, n, sz / MB))
            self.out("  newest 5:")
            for f in files[:5]:
                self.out("    %s  %8.1f MB  attr=%s  %s" % (f["time"], f["size"] / MB, f["attr"], f["path"]))
            if not files:
                self.out("  (no <File> entries parsed - see raw response in the log)")
        return files


def tag(text, name):
    m = re.search(r"<%s>(.*?)</%s>" % (name, name), text or "", re.S)
    return m.group(1).strip() if m else None


def speed(r):
    return (r["bytes"] / MB) / r["secs"] if r["secs"] > 0 else 0.0


# ---------------------------------------------------------------- steps

def find_camera(cam):
    cam.head("Connect")
    cands = [None]
    try:
        cands += [ip for ip in socket.gethostbyname_ex(socket.gethostname())[2] if not ip.startswith("127.")]
    except OSError:
        pass
    for src in cands:
        cam.bind = src
        r = cam.get("/?custom=1&cmd=3012", timeout=5)
        cam.raw("probe bind=%s -> %s %s %r" % (src, r["status"], r["err"], r["body"][:200]))
        if r["status"] and b"<Cmd>" in r["body"]:
            cam.out("  camera answered at %s:%s (local address: %s)" % (cam.host, cam.port, src or "default"))
            return True
    cam.out("  NO ANSWER from %s. Join the camera's Wi-Fi first; on a phone also turn mobile data OFF." % cam.host)
    return False


def step_info(cam):
    cam.head("T1 identity / status")
    for c in (3012, 8005, 3024, 3017, 3019):
        cam.cmd(c)
    cam.rec_secs()

    cam.head("T8 live view links")
    cam.cmd(2019)

    cam.head("T7 settings (full XML is in the log)")
    cur = cam.cmd(3014, show=False)
    pairs = re.findall(r"<Cmd>(\d+)</Cmd>\s*<Status>(.*?)</Status>", cur, re.S)
    cam.out("  cmd=3014 current values: " + ", ".join("%s=%s" % p for p in pairs))
    opts = cam.cmd(3031, s="all", show=False)
    for item in re.findall(r"<Item>(.*?)</Item>", opts, re.S):
        ids = re.findall(r"<Id>(.*?)</Id>", item, re.S)
        idx = re.findall(r"<Index>(.*?)</Index>", item, re.S)
        cam.out("  %-5s %-22s %s%s" % (tag(item, "Cmd"), tag(item, "Name"), ids,
                                       ("  index=%s" % idx) if idx else ""))
    if "<Item>" not in opts:
        cam.out("  cmd=3031 gave no <Item> entries (%d bytes) - see log" % len(opts))

    cam.head("T2 file list")
    files = cam.list_files()

    cam.head("T2 HTTP file index")
    paths = ["/", "/CARDV/", "/CARDV/MOVIE/", "/CARDV/PHOTO/", "/CARDV/MOVIE/RO/", "/DCIM/", "/DCIM/MOVIE/",
             "/DCIM/PHOTO/"]
    for f in files:
        d = f["path"].rsplit("/", 1)[0] + "/"
        if d not in paths:
            paths.append(d)
    for p in paths:
        r = cam.get(quote(p), limit=200000)
        body = r["body"].decode("utf-8", "replace")
        cam.raw("\n--- GET %s\nstatus=%s err=%s headers=%s\n%s" % (p, r["status"], r["err"], r["headers"], body[:20000]))
        cam.out("  %-28s http %s  %d bytes  %d links  type=%s" % (
            p, r["status"] if not r["err"] else r["err"], r["bytes"], len(re.findall(r"(?i)<a\s", body)),
            r["headers"].get("Content-Type")))

    cam.head("Ports")
    for port in (80, 554, 3333, 8192, 21, 23, 8080):
        s = socket.socket()
        s.settimeout(3)
        try:
            if cam.bind:
                s.bind((cam.bind, 0))
            s.connect((cam.host, port))
            state = "open"
        except OSError as e:
            state = "closed (%s)" % type(e).__name__
        finally:
            s.close()
        cam.out("  tcp %-5d %s" % (port, state))

    cam.head("Notification socket 3333 (listening 8 s)")
    s = socket.socket()
    s.settimeout(3)
    try:
        if cam.bind:
            s.bind((cam.bind, 0))
        s.connect((cam.host, 3333))
        s.settimeout(1)
        end, got = time.time() + 8, b""
        while time.time() < end:
            try:
                b = s.recv(4096)
                if not b:
                    break
                got += b
            except socket.timeout:
                pass
        cam.out("  received %d bytes: %r" % (len(got), got[:600]))
    except OSError as e:
        cam.out("  could not connect: %s" % e)
    finally:
        s.close()


def pick_videos(cam, files, recording):
    """Returns (files still being written, finished videos newest first).

    The camera clock can be wrong, so "newest by time" is not reliable: a file is
    treated as in progress when its size changes between two listings.
    """
    vids = [f for f in files if f["video"]]
    growing = []
    if recording and vids:
        time.sleep(3)
        later = {f["path"]: f["size"] for f in cam.list_files(show=False)}
        growing = [f for f in vids if later.get(f["path"], f["size"]) != f["size"]]
        for f in growing:
            cam.out("  being written now: %s (%.1f -> %.1f MB)" % (f["path"], f["size"] / MB, later[f["path"]] / MB))
    done = [f for f in vids if f not in growing]
    big = [f for f in done if f["size"] >= 8 * MB] or done
    return growing, big


def timed_download(cam, label, f, nbytes, headers=None):
    r = cam.get(quote(f["path"]), headers=headers, limit=nbytes, timeout=30)
    cam.raw("\n--- GET %s %s\nstatus=%s err=%s headers=%s" % (f["path"], headers, r["status"], r["err"], r["headers"]))
    cam.out("  %-26s http %s  %.1f MB in %.1f s = %.2f MB/s (first byte %.2f s)%s" % (
        label, r["status"], r["bytes"] / MB, r["secs"], speed(r), r["ttfb"],
        ("  ERROR " + r["err"]) if r["err"] else ""))
    return r


def step_download(cam, mb):
    cam.head("T3/T4 list + download (recording state before)")
    rec0 = cam.rec_secs()
    files = cam.list_files(show=False)
    cam.out("  listed %d files" % len(files))
    current, vids = pick_videos(cam, files, rec0 > 0)
    if not vids:
        cam.out("  no finished video file to test with")
        return
    f = vids[0]
    cam.out("  test file: %s (%.1f MB, %s)" % (f["path"], f["size"] / MB, f["time"]))

    r = timed_download(cam, "plain GET, first %d MB" % mb, f, mb * MB)
    cam.out("    Content-Length=%s Accept-Ranges=%s Content-Type=%s" % (
        r["headers"].get("Content-Length"), r["headers"].get("Accept-Ranges"), r["headers"].get("Content-Type")))

    mid = f["size"] // 2
    r = timed_download(cam, "Range from middle, 1 MB", f, MB, {"Range": "bytes=%d-%d" % (mid, mid + MB - 1)})
    ok = r["status"] == 206
    cam.out("    Content-Range=%s -> resume %s" % (
        r["headers"].get("Content-Range"), "SUPPORTED" if ok else "NOT supported (server ignored Range)"))
    r = timed_download(cam, "Range open-ended, 1 MB", f, MB, {"Range": "bytes=%d-" % mid})
    cam.out("    Content-Range=%s Content-Length=%s" % (r["headers"].get("Content-Range"), r["headers"].get("Content-Length")))

    r = cam.get(quote(f["path"]) + "?custom=1&cmd=4001", timeout=20)
    cam.raw("\n--- thumbnail %s status=%s err=%s headers=%s first=%r" % (f["path"], r["status"], r["err"], r["headers"], r["body"][:400]))
    cam.out("  thumbnail (cmd 4001)        http %s  %d bytes in %.2f s  type=%s  jpeg=%s" % (
        r["status"], r["bytes"], r["secs"], r["headers"].get("Content-Type"), r["body"][:2] == b"\xff\xd8"))
    photos = [x for x in files if not x["video"]]
    if photos:
        r = cam.get(quote(photos[0]["path"]) + "?custom=1&cmd=4001", timeout=20)
        cam.out("  photo thumbnail             http %s  %d bytes  jpeg=%s  (%s)" % (
            r["status"], r["bytes"], r["body"][:2] == b"\xff\xd8", photos[0]["path"]))

    if len(vids) >= 2:
        res = [None, None]

        def work(i):
            res[i] = cam.get(quote(vids[i]["path"]), limit=(mb // 2) * MB, timeout=30)

        t0 = time.time()
        ts = [threading.Thread(target=work, args=(i,)) for i in (0, 1)]
        [t.start() for t in ts]
        [t.join() for t in ts]
        secs = time.time() - t0
        total = sum(x["bytes"] for x in res)
        cam.out("  2 downloads in parallel      http %s/%s  %.1f MB in %.1f s = %.2f MB/s combined  err=%s/%s" % (
            res[0]["status"], res[1]["status"], total / MB, secs, total / MB / secs if secs else 0,
            res[0]["err"], res[1]["err"]))

    for g in current[:2]:
        timed_download(cam, "file being recorded, 1 MB", g, MB)

    cam.out("  recording state after:")
    rec1 = cam.rec_secs()
    if rec0 > 0:
        cam.out("  => recording %s during list/download (%d s -> %d s)" % (
            "is STILL ON" if rec1 > 0 else "STOPPED", rec0, rec1))
    else:
        cam.out("  => camera was not recording; repeat this step while it records")


def step_time(cam):
    cam.head("T6 clock")
    now = datetime.datetime.now()
    files = cam.list_files(show=False)
    cam.out("  this device's clock: %s" % now.strftime("%Y/%m/%d %H:%M:%S"))
    for f in files[:3]:
        cam.out("  newest file before sync: %s  %s" % (f["time"], f["name"]))
    rec0 = cam.rec_secs()
    now = datetime.datetime.now()
    a = cam.cmd(3005, s=now.strftime("%Y-%m-%d"))
    b = cam.cmd(3006, s=now.strftime("%H:%M:%S"))
    cam.out("  set date Status=%s, set time Status=%s (0 = accepted)" % (tag(a, "Status"), tag(b, "Status")))
    time.sleep(2)
    rec1 = cam.rec_secs()
    if rec0 > 0:
        cam.out("  => recording %s across the time change (%d s -> %d s)" % (
            "is still on" if rec1 > 0 else "STOPPED", rec0, rec1))
    cam.out("  Check the date stamp on the camera screen now. Run 'camtest.py time' again after the next\n"
            "  clip starts, and once more after the camera has been powered off for a while: the\n"
            "  'newest file before sync' lines show how far the clock had drifted.")


def step_mode(cam, mb, yes):
    cam.head("T5 playback mode (may stop recording)")
    if not yes:
        cam.out("  skipped: add --yes to run it. Do this parked.")
        return
    rec0 = cam.rec_secs()
    files = cam.list_files(show=False)
    _, vids = pick_videos(cam, files, rec0 > 0)
    if vids:
        timed_download(cam, "movie mode, %d MB" % mb, vids[0], mb * MB)
    cam.cmd(3001, par=2)
    time.sleep(2)
    cam.out("  after switching to playback mode:")
    cam.rec_secs()
    if vids:
        timed_download(cam, "playback mode, %d MB" % mb, vids[0], mb * MB)
    cam.cmd(3001, par=1)
    rec = 0
    for wait in (3, 5, 7):
        time.sleep(wait)
        rec = cam.rec_secs()
    if rec0 > 0 and rec <= 0:
        cam.out("  recording did NOT restart by itself; sending start (cmd 2001 par=1)")
        cam.cmd(2001, par=1)
        time.sleep(3)
        cam.rec_secs()
    elif rec0 > 0:
        cam.out("  => recording restarted by itself after returning to movie mode")


def step_idle(cam, secs):
    cam.head("T9 idle %d s, then one request" % secs)
    for left in range(secs, 0, -30):
        print("  waiting %d s..." % left, flush=True)
        time.sleep(min(30, left))
    cam.cmd(3012)
    cam.rec_secs()


class Mjpeg:
    """Reads the camera's live view (MJPEG on :8192) in a background thread and keeps
    every picture with the time it arrived."""

    def __init__(self, cam, port=8192):
        self.cam, self.port = cam, port
        self.frames = []  # (time, bytes)
        self.error = None
        self.stopped = False
        self.lock = threading.Lock()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self.thread.start()
        return self

    def stop(self):
        self.stopped = True
        try:
            self.sock.close()
        except Exception:  # noqa: BLE001
            pass
        self.thread.join(3)

    def _run(self):
        try:
            self.sock = socket.socket()
            self.sock.settimeout(5)
            if self.cam.bind:
                self.sock.bind((self.cam.bind, 0))
            self.sock.connect((self.cam.host, self.port))
            self.sock.sendall(b"GET / HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n"
                              % self.cam.host.encode())
            buf = b""
            while not self.stopped:
                chunk = self.sock.recv(65536)
                if not chunk:
                    self.error = "stream closed"
                    break
                buf += chunk
                while True:
                    a = buf.find(b"\xff\xd8")
                    if a < 0:
                        buf = buf[-1:]
                        break
                    b = buf.find(b"\xff\xd9", a + 2)
                    if b < 0:
                        buf = buf[a:]
                        break
                    with self.lock:
                        self.frames.append((time.time(), buf[a:b + 2]))
                    buf = buf[b + 2:]
        except Exception as e:  # noqa: BLE001
            if not self.stopped:
                self.error = "%s: %s" % (type(e).__name__, e)

    def count(self):
        with self.lock:
            return len(self.frames)

    def at(self, t):
        """The last picture that arrived at or before time t."""
        with self.lock:
            best = None
            for ft, data in self.frames:
                if ft <= t:
                    best = (ft, data)
                else:
                    break
            return best

    def since(self, t):
        with self.lock:
            return [(ft, d) for ft, d in self.frames if ft >= t]


def jpeg_size(data):
    """(width, height) from a JPEG's SOF marker, or None."""
    i = 2
    while i + 9 < len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xC0, 0xC1, 0xC2):
            h = (data[i + 5] << 8) | data[i + 6]
            w = (data[i + 7] << 8) | data[i + 8]
            return w, h
        length = (data[i + 2] << 8) | data[i + 3]
        i += 2 + length
    return None


def step_views(cam):
    cam.head("Live view modes (watch the camera's own screen too)")
    folder = "camtest-views-%s" % datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    os.makedirs(folder, exist_ok=True)

    def save(name, frame):
        if frame:
            with open(os.path.join(folder, name), "wb") as f:
                f.write(frame[1])

    cur = cam.cmd(3014, show=False)
    m = re.search(r"<Cmd>3028</Cmd>\s*<Status>(\d+)</Status>", cur)
    original = int(m.group(1)) if m else None
    cam.out("  current view (3028): %s" % original)
    cam.rec_secs()

    live = Mjpeg(cam).start()
    try:
        time.sleep(3)
        n = live.count()
        cam.out("  stream: %d pictures in 3 s (%.1f fps)%s" % (
            n, n / 3.0, ("  ERROR " + live.error) if live.error else ""))
        if n == 0:
            cam.out("  no pictures; the rest of this step needs the stream")
            return
        first = live.at(time.time())
        cam.out("  picture size: %s, %d bytes" % (jpeg_size(first[1]), len(first[1])))

        cam.head("Each view number")
        for par in range(0, 7):
            t0 = time.time()
            text = cam.cmd(3028, par=par, show=False)
            st = tag(text, "Status")
            time.sleep(3.2)
            sizes = sorted({jpeg_size(d) for _, d in live.since(t0)}, key=str)
            cam.out("  view %d -> status %s, %d pictures in 3 s, sizes %s" % (
                par, st, len(live.since(t0)), sizes))
            for label, dt in (("0.2s", 0.2), ("0.5s", 0.5), ("1s", 1.0), ("3s", 3.0)):
                save("view%d-%s.jpg" % (par, label), live.at(t0 + dt))

        cam.head("Fast switching between front (0) and rear (1)")
        for gap in (0.5, 0.25):
            sub = "alt-%dms" % int(gap * 1000)
            os.makedirs(os.path.join(folder, sub), exist_ok=True)
            switches = []
            t_start = time.time()
            for i in range(20):
                par = i % 2
                switches.append((time.time(), par))
                cam.cmd(3028, par=par, show=False)
                time.sleep(gap)
            frames = live.since(t_start)
            for k, (ft, data) in enumerate(frames):
                # Name each picture after the last view asked for before it arrived.
                asked = [p for st, p in switches if st <= ft]
                with open(os.path.join(folder, sub, "%03d-asked%s-%+.2fs.jpg" % (
                        k, asked[-1] if asked else "-", ft - t_start)), "wb") as f:
                    f.write(data)
            cam.out("  every %d ms: 20 switches, %d pictures (saved in %s/%s)" % (
                gap * 1000, len(frames), folder, sub))
            time.sleep(1)
    finally:
        if original is not None:
            cam.cmd(3028, par=original, show=False)
            cam.out("  view set back to %s" % original)
        live.stop()

    cam.head("Two streams at once")
    a, b = Mjpeg(cam).start(), Mjpeg(cam).start()
    time.sleep(4)
    cam.out("  first: %d pictures %s; second: %d pictures %s" % (
        a.count(), a.error or "", b.count(), b.error or ""))
    a.stop()
    b.stop()

    cam.head("Other ports near 8192")
    for port in range(8190, 8200):
        sck = socket.socket()
        sck.settimeout(2)
        try:
            if cam.bind:
                sck.bind((cam.bind, 0))
            sck.connect((cam.host, port))
            state = "OPEN"
        except OSError:
            state = "closed"
        finally:
            sck.close()
        cam.out("  tcp %d %s" % (port, state))
    cam.rec_secs()
    cam.out("  Pictures saved in %s/ - please send that folder with this log." % os.path.abspath(folder))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("steps", nargs="*", default=["info", "download", "time"],
                    help="info download time mode idle views (default: info download time)")
    ap.add_argument("--host", default="192.168.1.254")
    ap.add_argument("--port", type=int, default=80)
    ap.add_argument("--mb", type=int, default=32, help="MB to download per speed test (default 32)")
    ap.add_argument("--idle-secs", type=int, default=300)
    ap.add_argument("--yes", action="store_true", help="allow the 'mode' step, which can stop recording")
    a = ap.parse_intermixed_args()
    bad = [s for s in a.steps if s not in ("info", "download", "time", "mode", "idle", "views")]
    if bad:
        ap.error("unknown step: %s" % ", ".join(bad))

    name = "camtest-%s.log" % datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    try:
        cam = Cam(a.host, a.port, name)
    except OSError:
        name = os.path.join(os.path.expanduser("~"), name)
        cam = Cam(a.host, a.port, name)
    cam.out("camtest %s  steps=%s  python %s  %s" % (
        datetime.datetime.now().isoformat(timespec="seconds"), a.steps, sys.version.split()[0], sys.platform))
    try:
        if not find_camera(cam):
            return 1
        for s in a.steps:
            try:
                if s == "info":
                    step_info(cam)
                elif s == "download":
                    step_download(cam, a.mb)
                elif s == "time":
                    step_time(cam)
                elif s == "mode":
                    step_mode(cam, a.mb, a.yes)
                elif s == "views":
                    step_views(cam)
                elif s == "idle":
                    step_idle(cam, a.idle_secs)
            except Exception as e:  # noqa: BLE001 - keep going with the next step
                cam.out("  STEP '%s' FAILED: %s: %s" % (s, type(e).__name__, e))
    finally:
        print("\nLog written to: %s" % os.path.abspath(name))
        cam.f.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
