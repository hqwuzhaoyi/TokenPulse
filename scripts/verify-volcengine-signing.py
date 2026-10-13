#!/usr/bin/env python3
"""Offline reference vectors derived independently from Volcengine's Python SDK.

Source: volcengine/volc-sdk-python d88be4d8028e35563b27ff1bafe3c1f7ed1ab656,
volcengine/auth/SignerV4.py and volcengine/util/Util.py. Inputs are synthetic;
this script performs no network request and reads no environment credentials.
"""
import hashlib
import hmac
from urllib.parse import parse_qsl, quote, urlsplit


def authorization(url, body=b""):
    stamp = "20260907T093000Z"
    day, region, service = stamp[:8], "cn-beijing", "ark"
    key_id, secret = "AKLTTestAccessKeyId", "dGVzdC1zZWNyZXQtYWNjZXNzLWtleQ=="
    parsed = urlsplit(url)
    query = "&".join("%s=%s" % (quote(k, safe="-_.~"), quote(v, safe="-_.~"))
                     for k, v in sorted(parse_qsl(parsed.query, keep_blank_values=True)))
    digest = hashlib.sha256(body).hexdigest()
    headers = {"content-type": "application/x-www-form-urlencoded; charset=utf-8",
               "host": "open.volcengineapi.com", "x-date": stamp, "x-content-sha256": digest}
    signed = ";".join(sorted(headers))
    canonical = "\n".join(["GET", quote(parsed.path or "/", safe="/-_.~"), query,
                             "".join(f"{k}:{headers[k]}\n" for k in sorted(headers)), signed, digest])
    scope = f"{day}/{region}/{service}/request"
    to_sign = "\n".join(["HMAC-SHA256", stamp, scope, hashlib.sha256(canonical.encode()).hexdigest()])
    key = secret.encode()
    for step in [day, region, service, "request"]:
        key = hmac.new(key, step.encode(), hashlib.sha256).digest()
    result = hmac.new(key, to_sign.encode(), hashlib.sha256).hexdigest()
    return f"HMAC-SHA256 Credential={key_id}/{scope}, SignedHeaders={signed}, Signature={result}"


if __name__ == "__main__":
    cases = [
        "https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01",
        "https://open.volcengineapi.com/?Version=2024-01-01&Action=GetAFPUsage",
        "https://open.volcengineapi.com/?Action=%E4%B8%AD%E6%96%87~%20x&Version=2024-01-01",
    ]
    assert authorization(cases[0]).endswith("3bc6ebb4fd6da065cae0c05dbfc35285cdced26090d7c0aea87b2f2330cd031d")
    for case in cases:
        print(authorization(case))
