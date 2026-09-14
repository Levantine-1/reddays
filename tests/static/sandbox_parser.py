"""Parse the mod's real sandbox-options.txt.

Both the Lua harness (via run.py) and check_sandbox_translations.py read sandbox
values through here, so test defaults can never drift from what actually ships.
"""

import re

# option RedDays.some_name
# {
#     type = integer,
#     min = 0,
#     max = 100,
#     default = 30,
#     page = RedDays,
#     translation = RedDays_some_name,
# }
_OPTION_RE = re.compile(
    r"option\s+RedDays\.(?P<name>\w+)\s*\{(?P<body>[^}]*)\}",
    re.MULTILINE,
)
_FIELD_RE = re.compile(r"(\w+)\s*=\s*([^,\n]+?)\s*,?\s*$", re.MULTILINE)


def _coerce(raw):
    """Turn a raw script value into a Python bool/int/float/str."""
    if raw == "true":
        return True
    if raw == "false":
        return False
    try:
        return int(raw)
    except ValueError:
        pass
    try:
        return float(raw)
    except ValueError:
        pass
    return raw


def parse_sandbox_options(path):
    """Return {name: {type, default, min, max, translation}} in file order."""
    text = path.read_text(encoding="utf-8", errors="replace")
    options = {}
    for match in _OPTION_RE.finditer(text):
        name = match.group("name")
        fields = {}
        for key, raw in _FIELD_RE.findall(match.group("body")):
            fields[key] = _coerce(raw.strip())
        options[name] = fields
    return options


def defaults_table(options):
    """Just {name: default} -- what SandboxVars.RedDays looks like at runtime."""
    return {name: fields.get("default") for name, fields in options.items()}
