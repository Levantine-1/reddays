#!/usr/bin/env python3
"""RedDays test runner.

Runs the Lua behavioural suites inside LuaJIT (via lupa) and then the static
checks. Exit code is non-zero if anything failed.

    python tests/run.py                 # everything
    python tests/run.py --lua-only      # just the behavioural suites
    python tests/run.py --static-only   # just the static checks
    python tests/run.py -k cycle        # only suites whose filename matches
"""

import argparse
import sys
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TESTS_DIR.parent
sys.path.insert(0, str(TESTS_DIR))

from static.sandbox_parser import parse_sandbox_options, defaults_table  # noqa: E402

DEFAULT_VERSION = "42.20"


def mod_media_dir(version):
    return REPO_ROOT / "Contents" / "mods" / "RedDays" / version / "media"


def build_runtime(version):
    try:
        from lupa import luajit21 as lua_impl
    except ImportError:
        try:
            import lupa as lua_impl
        except ImportError:
            sys.exit(
                "lupa is not installed. Run:  pip install lupa\n"
                "It provides LuaJIT 2.1 (Lua 5.1 semantics), which is what PZ's "
                "Kahlua VM targets."
            )
    return lua_impl.LuaRuntime(unpack_returned_tuples=True)


def lua_path_for(tests_dir):
    lua_root = (tests_dir / "lua").as_posix()
    return f"{lua_root}/?.lua;{lua_root}/?/init.lua"


def run_lua_suites(version, name_filter):
    media = mod_media_dir(version)
    if not media.is_dir():
        sys.exit(f"No such mod version directory: {media}")

    options = parse_sandbox_options(media / "sandbox-options.txt")
    sandbox = defaults_table(options)

    rt = build_runtime(version)
    rt.execute(f'package.path = "{lua_path_for(TESTS_DIR)};" .. package.path')

    suite_files = sorted((TESTS_DIR / "lua" / "suites").glob("*_spec.lua"))
    if name_filter:
        suite_files = [p for p in suite_files if name_filter in p.name]
    if not suite_files:
        print("No suites matched.")
        return 0, 0, []

    config = rt.table_from(
        {
            "luaRoot": (media / "lua").as_posix(),
            "mediaRoot": media.as_posix(),
            "repoRoot": REPO_ROOT.as_posix(),
            "version": version,
            "sandbox": sandbox,
        },
        recursive=True,
    )
    rt.globals()["RD_TEST_CONFIG"] = config

    runner = rt.eval('require "runner"')
    lines = []
    rt.globals()["RD_TEST_OUT"] = lambda line: lines.append(line)

    load_errors = []
    for path in suite_files:
        posix = path.as_posix()
        ok, err = rt.execute(
            f"""
            local chunk, err = loadfile("{posix}")
            if not chunk then return false, err end
            local ok, runErr = pcall(chunk)
            if not ok then return false, runErr end
            return true, nil
            """
        )
        if not ok:
            load_errors.append((path.name, str(err)))

    summary = runner.run(rt.globals()["RD_TEST_OUT"])

    for line in lines:
        print(line)

    failures = []
    if summary.failures:
        for i in range(1, len(summary.failures) + 1):
            f = summary.failures[i]
            failures.append((f.suite, f.test, f.err))

    passed = int(summary.passed)
    failed = int(summary.failed) + len(load_errors)

    if load_errors:
        print()
        for name, err in load_errors:
            print(f"SUITE FAILED TO LOAD: {name}\n  {err}")

    if failures:
        print("\n" + "=" * 70)
        print("FAILURES")
        print("=" * 70)
        for suite, test, err in failures:
            print(f"\n{suite} > {test}\n{err}")

    return passed, failed, failures


def run_static_checks(version):
    from static import check_api_contract, check_sandbox_translations, check_syntax

    media = mod_media_dir(version)
    total_errors = 0

    for label, module in (
        ("syntax", check_syntax),
        ("sandbox + translations", check_sandbox_translations),
        ("vanilla API contract", check_api_contract),
    ):
        print(f"\n--- static: {label} ---")
        total_errors += module.run(REPO_ROOT, media)

    return total_errors


def main():
    parser = argparse.ArgumentParser(description="RedDays test runner")
    parser.add_argument("--version", default=DEFAULT_VERSION,
                        help=f"mod version folder to test (default {DEFAULT_VERSION})")
    parser.add_argument("--lua-only", action="store_true", help="skip static checks")
    parser.add_argument("--static-only", action="store_true", help="skip Lua suites")
    parser.add_argument("-k", "--filter", default=None, help="only suites matching this substring")
    args = parser.parse_args()

    passed = failed = 0
    static_errors = 0

    if not args.static_only:
        print(f"=== behavioural suites ({args.version}) ===\n")
        passed, failed, _ = run_lua_suites(args.version, args.filter)

    if not args.lua_only:
        static_errors = run_static_checks(args.version)

    print("\n" + "=" * 70)
    if not args.static_only:
        print(f"tests:  {passed} passed, {failed} failed")
    if not args.lua_only:
        print(f"static: {static_errors} error(s)")
    print("=" * 70)

    return 1 if (failed or static_errors) else 0


if __name__ == "__main__":
    sys.exit(main())
