"""Parse-check every Lua file in every version folder.

Uses the same LuaJIT (5.1) front end the suites run under, so a file that parses
here parses in game. Replaces the ad-hoc block-balance checking used previously.
"""

from pathlib import Path


def _load_runtime():
    try:
        from lupa import luajit21 as lua_impl
    except ImportError:
        import lupa as lua_impl
    return lua_impl.LuaRuntime(unpack_returned_tuples=True)


def run(repo_root, media_dir=None):
    repo_root = Path(repo_root)
    mods_root = repo_root / "Contents" / "mods" / "RedDays"

    lua_files = sorted(mods_root.glob("*/media/**/*.lua"))
    if not lua_files:
        print("  no Lua files found")
        return 0

    rt = _load_runtime()
    # loadstring returns ONE value on success and TWO on failure; normalise the
    # arity so the Python side can always unpack a pair.
    parse = rt.eval(
        """
        function(source, chunkname)
            local chunk, err = loadstring(source, chunkname)
            if chunk then return true, "" end
            return false, tostring(err)
        end
        """
    )

    errors = 0
    by_version = {}
    for path in lua_files:
        # Contents/mods/RedDays/<version>/media/...
        version = path.relative_to(mods_root).parts[0]
        by_version.setdefault(version, [0, 0])

        source = path.read_text(encoding="utf-8", errors="replace")
        ok, err = parse(source, str(path))
        by_version[version][1] += 1
        if not ok:
            errors += 1
            by_version[version][0] += 1
            rel = path.relative_to(repo_root).as_posix()
            print(f"  SYNTAX ERROR  {rel}\n                {err}")

    for version in sorted(by_version):
        bad, total = by_version[version]
        status = "OK" if bad == 0 else f"{bad} FAILED"
        print(f"  {version}: {total - bad}/{total} parse {status}")

    return errors
