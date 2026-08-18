"""Alias generation for food names.

The Food Normalization stage resolves a free-text label to a stable
``food_id``. INDB names carry embedded aliases (e.g. ``Potato parantha/paratha
(Aloo ka parantha/paratha)``), so aliases are derived from each food name by:

- adding the normalized full name,
- adding the name with its parenthetical dropped (primary phrase),
- expanding each slash group into alternatives — handling BOTH shared-prefix
  forms (``parantha/paratha`` -> ``parantha``, ``paratha``) and shared-suffix
  forms (``Suji/Rava daliya`` -> ``Suji daliya``, ``Rava daliya``), and
- dropping Hindi genitives (``ka``/``ki``/``ke``) to yield short variants
  such as ``aloo parantha`` / ``aloo paratha``.

This is what lets a query such as ``Aloo paratha`` resolve to food ``ASC098``
even though the canonical name is ``Potato parantha/paratha (Aloo ka
parantha/paratha)``.
"""

import re
from typing import Iterable

from app.models.food import Food

_GENITIVE_RE = re.compile(r" (ka|ki|ke) ")


def normalize_alias(name: str) -> str:
    """Lowercase, collapse whitespace and trim an alias/label."""
    return " ".join(name.strip().lower().split())


def _word_count(phrase: str) -> int:
    return len(phrase.split()) if phrase.strip() else 0


def _slash_variants(phrase: str) -> set[str]:
    """Return all spellings produced by expanding slash groups in ``phrase``.

    A slash group ``a/b/c`` is interpreted as alternatives sharing either a
    common prefix (``plain parantha/paratha``) or a common suffix
    (``Suji/Rava daliya``); both interpretations are generated, which is
    enough for every slash form found in INDB.
    """
    parts = [normalize_alias(p) for p in phrase.split("/")]
    parts = [p for p in parts if p]
    if not parts:
        return set()
    if len(parts) == 1:
        return set(parts)

    first, last = parts[0], parts[-1]
    variants = set(parts)

    # Shared prefix: base is the first segment; later segments replace its
    # final word. -> "plain parantha", "plain paratha".
    prefix = " ".join(first.split()[:-1]) if first else ""
    if prefix:
        for alt in parts:
            variants.add(normalize_alias(f"{prefix} {alt}"))

    # Shared suffix: base is the last segment; earlier segments replace its
    # first word. -> "suji daliya", "rava daliya".
    suffix = " ".join(last.split()[1:]) if last else ""
    if suffix:
        for alt in parts:
            variants.add(normalize_alias(f"{alt} {suffix}"))

    return {v for v in variants if v}


def _drop_genitives(phrase: str) -> set[str]:
    variants = {phrase}
    while True:
        next_round = set(variants)
        for v in tuple(variants):
            next_round.add(normalize_alias(_GENITIVE_RE.sub(" ", v)))
        if next_round <= variants:
            break
        variants = next_round
    return {v for v in variants if v}


def expand_aliases(food_name: str) -> set[str]:
    """Return the normalized alias variants for a single food name."""
    normalized = normalize_alias(food_name)
    aliases: set[str] = {normalized}

    open_idx = normalized.find(" (")
    if open_idx == -1:
        aliases.update(_slash_variants(normalized))
        for v in list(aliases):
            aliases.update(_drop_genitives(v))
        return aliases

    primary = normalize_alias(normalized[:open_idx])
    inner = normalized[normalized.find("(") + 1 : normalized.rfind(")")]
    inner = normalize_alias(inner)

    aliases.add(primary)
    aliases.update(_slash_variants(primary))
    aliases.update(_slash_variants(inner))

    for source in list(aliases):
        aliases.update(_drop_genitives(source))

    return {a for a in aliases if a}


def build_alias_map(foods: Iterable[Food]) -> dict[str, str]:
    """Build a canonical ``alias -> food_id`` map.

    Collisions (two foods generating the same alias) keep the first mapping,
    resolved deterministically by ``food_id``.
    """
    alias_map: dict[str, str] = {}
    for food in sorted(foods, key=lambda f: f.food_id):
        for alias in expand_aliases(food.food_name):
            alias_map.setdefault(alias, food.food_id)
    return alias_map