#!/usr/bin/env python3
"""Check that public agent configuration survives Xcode's Info.plist processing."""
import argparse
import pathlib
import plistlib
from urllib.parse import urlparse

parser = argparse.ArgumentParser()
parser.add_argument("app", type=pathlib.Path)
parser.add_argument("--expected-url")
parser.add_argument("--build-number")
args = parser.parse_args()
with (args.app / "Info.plist").open("rb") as file:
    info = plistlib.load(file)
value = info.get("ShiplogAgentURL")
assert isinstance(value, str), "ShiplogAgentURL is missing from the packaged Info.plist"
if value:
    url = urlparse(value)
    assert url.scheme == "https" and url.hostname, "Agent URL must use HTTPS"
    assert not url.username and not url.password, "Agent URL must not embed credentials"
    assert url.path in ("", "/") and not url.query and not url.fragment, "Agent URL must be an origin"
if args.expected_url is not None:
    assert value == args.expected_url, "Packaged agent URL differs from the requested build setting"
if args.build_number:
    assert info.get("CFBundleVersion") == args.build_number, "Packaged build number differs from the requested build"
schemes = [scheme for item in info.get("CFBundleURLTypes", []) for scheme in item.get("CFBundleURLSchemes", [])]
assert "shiplog" in schemes, "GitHub callback scheme is not registered"
print("Packaged agent URL, callback scheme, and requested build identity verified.")
