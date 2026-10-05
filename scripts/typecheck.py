#!/usr/bin/env python3
"""Check iPhone sources without requiring a bootable simulator runtime.

This checks types and concurrency. It does not build assets, link the app,
run UI tests, or replace an Xcode build.
"""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]


def resolve(*arguments):
    return subprocess.check_output(["xcrun", *arguments], text=True).strip()


def check(arguments):
    subprocess.run(arguments, cwd=ROOT, check=True)


def main():
    compiler = resolve("--find", "swiftc")
    iphone_sdk = resolve("--sdk", "iphoneos", "--show-sdk-path")
    simulator_sdk = pathlib.Path(resolve("--sdk", "iphonesimulator", "--show-sdk-path"))
    platform_developer = simulator_sdk.parent.parent
    sources = sorted(str(path.relative_to(ROOT)) for path in (ROOT / "Shiplog").rglob("*.swift"))
    base = [compiler, "-typecheck", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete"]
    for configuration in ("Release", "Debug"):
        arguments = base + ["-sdk", iphone_sdk, "-target", "arm64-apple-ios18.0", "-module-name", "Shiplog"]
        if configuration == "Debug":
            arguments += ["-D", "DEBUG"]
        check(arguments + sources)
        print(f"{configuration} iPhone source type check passed.", flush=True)
    check(base + [
        "-sdk", str(simulator_sdk), "-target", "arm64-apple-ios18.0-simulator",
        "-F", str(platform_developer / "Library/Frameworks"),
        "-I", str(platform_developer / "usr/lib"),
        "ShiplogUITests/ShiplogUITests.swift",
    ])
    print("Native UI-test source type check passed; tests were not executed.", flush=True)


if __name__ == "__main__":
    main()
