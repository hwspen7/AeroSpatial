#!/usr/bin/env python3
"""Check bounded source hierarchy and portable build/path contracts."""

from __future__ import annotations

from collections import Counter
from pathlib import Path
import importlib.util
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CAP = 12
PUBLIC_ABI_CAP = 15


def tracked_files() -> list[str]:
    output = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
    return [path.decode("utf-8") for path in output.split(b"\0") if path]


def check() -> list[str]:
    issues: list[str] = []
    paths = tracked_files()
    files = set(paths)
    per_folder = Counter()
    for name in paths:
        parts = name.split("/")
        if len(parts) > 3:
            issues.append(f"Too many levels: {name}")
        per_folder["/".join(parts[:-1]) or "."] += 1

    for folder, count in sorted(per_folder.items()):
        maximum = PUBLIC_ABI_CAP if folder == "Kernel/include" else DEFAULT_CAP
        if count > maximum:
            issues.append(f"Overcrowded folder: {folder} has {count} files (limit {maximum})")

    cmake = (ROOT / "Kernel/CMakeLists.txt").read_text(encoding="utf-8")
    native_sources = re.findall(r'\$\{NATIVE_ROOT\}/([A-Za-z]+/[A-Za-z0-9_]+\.cpp)', cmake)
    if len(native_sources) != 25 or len(set(native_sources)) != 25:
        issues.append("Native CMake source enumeration changed unexpectedly")
    for source in native_sources:
        if f"Kernel/{source}" not in files:
            issues.append(f"Missing CMake source: Kernel/{source}")

    groups = re.findall(r'set\(NATIVE_TEST_GROUP_([A-Za-z]+)\s+([^)]*)\)', cmake)
    tests = [f"NativeTests/{group}/test_{name}.cpp" for group, values in groups for name in values.split()]
    if len(tests) != 30 or len(set(tests)) != 30:
        issues.append("Native CMake test enumeration changed unexpectedly")
    for name in tests:
        if name not in files:
            issues.append(f"Missing CMake test: {name}")

    for name in ("probe", "wire_probe", "qos_probe",
                 "benchmark", "bus_benchmark", "estimation_benchmark", "work_benchmark"):
        if f"Kernel/Tools/{name}.cpp" not in files:
            issues.append(f"Missing native tool: Kernel/Tools/{name}.cpp")

    root_package = ROOT / "aerospatial_tools"
    if not (ROOT / "pyproject.toml").is_file():
        issues.append("Root Python pyproject.toml is missing")
    if not (root_package / "__init__.py").is_file():
        issues.append("Python package initializer is missing")

    sys.path.insert(0, str(ROOT))
    for source in sorted(files):
        if not source.startswith("aerospatial_tools/") or source.count("/") != 2:
            continue
        if not source.endswith(".py") or source.endswith("/__init__.py"):
            continue
        name = Path(source).stem
        if importlib.util.find_spec(f"aerospatial_tools.{name}") is None:
            issues.append(f"Broken compatibility import: aerospatial_tools.{name}")

    for path in paths:
        if not path.endswith(".md"):
            continue
        document = ROOT / path
        text = document.read_text(encoding="utf-8")
        for old in ("Toolkit/aerospatial_tools/", "Kernel/src/", "PYTHONPATH=Toolkit"):
            if old in text:
                issues.append(f"Stale reference in {path}: {old}")
        for ref in re.findall(r'\]\(([^)\s]+)\)', text):
            if ref.startswith(("https:", "http:", "mailto:", "data:", "#")):
                continue
            target = ref.split("#", 1)[0]
            if not target.endswith(".md"):
                continue
            resolved = (document.parent / target).resolve()
            if not resolved.is_file():
                issues.append(f"Broken local Markdown link: {path} -> {ref}")

    return issues


if __name__ == "__main__":
    findings = check()
    if findings:
        print("\n".join(f"ERROR: {finding}" for finding in findings), file=sys.stderr)
        raise SystemExit(1)
    print("Layout OK: max depth 2, bounded folders, 25 C++ sources, 30 native tests, and Markdown links verified.")
