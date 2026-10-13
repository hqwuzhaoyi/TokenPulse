#!/usr/bin/env python3
"""Re-read locked public GitHub source and release assets; never access credentials or login.

Run: python3 .scratch/provider-expansion/research/verify-public-evidence.py
Only GETs of fixed public source paths/release URLs are made (gh fallback on GitHub rate limit). No source
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
from urllib.parse import urlparse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", help="Only check one repository from the source lock")
    parser.add_argument("--large-artifacts", action="store_true", help="Also re-download/hash fixed large public release archives (never execute them)")
    args = parser.parse_args()
    entries = json.loads(Path(__file__).with_name("public-source-lock.json").read_text())
    if args.repo:
        entries = [entry for entry in entries if entry["repo"] == args.repo]
        if not entries:
            parser.error("Repository is not in the public source lock")
    failed = 0
    skipped = 0
    for entry in entries:
        if entry.get("largeArtifact") and not args.large_artifacts:
            print("SKIP_LARGE", entry["repo"], entry["path"], "use --large-artifacts to verify")
            skipped += 1
            continue
        url = entry.get("url") or "https://raw.githubusercontent.com/{repo}/{commit}/{path}".format(**entry)
        try:
            parsed = urlparse(url)
            if parsed.scheme != "https" or parsed.username or parsed.password or parsed.query or parsed.fragment:
                raise ValueError("Source lock must contain a credential-free public HTTPS path")
            algorithm = "sha512" if "sha512" in entry else "sha256"
            limit = 256_000_000 if entry.get("largeArtifact") else 16_000_000
            request = Request(url, headers={"User-Agent": "TokenPulse-public-source-audit"})
            try:
                with urlopen(request, timeout=20) as response:
                    hasher = hashlib.new(algorithm)
                    total = 0
                    while chunk := response.read(262_144):
                        total += len(chunk)
                        if total > limit:
                            raise ValueError("Public source exceeds bounded audit size")
                        hasher.update(chunk)
                    digest = hasher.hexdigest()
            except HTTPError as error:
                if error.code != 429 or entry.get("url"):
                    raise
                route = "repos/{repo}/contents/{path}?ref={commit}".format(**entry)
                result = subprocess.run(
                    ["gh", "api", route, "--jq", ".content"],
                    capture_output=True, check=True, timeout=20,
                )
                content = base64.b64decode(result.stdout)
                digest = hashlib.new(algorithm, content).hexdigest()
            matches = digest == entry[algorithm]
            print(("OK" if matches else "MISMATCH"), entry["repo"], entry["path"])
            failed += not matches
        except Exception as error:
            print("FETCH_FAILED", entry["repo"], entry["path"], type(error).__name__)
            failed += 1
    print("Public sources:", len(entries), "checked:", len(entries) - skipped, "skipped large artifacts:", skipped, "failures:", failed)
    raise SystemExit(bool(failed))


if __name__ == "__main__":
    main()
