"""Upload the packaged ZIP to CurseForge.

Reads the project ID (## X-Curse-Project-ID) and interface versions (## Interface)
from RaidPortraits/RaidPortraits.toc, maps each interface number to a CurseForge game version
(11508 -> 1.15.8, 120001 -> 12.0.1), and uses this version's CHANGELOG.md section.

    CF_API_KEY=... python tools/upload_curseforge.py            # upload
    python tools/upload_curseforge.py --dry-run                  # show what would be sent
"""
import json
import os
import re
import sys
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOC = (ROOT / "RaidPortraits" / "RaidPortraits.toc").read_text(encoding="utf-8")
API = "https://wow.curseforge.com/api"


def toc_field(name):
    m = re.search(rf"^## {re.escape(name)}:\s*(.+?)\s*$", TOC, re.M)
    return m.group(1) if m else None


def interface_to_version(n):
    return f"{n // 10000}.{(n // 100) % 100}.{n % 100}"


def changelog_for(version):
    text = (ROOT / "RaidPortraits" / "CHANGELOG.md").read_text(encoding="utf-8")
    m = re.search(rf"^## {re.escape(version)}\s*$(.*?)(?=^## |\Z)", text, re.M | re.S)
    return m.group(1).strip() if m else f"RaidPortraits {version}"


def request(url, token, data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers={"X-Api-Token": token, **(headers or {})})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode())


def multipart(fields, file_field, path):
    boundary = uuid.uuid4().hex
    body = b""
    for k, v in fields.items():
        body += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode()
    body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{file_field}\"; filename=\"{path.name}\"\r\n"
             "Content-Type: application/zip\r\n\r\n").encode() + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    return body, f"multipart/form-data; boundary={boundary}"


def main():
    dry = "--dry-run" in sys.argv
    version = toc_field("Version")
    project = toc_field("X-Curse-Project-ID")
    interfaces = [int(x) for x in re.findall(r"\d+", toc_field("Interface") or "")]
    wanted = [interface_to_version(n) for n in interfaces]
    zip_path = ROOT / "dist" / f"RaidPortraits-{version}.zip"
    release_type = "beta" if re.search(r"beta|alpha", version, re.I) else "release"
    print(f"Version {version} ({release_type}), project {project}, game versions wanted: {', '.join(wanted)}")
    if not zip_path.exists():
        sys.exit(f"{zip_path} is missing; run tools/package.py first")
    if not project or not project.isdigit():
        sys.exit("Add '## X-Curse-Project-ID: <id>' to RaidPortraits/RaidPortraits.toc (shown in the About Project box on CurseForge)")
    token = os.environ.get("CF_API_KEY")
    if not token:
        if dry:
            print("No CF_API_KEY: skipping the game-version lookup.")
            print("Changelog:\n" + changelog_for(version))
            return
        sys.exit("CF_API_KEY is not set")

    known = {v["name"]: v["id"] for v in request(f"{API}/game/versions", token)}
    ids = [known[name] for name in wanted if name in known]
    missing = [name for name in wanted if name not in known]
    if missing:
        print(f"Not on CurseForge (skipped): {', '.join(missing)}")
    if not ids:
        sys.exit("None of the TOC interface versions match a CurseForge game version")
    metadata = {"changelog": changelog_for(version), "changelogType": "markdown",
                "displayName": version, "gameVersions": ids, "releaseType": release_type}
    if dry:
        print(json.dumps(metadata, indent=2))
        return
    body, content_type = multipart({"metadata": json.dumps(metadata)}, "file", zip_path)
    result = request(f"{API}/projects/{project}/upload-file", token, body, {"Content-Type": content_type})
    print(f"Uploaded {zip_path.name} to CurseForge: file id {result.get('id')}")


if __name__ == "__main__":
    main()
