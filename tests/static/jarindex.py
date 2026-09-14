"""Index the identifiers inside projectzomboid.jar, with an on-disk cache.

There is no JDK in the PZ install (no javap), so method names are recovered by
scanning the compiled classes for constant-pool strings. That is deliberately
fuzzy -- it answers "does this name exist anywhere in the engine", which is
exactly the question that matters when a build bumps and a method disappears.
"""

import gzip
import os
import re
import zipfile
from pathlib import Path

# Where PZ is installed. Overridable for a different machine or a second install.
DEFAULT_JAR = Path(
    os.environ.get(
        "PZ_JAR",
        r"D:\SteamLibrary\steamapps\common\ProjectZomboid\projectzomboid.jar",
    )
)

CACHE_DIR = Path(__file__).resolve().parent.parent / ".jarindex-cache"

# Java identifiers, two chars or more. Two matters: ResourceLocation.of() is a
# real engine call and a three-char floor would silently miss it.
_IDENT = re.compile(rb"[A-Za-z_$][A-Za-z0-9_$]{1,63}")


def _cache_path(jar_path):
    stat = jar_path.stat()
    key = f"{jar_path.name}-{stat.st_size}-{int(stat.st_mtime)}"
    return CACHE_DIR / f"{key}.txt.gz"


def build_index(jar_path=None, verbose=True):
    """Return a set of identifier strings found in the jar, or None if absent."""
    jar_path = Path(jar_path or DEFAULT_JAR)
    if not jar_path.is_file():
        return None

    cache = _cache_path(jar_path)
    if cache.is_file():
        with gzip.open(cache, "rt", encoding="utf-8") as handle:
            return set(handle.read().split("\n"))

    if verbose:
        print(f"  building identifier index from {jar_path.name} (one-time, ~1 min)...")

    names = set()
    with zipfile.ZipFile(jar_path) as archive:
        for info in archive.infolist():
            if not info.filename.endswith(".class"):
                continue
            try:
                data = archive.read(info)
            except (zipfile.BadZipFile, RuntimeError):
                continue
            for match in _IDENT.finditer(data):
                names.add(match.group().decode("ascii"))

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    with gzip.open(cache, "wt", encoding="utf-8") as handle:
        handle.write("\n".join(sorted(names)))

    if verbose:
        print(f"  indexed {len(names)} identifiers (cached at {cache.name})")
    return names
