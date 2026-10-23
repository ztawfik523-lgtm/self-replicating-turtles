"""Fail CI if the controller installer is pinned to stale or missing source."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def test_installer_pin_matches_the_current_turtle_sources():
    code=(ROOT/"controller/install.lua").read_text(encoding="utf-8")
    match=re.search(r"local PINNED_REV='([a-f0-9]{40})'",code)
    assert match, "Installer must be pinned to a 40-character Git SHA"
    revision=match.group(1)
    files_match=re.search(r"local paths=\{(.*?)\n\}",code,re.S)
    assert files_match, "Cannot find install manifest"
    paths=re.findall(r"'([^']+\.lua)'",files_match.group(1))
    assert len(paths)>=18 and len(paths)==len(set(paths))
    assert "tg/workshop.lua" in paths and "tg/worker.lua" in paths
    assert "tg/worker-entry.lua" in paths and "startup.lua" in paths
    for path in paths:
        current=(ROOT/path).read_bytes()
        pinned=subprocess.check_output(["git","show",f"{revision}:{path}"],cwd=ROOT)
        assert current==pinned, f"Installer would download stale {path}"
