"""Tests for common food aliases and enhanced normalization.

Verifies that Gemini-style food names resolve to INDB entries through the
common alias mapping, and that punctuation stripping works correctly.
"""

import pytest

from app.database.sqlite import normalize_label
from app.seed.food_aliases import FOOD_COMMON_ALIASES, normalize_alias, resolve_common_alias


# ---------------------------------------------------------------------------
# normalize_label (punctuation stripping)
# ---------------------------------------------------------------------------

class TestNormalizeLabel:
    def test_lowercase_and_trim(self):
        assert normalize_label("  Poha  ") == "poha"

    def test_collapse_whitespace(self):
        assert normalize_label("masala   dosa") == "masala dosa"

    def test_strip_commas(self):
        assert normalize_label("Biryani, chicken") == "biryani chicken"

    def test_strip_periods(self):
        assert normalize_label("roti.") == "roti"

    def test_preserves_slash(self):
        assert normalize_label("parantha/paratha") == "parantha/paratha"

    def test_mixed_punctuation(self):
        assert normalize_label("Dal (makhani)!") == "dal makhani"

    def test_empty_string(self):
        assert normalize_label("") == ""

    def test_only_punctuation(self):
        assert normalize_label("...") == ""


# ---------------------------------------------------------------------------
# normalize_alias (seed module consistency)
# ---------------------------------------------------------------------------

class TestNormalizeAlias:
    def test_lowercase_and_trim(self):
        assert normalize_alias("  Poha  ") == "poha"

    def test_strip_commas(self):
        assert normalize_alias("Biryani, chicken") == "biryani chicken"

    def test_preserves_slash(self):
        assert normalize_alias("parantha/paratha") == "parantha/paratha"

    def test_strip_exclamation(self):
        assert normalize_alias("Dosa!") == "dosa"


# ---------------------------------------------------------------------------
# resolve_common_alias
# ---------------------------------------------------------------------------

class TestResolveCommonAlias:
    def test_chapati_to_roti(self):
        assert resolve_common_alias("Chapati") == "roti"

    def test_chicken_biryani(self):
        assert resolve_common_alias("Chicken Biryani") == "chicken curry"

    def test_mutton_biryani(self):
        assert resolve_common_alias("Mutton Biryani") == "mutton biryani/biriyani"

    def test_paneer_butter_masala(self):
        assert resolve_common_alias("Paneer Butter Masala") == "shahi paneer"

    def test_rajma(self):
        assert resolve_common_alias("Rajma") == "kidney bean curry (rajmah curry)"

    def test_rajma_curry(self):
        assert resolve_common_alias("Rajma Curry") == "kidney bean curry (rajmah curry)"

    def test_aloo_paratha(self):
        result = resolve_common_alias("Aloo Paratha")
        assert result == "potato parantha/paratha (aloo ka parantha/paratha)"

    def test_dosa_returns_original(self):
        # "dosa" is in the alias map, resolves to "masala dosa"
        assert resolve_common_alias("dosa") == "masala dosa"

    def test_unknown_food_returns_original(self):
        assert resolve_common_alias("Avocado Toast") == "Avocado Toast"

    def test_case_insensitive(self):
        assert resolve_common_alias("CHAPATI") == "roti"
        assert resolve_common_alias("butter chicken") == "butter chicken"

    def test_poha_exact(self):
        assert resolve_common_alias("Poha") == "poha"


# ---------------------------------------------------------------------------
# Common alias map coverage
# ---------------------------------------------------------------------------

class TestFoodCommonAliasesMap:
    def test_all_keys_are_lowercase(self):
        for key in FOOD_COMMON_ALIASES:
            assert key == key.lower(), f"Key {key!r} is not lowercase"

    def test_all_keys_have_no_punctuation_except_slash(self):
        import re
        for key in FOOD_COMMON_ALIASES:
            cleaned = re.sub(r"[^\w\s/]", "", key)
            assert cleaned == key, f"Key {key!r} contains unexpected punctuation"

    def test_chapati_key_exists(self):
        assert "chapati" in FOOD_COMMON_ALIASES

    def test_chicken_biryani_key_exists(self):
        assert "chicken biryani" in FOOD_COMMON_ALIASES

    def test_paneer_butter_masala_key_exists(self):
        assert "paneer butter masala" in FOOD_COMMON_ALIASES


# ---------------------------------------------------------------------------
# Integration with find_food_match (via seeded INDB repo)
# ---------------------------------------------------------------------------

