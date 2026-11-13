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
    # Validate automatic source discovery, complete subsystem coverage,
    # duplicate test targets, and every tool without fixed file counts.
    source_dirs = set(re.findall(
        r'"\$\{NATIVE_ROOT\}/([A-Za-z]+)/\*\.cpp"', cmake))
    actual_sources = [
        path for path in paths
        if re.fullmatch(r"Kernel/[A-Za-z]+/[A-Za-z0-9_]+\.cpp", path)
        and not path.startswith("Kernel/Tools/")
    ]
    actual_dirs = {path.split("/")[1] for path in actual_sources}
    if not actual_sources or source_dirs != actual_dirs:
        issues.append(f"CMake native glob mismatch: declared {sorted(source_dirs)}, "
                      f"found {sorted(actual_dirs)}")
    if "file(GLOB NATIVE_SOURCES CONFIGURE_DEPENDS" not in cmake:
        issues.append("Native CMake must discover newly added sources")
    test_glob = '"${NATIVE_TEST_ROOT}/*/test_*.cpp"'
    if test_glob not in cmake or "file(GLOB NATIVE_TEST_SOURCES CONFIGURE_DEPENDS" not in cmake:
        issues.append("Native CMake must discover newly added tests")
    native_tests = [
        path for path in paths
        if re.fullmatch(r"NativeTests/[A-Za-z]+/test_[a-z0-9_]+\.cpp", path)
    ]
    test_names = [Path(path).stem for path in native_tests]
    if not native_tests or len(test_names) != len(set(test_names)):
        issues.append("No native tests or duplicate native test target names")
    if "NativeTests/Common/test_common.h" not in files:
        issues.append("Native test assertions header is missing")

    declared_tools = set(re.findall(
        r'aerospatial_add_tool\([\w-]+\s+([a-z_]+\.cpp)\)', cmake))
    if 'add_executable(aerospatial-fuzz "${NATIVE_ROOT}/Tools/fuzz_parsers.cpp")' in cmake:
        declared_tools.add("fuzz_parsers.cpp")
    actual_tools = {
        Path(path).name for path in paths
        if re.fullmatch(r"Kernel/Tools/[a-z_]+\.cpp", path)
    }
    if declared_tools != actual_tools:
        issues.append(f"Native tool registration mismatch: declared "
                      f"{sorted(declared_tools)}, found {sorted(actual_tools)}")

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
    print("Layout OK: shallow folders, dynamic C++ registration, Python imports and Markdown links verified.")
