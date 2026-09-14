"""Verify every engine call the mod makes still exists in the game.

This is the guard against the B42.x migration pain documented in the repo: a
renamed or removed engine method is invisible until the moment it runs in game.
Findings are ADVISORY -- constant-pool matching is fuzzy, so an unmatched name is
a prompt to check, not proof of a bug.
"""

import re
from pathlib import Path

from .jarindex import build_index
from .luasource import strip_comments, strip_comments_and_strings

# item:hasTag("someString") -- confirmed via bytecode disassembly of InventoryItem/Food/
# DrainableComboItem: hasTag has ONLY (ItemTag) and (ItemTag[]) overloads, no String overload
# anywhere in the exposed API. Every one of the 57 real vanilla call sites passes an
# ItemTag.CONSTANT. A string argument throws "No implementation found for function: hasTag(...)"
# unconditionally, for any item -- this is hard-failed rather than advisory because it is
# ALWAYS wrong, not a fuzzy jar-lookup miss (confirmed the hard way: see RD_effects_pms.lua git
# history for the crash this produced on any item not covered by an earlier fast-path).
_HASTAG_STRING_ARG = re.compile(r':hasTag\s*\(\s*(["\'])')

# obj:method(  -- calls on an engine object
_METHOD_CALL = re.compile(r":(\w+)\s*\(")
# Class.method(  -- static-style calls (BloodClothingType.getCoveredParts, ...)
_STATIC_CALL = re.compile(r"\b([A-Z]\w*)\.(\w+)\s*\(")
# bare name(  -- candidate global engine function
_BARE_CALL = re.compile(r"(?<![\w.:])([a-z]\w{2,})\s*\(")

# Definitions inside the mod, in every form it uses.
_DEFINITIONS = [
    re.compile(r"function\s+[\w.]*[.:](\w+)\s*\("),
    re.compile(r"function\s+(\w+)\s*\("),
    re.compile(r"local\s+function\s+(\w+)\s*\("),
    re.compile(r"(\w+)\s*=\s*function\s*\("),
    # `local o_ISUnequipAction_perform = ISUnequipAction.perform` -- a local
    # holding a function value, later called by name.
    re.compile(r"local\s+(\w+)\s*="),
]

# Function parameters, which may themselves be callbacks invoked by name
# (RD_debugger.lua's defineAccessor takes rootGetter and normalizer).
_PARAM_LIST = re.compile(r"function\s*[\w.:]*\s*\(([^)]*)\)")
_PARAM_NAME = re.compile(r"[A-Za-z_]\w*")

# Lua standard library methods and globals -- not engine API.
_LUA_STDLIB = {
    # string methods
    "gsub", "format", "find", "rep", "lower", "upper", "sub", "len", "byte",
    "char", "match", "gmatch", "reverse",
    # table / math / base
    "concat", "insert", "remove", "sort", "unpack", "floor", "ceil", "abs",
    "min", "max", "random", "sqrt", "huge", "pairs", "ipairs", "type",
    "tostring", "tonumber", "print", "pcall", "xpcall", "error", "assert",
    "select", "setmetatable", "getmetatable", "rawget", "rawset", "require",
    "next", "string", "table", "math", "loadstring", "setfenv", "getfenv",
}

# Provided by other mods, not the base game.
_EXTERNAL = {
    "createMoodle", "getMoodle", "setThresholds", "setValue", "getValue",
}


def _collect(media_dir):
    """Returns (method_names, static_calls, bare_calls, defined_names)."""
    methods, statics, bares, defined = set(), set(), set(), set()

    for path in sorted((media_dir / "lua").rglob("*.lua")):
        # Strip comments AND strings: commented-out code is not a live call, and
        # a log line like print("obese (") otherwise reads as a call to obese().
        text = strip_comments_and_strings(
            path.read_text(encoding="utf-8", errors="replace"))

        for pattern in _DEFINITIONS:
            defined.update(pattern.findall(text))
        for params in _PARAM_LIST.findall(text):
            defined.update(_PARAM_NAME.findall(params))

        methods.update(_METHOD_CALL.findall(text))
        for cls, member in _STATIC_CALL.findall(text):
            statics.add((cls, member))
        bares.update(_BARE_CALL.findall(text))

    return methods, statics, bares, defined


def _check_hastag_string_args(repo_root, media_dir):
    """hasTag(String) is confirmed broken for every item, unconditionally -- hard error."""
    errors = 0
    for path in sorted((media_dir / "lua").rglob("*.lua")):
        # Comments stripped, but NOT strings -- we need to see the string literal itself.
        text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        if _HASTAG_STRING_ARG.search(text):
            rel = path.relative_to(repo_root).as_posix()
            print(f"  ERROR  {rel}: hasTag() called with a string literal -- hasTag only "
                  f"accepts an ItemTag object (e.g. ItemTag.FISH_MEAT); a string throws "
                  f"'No implementation found for function: hasTag(...)' for any item")
            errors += 1
    return errors


def run(repo_root, media_dir):
    repo_root, media_dir = Path(repo_root), Path(media_dir)
    index = build_index()

    if index is None:
        print("  skipped jar-based checks: projectzomboid.jar not found "
              "(set PZ_JAR to your install to enable them)")
        # This one needs no jar -- it's a pure source-pattern match -- so it still runs.
        return _check_hastag_string_args(repo_root, media_dir)

    methods, statics, bares, defined = _collect(media_dir)

    def is_modmade(name):
        return name in defined or name.startswith("RD_") or name.startswith("rd")

    unknown_methods = sorted(
        name for name in methods
        if not is_modmade(name)
        and name not in _LUA_STDLIB
        and name not in _EXTERNAL
        and name not in index
    )

    unknown_statics = sorted(
        (cls, member) for cls, member in statics
        if not is_modmade(member)
        and member not in _LUA_STDLIB
        and member not in _EXTERNAL
        and not cls.startswith("RD_")
        and member not in index
    )

    unknown_globals = sorted(
        name for name in bares
        if not is_modmade(name)
        and name not in _LUA_STDLIB
        and name not in _EXTERNAL
        and name not in index
    )

    checked = len(methods) + len(statics) + len(bares)
    print(f"  checked {checked} distinct call names against the game jar")

    for name in unknown_methods:
        print(f"  warn   engine method ':{name}()' not found in projectzomboid.jar")
    for cls, member in unknown_statics:
        print(f"  warn   static call '{cls}.{member}()' not found in projectzomboid.jar")
    for name in unknown_globals:
        print(f"  warn   global '{name}()' not found in projectzomboid.jar")

    total = len(unknown_methods) + len(unknown_statics) + len(unknown_globals)
    if total == 0:
        print("  every engine call resolves against the installed build")
    else:
        print(f"  {total} name(s) did not resolve -- advisory, verify before acting")

    # Everything above is advisory: constant-pool matching cannot distinguish a genuinely
    # missing method from one this heuristic simply failed to see. hasTag(String) is different
    # -- confirmed via bytecode to have zero String overloads, so it is hard-failed instead.
    return _check_hastag_string_args(repo_root, media_dir)