class TestCommonAliasesWithRepo:
    """Uses the real seeded INDB repository to verify end-to-end matching."""

    def test_chapati_matches_roti(self, indb_repo):
        match = indb_repo.find_food_match("Chapati")
        assert match is not None
        assert match.tier == "exact"
        food = indb_repo.get_food(match.food_id)
        assert "roti" in food.food_name.lower() or "roti" in food.food_name.lower()

    def test_chicken_biryani_matches_closest(self, indb_repo):
        match = indb_repo.find_food_match("Chicken Biryani")
        assert match is not None
        food = indb_repo.get_food(match.food_id)
        assert "chicken" in food.food_name.lower()

    def test_paneer_butter_masala_matches(self, indb_repo):
        match = indb_repo.find_food_match("Paneer Butter Masala")
        assert match is not None
        food = indb_repo.get_food(match.food_id)
        assert "paneer" in food.food_name.lower()

    def test_rajma_matches_kidney_bean_curry(self, indb_repo):
        match = indb_repo.find_food_match("Rajma")
        assert match is not None
        assert match.tier == "exact"
        food = indb_repo.get_food(match.food_id)
        assert "rajmah" in food.food_name.lower() or "kidney" in food.food_name.lower()

    def test_aloo_paratha_via_common_alias(self, indb_repo):
        match = indb_repo.find_food_match("Aloo Paratha")
        assert match is not None
        food = indb_repo.get_food(match.food_id)
        assert "Aloo" in food.food_name

    def test_punctuation_in_query(self, indb_repo):
        match = indb_repo.find_food_match("Chicken Biryani!")
        assert match is not None
        food = indb_repo.get_food(match.food_id)
        assert "chicken" in food.food_name.lower()

    def test_mixed_case_punctuation(self, indb_repo):
        match = indb_repo.find_food_match("Chicken Biryani!")
        assert match is not None
        food = indb_repo.get_food(match.food_id)
        assert "chicken" in food.food_name.lower()

    def test_paneer_paratha_exact_runtime_input(self, indb_repo):
        """Exact runtime input: Gemini returns 'Paneer Paratha' -> must match ASC105."""
        from app.database.sqlite import normalize_label
        from app.seed.food_aliases import resolve_common_alias

        raw_input = "Paneer Paratha"

        # 1. Normalization
        label = normalize_label(raw_input)
        assert label == "paneer paratha"

        # 2. Alias resolution
        resolved = resolve_common_alias(label)
        assert resolved == "paneer parantha/paratha"

        # 3. find_food_match must succeed
        match = indb_repo.find_food_match(raw_input)
        assert match is not None, f"find_food_match({raw_input!r}) returned None"
        assert match.food_id == "ASC105"
        assert match.tier == "exact"

        # 4. Canonical food must be Paneer parantha/paratha
        food = indb_repo.get_food(match.food_id)
        assert food.food_name == "Paneer parantha/paratha"

        # 5. Nutrition must exist
        nutrition = indb_repo.get_nutrition(match.food_id)
        assert nutrition.calories_per_100g > 0

    def test_paneer_paratha_pipeline_trace(self, indb_repo, capsys):
        """Full pipeline trace for 'Paneer Paratha' - prints every step."""
        from app.database.sqlite import normalize_label
        from app.seed.food_aliases import resolve_common_alias

        raw = "Paneer Paratha"
        label = normalize_label(raw)
        resolved = resolve_common_alias(label)
        resolved_label = normalize_label(resolved)

        match = indb_repo.find_food_match(raw)
        food = indb_repo.get_food(match.food_id) if match else None

        trace = (
            f"\n--- Paneer Paratha Pipeline Trace ---\n"
            f"  1. Original Gemini name:  {raw!r}\n"
            f"  2. normalize_label():     {label!r}\n"
            f"  3. resolve_common_alias(): {resolved!r}\n"
            f"  4. Resolved + normalized:  {resolved_label!r}\n"
            f"  5. find_food_match():      food_id={match.food_id}, tier={match.tier}, score={match.score}\n"
            f"  6. Canonical food_name:    {food.food_name!r}\n"
            f"  7. SQLite alias hit:       alias={resolved_label!r} -> food_id={match.food_id}\n"
            f"--- End Trace ---"
        )
        capsys.readouterr()  # clear prior output
        print(trace)

        assert match is not None
        assert match.food_id == "ASC105"
        assert match.tier == "exact"
