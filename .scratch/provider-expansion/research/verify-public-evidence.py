#!/usr/bin/env python3
"""Re-read locked public GitHub source; never access provider credentials or login.

Run: python3 .scratch/provider-expansion/research/verify-public-evidence.py
Only GETs of fixed public source paths are made (gh API fallback on CDN rate limit). No source
body, OAuth constants, account data, or credential values are printed or stored.
This verifies research provenance, not API compatibility or account acceptance.
"""
import argparse
import base64
import hashlib
import json
import subprocess
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", help="Only check one repository from the source lock")
    args = parser.parse_args()
    entries = json.loads(Path(__file__).with_name("public-source-lock.json").read_text())
    if args.repo:
        entries = [entry for entry in entries if entry["repo"] == args.repo]
        if not entries:
            parser.error("Repository is not in the public source lock")
    failed = 0
    for entry in entries:
        url = "https://raw.githubusercontent.com/{repo}/{commit}/{path}".format(**entry)
        try:
            request = Request(url, headers={"User-Agent": "TokenPulse-public-source-audit"})
            try:
                with urlopen(request, timeout=20) as response:
                    content = response.read()
            except HTTPError as error:
                if error.code != 429:
                    raise
                route = "repos/{repo}/contents/{path}?ref={commit}".format(**entry)
                result = subprocess.run(
                    ["gh", "api", route, "--jq", ".content"],
                    capture_output=True, check=True, timeout=20,
                )
                content = base64.b64decode(result.stdout)
            digest = hashlib.sha256(content).hexdigest()
            matches = digest == entry["sha256"]
            print(("OK" if matches else "MISMATCH"), entry["repo"], entry["path"])
            failed += not matches
        except Exception as error:
            print("FETCH_FAILED", entry["repo"], entry["path"], type(error).__name__)
            failed += 1
    print("Public sources:", len(entries), "failures:", failed)
    raise SystemExit(bool(failed))


if __name__ == "__main__":
    main()
