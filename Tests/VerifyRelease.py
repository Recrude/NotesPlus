"""Validate the exact release archive and reject tampering; run after generate-feed.sh."""
from pathlib import Path
import json
import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

root = Path(__file__).resolve().parents[1]
info = plistlib.loads((root / "Resources/Info.plist").read_bytes())
version = info["CFBundleShortVersionString"]
feed = root / "Release/appcast.xml"
ns = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
items = ET.fromstring(feed.read_bytes()).findall("channel/item")
item = next(i for i in items if i.find("s:version", ns).text == info["CFBundleVersion"])
assert item.find("s:shortVersionString", ns).text == version
enclosure = item.find("enclosure")
signature = enclosure.attrib["{" + ns["s"] + "}edSignature"]
archive = root.parent / f"outputs/NotesPlus-{version}-macOS-arm64.zip"
assert enclosure.attrib["url"] == f"https://github.com/Recrude/NotesPlus/releases/download/v{version}/{archive.name}"
assert int(enclosure.attrib["length"]) == archive.stat().st_size
with zipfile.ZipFile(archive) as bundle:
    packaged = plistlib.loads(bundle.read("NotesPlus.app/Contents/Info.plist"))
    assert packaged == info
    assert packaged["SURequireSignedFeed"] and packaged["SUVerifyUpdateBeforeExtraction"]
    assert not packaged["SUAllowsAutomaticUpdates"]
    assert not packaged["SUEnableSystemProfiling"]
sparkle = subprocess.check_output(["bash", str(root / "Tools/fetch-sparkle.sh")], text=True).strip()
verify = [str(Path(sparkle) / "bin/sign_update"), "--account", "dev.notesplus.updates", "--verify"]
subprocess.run(verify + [str(feed)], check=True, capture_output=True)
subprocess.run(verify + [str(archive), signature], check=True, capture_output=True)
with tempfile.TemporaryDirectory(prefix="verify-release-", dir=root / "build") as folder:
    corrupt = Path(folder) / "tampered.zip"
    corrupt.write_bytes(archive.read_bytes() + b"x")
    assert subprocess.run(verify + [str(corrupt), signature], capture_output=True).returncode != 0
    corrupt = Path(folder) / "tampered.xml"
    changed = feed.read_bytes().replace(f"<title>{version}</title>".encode(), b"<title>altered</title>")
    assert changed != feed.read_bytes()
    corrupt.write_bytes(changed)
    assert subprocess.run(verify + [str(corrupt)], capture_output=True).returncode != 0
print("PASS: release metadata, bundle configuration, ZIP and feed signatures, tampered ZIP/feed rejection")
