"""Drive SolidWorks 2026 from the terminal: no VBA editor, no F5, no message boxes.

    python tools/sw_run.py <step> [file]     one step
    python tools/sw_run.py rebuild           everything from an empty part (see REBUILD)
    python tools/sw_run.py status            SolidWorks version and open documents
    python tools/sw_run.py build             only compile the harness

Steps: new-chassis, ImportFrameNodes, BuildTubes, TrimTubes, CheckChassis,
new-layout, BuildLayout, DrivenTest, BuildBodies (build123d bodies + clearance
check, no SolidWorks), new-assembly, BuildAssembly, SuspensionParts,
SuspensionAssembly, SuspensionCheck, SuspensionMotion, ChassisStatics,
SaveStandardViews <file>. Diagnostics: mitre, makeprofile, ChassisStatics probe.

How it works: the build logic lives in tools/sw_harness/*.cs (C#, ported from
cad/macros/*.bas). This script compiles it with the Roslyn compiler of the
installed .NET SDK against the SolidWorks interop DLLs into
tools/sw_harness/bin/swh.exe (only when a .cs file changed) and runs it. swh.exe
connects to the running SolidWorks over COM (or starts it), runs the step,
writes the same report files as the macros and prints them.

While a step runs, a watcher lists every dialog box SolidWorks opens and logs
its text. If a dialog stays open for DIALOG_GIVE_UP_S seconds, the step is
stopped and the dialog text is reported: that is the case where only a person
can continue (licence, sign-in, crash report). Every run is appended to
cad/harness_runs.log. Standard library only (ctypes), any Python 3.8+.

Exit codes: 0 pass, 1 a check failed, 2 stopped / error, 3 needs a person.
"""
import ctypes
import ctypes.wintypes as wt
import datetime
import os
import shutil
import subprocess
import sys
import threading
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "tools", "sw_harness")
BIN = os.path.join(SRC, "bin")
EXE = os.path.join(BIN, "swh.exe")
SW_DIR = r"C:\Program Files\SOLIDWORKS Corp\SOLIDWORKS"
DLLS = ["SolidWorks.Interop.sldworks.dll", "SolidWorks.Interop.swconst.dll", "SolidWorks.Interop.swmotionstudy.dll",
        "api/redist/SolidWorks.Interop.cosworks.dll"]
FW = r"C:\Windows\Microsoft.NET\Framework64\v4.0.30319"
RUN_LOG = os.path.join(REPO, "cad", "harness_runs.log")
STEP_TIMEOUT_S = 1800
STEP_TIMEOUTS = {"framesolid": 5400}   # the solid frame study: combine, ~1M-node mesh, solve
# SolidWorks' progress pop-up during long operations: a task-dialog template whose child windows hold only
# these placeholder texts (seen in passing steps; it stayed up 90 s during FrameSolid's long Combine/mesh,
# 2026-11-17). It asks nothing, so it does not stop a step; the step timeout still applies.
PROGRESS_TEMPLATE = "Title | Description | Button1 | Button2 | Hyperlink Text 1 | Hyperlink Text 2"
DIALOG_GIVE_UP_S = 90

# rebuild: (step, args, ok exit codes). TrimTubes runs twice: the second run must change nothing.
REBUILD = [
    ("restart-sw", [], (0,)),          # closes everything without saving, fresh SolidWorks
    ("new-chassis", [], (0,)),
    ("ImportFrameNodes", [], (0,)),
    ("BuildTubes", [], (0,)),
    ("TrimTubes", [], (0,)),
    ("TrimTubes", ["--expect-nothing"], (0,)),
    ("CheckChassis", [], (0,)),
    ("new-layout", [], (0,)),
    ("BuildLayout", [], (0,)),
    ("DrivenTest", [], (0,)),
    ("BuildBodies", [], (0,)),
    ("new-assembly", [], (0,)),
    ("BuildAssembly", [], (0,)),
    ("SuspensionParts", [], (0,)),
    ("SuspensionAssembly", [], (0,)),
    ("SuspensionCheck", [], (0,)),
    ("SuspensionMotion", [], (0,)),
    ("ChassisStatics", [], (0,)),
    ("SaveStandardViews", [r"cad\chassis\chassis.SLDPRT"], (0,)),
    ("SaveStandardViews", [r"cad\layout\master_layout.SLDPRT"], (0,)),
    ("SaveStandardViews", [r"cad\formula_single_seater.SLDASM"], (0,)),
]


