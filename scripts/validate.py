"""Validate the H69K-MAX build project: YAML syntax, config symbol hygiene, workflow sanity."""
import re
import sys
import pathlib

ROOT = pathlib.Path(r"D:\AI\H69k\openwrt-h69k-max")
fails = []
warns = []

# ---------------------------------------------------------------- YAML parse
wf = ROOT / ".github" / "workflows" / "build-h69k-max.yml"
try:
    import yaml  # type: ignore

    doc = yaml.safe_load(wf.read_text(encoding="utf-8"))
    print("[OK] YAML parsed with PyYAML")
    jobs = doc.get("jobs", {})
    print(f"     jobs: {list(jobs)}")
    steps = jobs["build"]["steps"]
    print(f"     build steps: {len(steps)}")
    for s in steps:
        nm = s.get("name", s.get("uses", "?"))
        has_run = "run" in s
        print(f"       - {nm!r:55} run={has_run}")
    # every step must have either run or uses
    for i, s in enumerate(steps):
        if "run" not in s and "uses" not in s:
            fails.append(f"step {i} has neither run nor uses: {s.get('name')}")
    # condition expressions
    exprs = []
    for s in steps:
        cond = s.get("if")
        if cond is not None:
            exprs.append(str(cond))
    print(f"     conditions: {exprs}")
    for e in exprs:
        if "${{" not in e:
            warns.append(f"condition missing expression wrapper: {e}")
except ImportError:
    print("[WARN] PyYAML not available; skipped YAML parse")
    warns.append("PyYAML unavailable - YAML not machine-validated")
except Exception as exc:  # noqa: BLE001
    fails.append(f"YAML parse error: {exc!r}")

# --------------------------------------------------------- workflow integrity
text = wf.read_text(encoding="utf-8")
checks = {
    "REPO_URL LEDE": "https://github.com/coolsnowwolf/lede",
    "device profile": "hinlink_opc-h69k",
    "target rockchip": "CONFIG_TARGET_rockchip",
    "defconfig": "make defconfig",
    "download": "make download",
    "parallel build": "make -j$(nproc)",
    "artifact upload": "actions/upload-artifact@v4",
    "release": "softprops/action-gh-release@v2",
    "feeds update": "./scripts/feeds update -a",
    "feeds install": "./scripts/feeds install -a",
    "kernel pin": "CONFIG_LINUX_",
}
for label, needle in checks.items():
    if needle in text:
        print(f"[OK] workflow contains {label}")
    else:
        fails.append(f"workflow missing {label}: {needle!r}")

# runner must exist
m = re.search(r"runs-on:\s*(\S+)", text)
print(f"     runner: {m.group(1) if m else 'MISSING'}")
if not m:
    fails.append("no runs-on found")

# every referenced config file must exist
for rel in re.findall(r"builder/(config/[A-Za-z0-9._-]+)", text):
    if not (ROOT / rel).exists():
        fails.append(f"workflow references missing file: {rel}")
    else:
        print(f"[OK] workflow reference exists: {rel}")

# --------------------------------------------------- config symbol hygiene
SYM = re.compile(r"^(CONFIG_[A-Za-z0-9_-]+)=(.*)$")
for cfgname in ("config/h69k-max.config", "config/5g-rm520n.config"):
    p = ROOT / cfgname
    seen: dict[str, list[str]] = {}
    for ln, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        line = line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        mm = SYM.match(line)
        if not mm:
            fails.append(f"{cfgname}:{ln} not a CONFIG assignment: {line!r}")
            continue
        seen.setdefault(mm.group(1), []).append(mm.group(2))
    dupes = {k: v for k, v in seen.items() if len(v) > 1}
    if dupes:
        for k, v in dupes.items():
            fails.append(f"{cfgname}: duplicate symbol {k} = {v}")
    else:
        print(f"[OK] {cfgname}: {len(seen)} unique symbols, no duplicates")

# cross-file duplicate consistency (both files are concatenated)
allvals: dict[str, list[tuple[str, str]]] = {}
for cfgname in ("config/h69k-max.config", "config/5g-rm520n.config"):
    p = ROOT / cfgname
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        mm = SYM.match(line)
        if mm:
            allvals.setdefault(mm.group(1), []).append((cfgname, mm.group(2)))
conflicts = {
    k: v for k, v in allvals.items() if len({val for _, val in v}) > 1
}
if conflicts:
    for k, v in conflicts.items():
        fails.append(f"cross-file conflict {k}: {v}")
else:
    print("[OK] no cross-file value conflicts")

# ------------------------------------------------------------------ summary
print()
if warns:
    print("WARNINGS:")
    for w in warns:
        print("  !", w)
print("FAILURES:" if fails else "All checks passed.")
for f in fails:
    print("  X", f)
sys.exit(1 if fails else 0)
