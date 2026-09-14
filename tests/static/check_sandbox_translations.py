"""Cross-check sandbox options, item/recipe/moodle names, and their translations.

This targets bug classes the mod has actually shipped: the missing
RecipeName.json (every recipe showed its raw script name in game) and the
"Missing translation CraftPeriodTracker" report. None of these throw an error in
game -- they just render wrong -- so nothing but a check like this catches them.
"""

import json
import re
from pathlib import Path

from .sandbox_parser import parse_sandbox_options
from .luasource import strip_comments

# How the mod reads sandbox values:
#   SandboxVars.RedDays.foo
#   sbv.foo / sb.foo      (locals assigned from the above)
#   getSandbox().foo
_SANDBOX_READ_PATTERNS = [
    re.compile(r"SandboxVars\.RedDays\.(\w+)"),
    re.compile(r"\bsbv?\.(\w+)"),
    re.compile(r"getSandbox\(\)\.(\w+)"),
]

# A top-level item definition is `item Name` alone on the line; recipe ingredient
# lines look like `item 1 RedDays.Tampon,` and must not be picked up.
_ITEM_DEF = re.compile(r"^\s*item\s+([A-Za-z_]\w*)\s*$", re.MULTILINE)
_RECIPE_DEF = re.compile(r"^\s*craftRecipe\s+([A-Za-z_]\w*)\s*$", re.MULTILINE)
_MOODLE_DEF = re.compile(r"""createMoodle\(\s*["'](\w+)["']""")


def _load_json(path):
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def _lua_sources(media_dir):
    return sorted((media_dir / "lua").rglob("*.lua"))


def run(repo_root, media_dir):
    repo_root, media_dir = Path(repo_root), Path(media_dir)
    translate = media_dir / "lua" / "shared" / "Translate" / "EN"
    errors = 0
    warnings = 0

    # ---------- sandbox options ----------
    options = parse_sandbox_options(media_dir / "sandbox-options.txt")
    declared = set(options)

    read_names = {}
    for path in _lua_sources(media_dir):
        # Comments stripped first: a commented-out read is not a read. The
        # spawn-rate multiplier in RedDays_ProceduralDistributions.lua is exactly
        # that case and would otherwise report as an undeclared option.
        text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        for pattern in _SANDBOX_READ_PATTERNS:
            for name in pattern.findall(text):
                read_names.setdefault(name, set()).add(path.name)

    undeclared = sorted(set(read_names) - declared)
    for name in undeclared:
        where = ", ".join(sorted(read_names[name]))
        print(f"  ERROR  sandbox option '{name}' is read in {where} but not declared "
              f"in sandbox-options.txt (it will be nil in game)")
        errors += 1

    unused = sorted(declared - set(read_names))
    for name in unused:
        print(f"  warn   sandbox option '{name}' is declared but never read in Lua")
        warnings += 1

    # ---------- sandbox translations ----------
    sandbox_json = _load_json(translate / "Sandbox.json")
    if sandbox_json is None:
        print("  ERROR  Translate/EN/Sandbox.json is missing")
        errors += 1
    else:
        for name in sorted(declared):
            for suffix, label in (("", "name"), ("_tooltip", "tooltip")):
                key = f"Sandbox_RedDays_{name}{suffix}"
                if key not in sandbox_json:
                    print(f"  ERROR  sandbox option '{name}' has no {label} translation "
                          f"(missing key '{key}')")
                    errors += 1

    print(f"  sandbox: {len(declared)} options declared, "
          f"{len(declared) - len(unused)} read in Lua")

    # ---------- items ----------
    item_names = set()
    scripts_dir = media_dir / "scripts"
    for path in sorted(scripts_dir.rglob("*.txt")):
        text = path.read_text(encoding="utf-8", errors="replace")
        if re.search(r"^\s*module\s+RedDays\s*$", text, re.MULTILINE):
            item_names.update(_ITEM_DEF.findall(text))

    item_json = _load_json(translate / "ItemName.json") or {}
    for name in sorted(item_names):
        key = f"RedDays.{name}"
        if key not in item_json:
            print(f"  ERROR  item '{name}' has no ItemName.json entry (key '{key}')")
            errors += 1
    print(f"  items: {len(item_names)} defined, {len(item_json)} translated")

    # ---------- recipes ----------
    recipe_names = set()
    for path in sorted(scripts_dir.rglob("*.txt")):
        text = path.read_text(encoding="utf-8", errors="replace")
        recipe_names.update(_RECIPE_DEF.findall(text))

    recipe_json = _load_json(translate / "RecipeName.json")
    if recipe_json is None:
        if recipe_names:
            print(f"  ERROR  {len(recipe_names)} recipes defined but "
                  f"Translate/EN/RecipeName.json does not exist "
                  f"(recipes show their raw script name in game)")
            errors += 1
        recipe_json = {}
    for name in sorted(recipe_names):
        if name not in recipe_json:
            print(f"  ERROR  recipe '{name}' has no RecipeName.json entry")
            errors += 1
    print(f"  recipes: {len(recipe_names)} defined, {len(recipe_json)} translated")

    # ---------- moodles ----------
    moodle_names = set()
    for path in _lua_sources(media_dir):
        moodle_names.update(_MOODLE_DEF.findall(
            path.read_text(encoding="utf-8", errors="replace")))

    moodle_json = _load_json(translate / "Moodles.json") or {}

    # Moodles legitimately define only the levels they can actually reach -- a
    # panty liner never reaches the low Bloody levels, so requiring lvl1 would be
    # wrong. What must hold is: at least one level exists, and every level has
    # BOTH a title and a description (one without the other renders blank).
    titles, descriptions = {}, {}
    for key in moodle_json:
        match = re.match(r"Moodles_(\w+?)_Bad_(desc_)?lvl(\d+)$", key)
        if not match:
            continue
        name, is_desc, level = match.group(1), bool(match.group(2)), int(match.group(3))
        (descriptions if is_desc else titles).setdefault(name, set()).add(level)

    for name in sorted(moodle_names):
        levels = titles.get(name, set()) | descriptions.get(name, set())
        if not levels:
            print(f"  ERROR  moodle '{name}' is created in Lua but has no "
                  f"Moodles.json entries at all")
            errors += 1
            continue
        for level in sorted(levels):
            if level not in titles.get(name, set()):
                print(f"  ERROR  moodle '{name}' level {level} has a description "
                      f"but no title (key 'Moodles_{name}_Bad_lvl{level}')")
                errors += 1
            if level not in descriptions.get(name, set()):
                print(f"  ERROR  moodle '{name}' level {level} has a title but no "
                      f"description (key 'Moodles_{name}_Bad_desc_lvl{level}')")
                errors += 1

    print(f"  moodles: {len(moodle_names)} created in Lua, all with paired title/description")

    if warnings:
        print(f"  ({warnings} warning(s) -- not counted as failures)")

    return errors
