#!/usr/bin/env python3
"""Read pinned ELF constants/function-value slots. Never load or execute Central."""
import hashlib
import json
import struct
import sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()
if hashlib.sha256(data).hexdigest() != "07d76becc367762e31f59ecbf744a967ce5ef1cbf395b4fc05835e6fb244a042":
    raise SystemExit("Expected fixed official Central 1.11.0 ELF")
offset = struct.unpack_from("<Q", data, 40)[0]
size, count = struct.unpack_from("<HH", data, 58)
sections = [struct.unpack_from("<IIQQQQIIQQ", data, offset + size * i) for i in range(count)]


def read(address, length):
    for section in sections:
        # Exclude NOBITS sections: virtual bytes are not bytes in this artifact.
        if section[1] != 8 and section[3] <= address and address + length <= section[3] + section[5]:
            start = section[4] + address - section[3]
            return data[start:start + length]
    raise ValueError("Address outside fixed file sections")


def pointer(address):
    return struct.unpack("<Q", read(address, 8))[0]


expected = {
    "productionOAuthBase": (0xe891c9, "https://oauth.account.jetbrains.com"),
    "productionAIAuthBase": (0xe79df8, "https://auth.grazie.ai"),
    "productionQuotaBase": (0xe7c24d, "https://api.jetbrains.ai"),
    "originalPublicClient": (0xe6e2d1, "central-cli"),
    "tokenPathFormat": (0xe72466, "%s/oauth2/token"),
    "registerPathFormat": (0xe83b02, "%s/auth/jetbrains-jwt/register"),
    "providePathFormat": (0xe961ab, "%s/auth/jetbrains-jwt/provide-access/license/v2"),
}
constants = {}
for name, (address, text) in expected.items():
    actual = read(address, len(text.encode())).decode()
    if actual != text:
        raise ValueError("Pinned constant differs: " + name)
    constants[name] = {"address": hex(address), "length": len(text.encode()), "value": actual}

functions = {
    "importJCPTransfer.refresh": (0x16b1e00, 0x8eb1c0),
    "completeLicenseLogin.signIn": (0x16b1d58, 0x8ec240),
    "fallback.fastAIRefresh": (0x16b1cc8, 0x8eb540),
    "fallback.JBARefresh": (0x16b1cc0, 0x8eb1c0),
    "fallback.SignInJBAI": (0x16b1cd0, 0x8ec240),
}
slots = {}
for name, (slot, target) in functions.items():
    actual = pointer(pointer(slot))
    if actual != target:
        raise ValueError("Pinned function value differs: " + name)
    slots[name] = {"slot": hex(slot), "functionValue": hex(pointer(slot)), "target": hex(actual)}

print(json.dumps({"binarySHA256": hashlib.sha256(data).hexdigest(), "constants": constants,
                  "functionValues": slots}, indent=2, sort_keys=True))
