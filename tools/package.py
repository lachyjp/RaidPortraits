"""Build dist/RaidPortraits-<version>.zip with one top-level RaidPortraits folder."""
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
addon = ROOT / "RaidPortraits"
toc = (addon / "RaidPortraits.toc").read_text(encoding="utf-8")
version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
changelog = (addon / "CHANGELOG.md").read_text(encoding="utf-8")
assert re.search(rf"^## {re.escape(version)}\s*$", changelog, re.M), f"CHANGELOG.md has no entry for {version}"
dest = ROOT / "dist" / f"RaidPortraits-{version}.zip"
dest.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(addon.rglob("*")):
        if path.is_file(): archive.write(path, path.relative_to(ROOT).as_posix())
with zipfile.ZipFile(dest) as archive:
    names = archive.namelist()
    assert archive.testzip() is None
    for need in ("RaidPortraits.toc", "CHANGELOG.md", "INSTALL.txt", "Media/Logo.tga", "Media/Circle.tga"):
        assert f"RaidPortraits/{need}" in names, f"missing {need}"
    for line in toc.splitlines():
        f = line.strip()
        if f and not f.startswith("#"):
            assert f"RaidPortraits/{f}" in names, f"TOC lists {f} but it isn't packaged"
    assert all(n.startswith("RaidPortraits/") and "\\" not in n for n in names)
    assert not any(n.endswith((".bak", ".py")) for n in names)
    print(f"Verified {len(names)} packaged files")
print(f"{dest} ({dest.stat().st_size:,} bytes)")