def log_run(text):
    os.makedirs(os.path.dirname(RUN_LOG), exist_ok=True)
    with open(RUN_LOG, "a", encoding="utf-8") as f:
        f.write(text.rstrip() + "\n")


# ------------------------------------------------------------------ build
def find_csc():
    root = r"C:\Program Files\dotnet\sdk"
    if os.path.isdir(root):
        for ver in sorted(os.listdir(root), reverse=True):
            p = os.path.join(root, ver, "Roslyn", "bincore", "csc.dll")
            if os.path.isfile(p):
                return p
    return None


def build(force=False):
    sources = sorted(os.path.join(SRC, f) for f in os.listdir(SRC) if f.endswith(".cs"))
    if not force and os.path.isfile(EXE) and os.path.getmtime(EXE) >= max(os.path.getmtime(s) for s in sources):
        return True
    os.makedirs(BIN, exist_ok=True)
    for d in DLLS:
        src = os.path.join(SW_DIR, d)
        dst = os.path.join(BIN, os.path.basename(d))
        if not os.path.isfile(dst) or os.path.getmtime(dst) < os.path.getmtime(src):
            shutil.copy2(src, dst)
    csc = find_csc()
    if csc is None:
        print("No .NET SDK Roslyn compiler found under C:\\Program Files\\dotnet\\sdk")
        return False
    refs = [os.path.join(FW, x) for x in ("mscorlib.dll", "System.dll", "System.Core.dll")] + [os.path.join(BIN, os.path.basename(d)) for d in DLLS]
    cmd = ["dotnet", csc, "-nologo", "-langversion:latest", "-nostdlib", "-noconfig", "-platform:x64",
           "-optimize", "-nowarn:CS1701,CS1702", "-out:" + EXE] + ["-r:" + r for r in refs] + sources
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    if r.returncode != 0:
        print("BUILD FAILED\n" + out)
        return False
    if out:
        print(out)
    print("built " + EXE)
    return True


# ------------------------------------------------------------------ python-side steps (no SolidWorks)
def build123d_python():
    """The repo's .venv (build123d 0.13) if present, else uvx; None if neither."""
    v = os.path.join(REPO, ".venv", "Scripts", "python.exe")
    if os.path.isfile(v):
        return [v]
    if shutil.which("uvx"):
        return ["uvx", "--from", "build123d", "python"]
    return None


def py_step(step, args):
    """BuildBodies: cad/generate/build_parts.py into cad/step, then check_clearances.py.
    Exit 0 only if every clearance rule passes."""
    t0 = time.time()
    py = build123d_python()
    if py is None:
        out, code = "STOPPED, NOTHING CHANGED: no Python with build123d (.venv or uvx)" + chr(10), 2
    else:
        out, code = "", 0
        for script in ("build_parts.py", "check_clearances.py"):
            r = subprocess.run(py + [os.path.join(REPO, "cad", "generate", script)] + args, capture_output=True, text=True,
                               encoding="utf-8", errors="replace", cwd=REPO)
            out += r.stdout + r.stderr
            if r.returncode != 0:
                code = 1
                break
    try:
        sys.stdout.write(out)
    except (OSError, UnicodeEncodeError):
        pass
    first = next((l.strip() for l in out.splitlines() if "RULE" in l or "ALL PASS" in l or "STOPPED" in l), out.strip()[:150])
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_run("%s  %-18s %-22s exit %d  %5.0f s  %s" % (stamp, step, " ".join(args), code, time.time() - t0, first[:150]))
    return code, out, []


PY_STEPS = {"buildbodies": py_step}


# ------------------------------------------------------------------ dialog watcher
user32 = ctypes.WinDLL("user32", use_last_error=True)
EnumWindowsProc = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)


def sw_pids():
    r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq SLDWORKS.exe", "/FO", "CSV", "/NH"], capture_output=True, text=True)
    pids = []
    for line in r.stdout.splitlines():
        parts = [p.strip('"') for p in line.split('","')]
        if len(parts) > 1 and parts[1].isdigit():
            pids.append(int(parts[1]))
    return pids


def _text(hwnd):
    n = user32.GetWindowTextLengthW(hwnd)
    buf = ctypes.create_unicode_buffer(n + 1)
    user32.GetWindowTextW(hwnd, buf, n + 1)
    return buf.value


def _cls(hwnd):
    buf = ctypes.create_unicode_buffer(256)
    user32.GetClassNameW(hwnd, buf, 256)
    return buf.value


def sw_dialogs(pids):
    """Visible top-level dialog windows (#32770) of SolidWorks: hwnd -> text of title and children."""
    found = {}

    def top(hwnd, _):
        pid = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value in pids and user32.IsWindowVisible(hwnd) and _cls(hwnd) == "#32770":
            parts = [_text(hwnd)]

            def child(h, _):
                t = _text(h)
                if t:
                    parts.append(t)
                return True
            user32.EnumChildWindows(hwnd, EnumWindowsProc(child), 0)
            found[hwnd] = " | ".join(p for p in parts if p)
        return True
    user32.EnumWindows(EnumWindowsProc(top), 0)
    return found


class Watcher(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.stop = threading.Event()
        self.seen = {}      # hwnd -> (text, first seen)
        self.blocking = None
        self.pids = sw_pids()

    def run(self):
        while not self.stop.wait(2.0):
            try:
                now = time.time()
                for h, t in sw_dialogs(self.pids).items():
                    if h not in self.seen:
                        self.seen[h] = (t, now)
                        print("   [dialog] " + t)
                    elif now - self.seen[h][1] > DIALOG_GIVE_UP_S and t.strip() != PROGRESS_TEMPLATE:
                        self.blocking = t
            except Exception as e:  # the watcher must never kill a step
                print("   [watcher] " + repr(e))


# ------------------------------------------------------------------ run
def run_step(step, args):
    if step.lower() in PY_STEPS:
        return PY_STEPS[step.lower()](step, args)
    w = Watcher()
    w.start()
    t0 = time.time()
    p = subprocess.Popen([EXE, REPO, step] + args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         encoding="utf-8", errors="replace")
    lines = []

    def pump():
        for line in p.stdout:
            lines.append(line)
            try:
                sys.stdout.write(line)
                sys.stdout.flush()
            except (OSError, UnicodeEncodeError):
                pass    # a closed or narrow console must not stop the step; the line is still kept
    th = threading.Thread(target=pump, daemon=True)
    th.start()
    code = None
    while code is None:
        code = p.poll()
        if code is None:
            if w.blocking or time.time() - t0 > STEP_TIMEOUTS.get(step.lower(), STEP_TIMEOUT_S):
                p.kill()
                code = 3
                why = ("a SolidWorks dialog has been open for %d s: %s" % (DIALOG_GIVE_UP_S, w.blocking)) if w.blocking \
                    else "no answer from SolidWorks in %d s" % STEP_TIMEOUTS.get(step.lower(), STEP_TIMEOUT_S)
                lines.append("NEEDS A PERSON: " + why + "\n")
                print("NEEDS A PERSON: " + why)
                break
            time.sleep(0.5)
    th.join(5)
    w.stop.set()
    dt = time.time() - t0
    dialogs = [" ".join(v[0].split()) for v in w.seen.values()]   # one line per run in the log
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    first = next((l.strip() for l in lines if l.strip()), "")
    log_run("%s  %-18s %-22s exit %d  %5.0f s  %s%s" % (stamp, step, " ".join(args), code, dt, first[:150],
                                                       ("  dialogs: " + " || ".join(dialogs)) if dialogs else ""))
    return code, "".join(lines), dialogs


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    if not build(force=(cmd == "build")):
        return 2
    if cmd == "build":
        return 0
    if cmd.lower() == "rebuild":
        return rebuild()
    code, _, _ = run_step(cmd, argv[2:])
    return code


def rebuild():
    log_run("---- rebuild %s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))
    results = []
    for step, args, ok in REBUILD:
        print("\n==== %s %s" % (step, " ".join(args)))
        code, out, dialogs = run_step(step, args)
        results.append((step, args, code))
        if code not in ok:
            print("\n==== STOPPED at %s (exit %d). Later steps not run." % (step, code))
            break
    print("\n==== rebuild summary")
    for step, args, code in results:
        print("  %-18s %-36s %s" % (step, " ".join(args), {0: "PASS", 1: "CHECK FAILED", 2: "STOPPED/ERROR", 3: "NEEDS A PERSON"}[code]))
    worst = max(c for _, _, c in results)
    return worst


if __name__ == "__main__":
    sys.exit(main(sys.argv))
