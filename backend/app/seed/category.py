"""Keyword-based category classification for INDB food names.

INDB does not provide a ``category`` column. ``Food.category`` is required by
the application schema, so a lightweight keyword classifier assigns a broad
family based on well-known terms in Indian food names, falling back to
``Other`` when nothing matches. This is display/grouping metadata only; it is
never used for nutrition lookup or values.
"""

import re

# Ordered rules: first matching rule wins.
CATEGORY_RULES: list[tuple[str, list[str]]] = [
    (
        "Beverages",
        [
            "tea", "coffee", "lassi", "milkshake", "shake", "juice", "drink",
            "water", "sherbet", "sharbat", "lemonade", "cooler", "cocoa",
            "squash", "quash", "nog", "jal jeera", "thandai", "canjee",
            "kanji", "shikanji", "sattu", "smoothie", "sorbet", "chaas",
            "mintade", "punched", "punch",
        ],
    ),
    (
        "Sweets & Desserts",
        [
            "kheer", "halwa", "burfi", "barfi", "ladoo", "laddu", "pudding",
            "payasam", "malpua", "custard", "sweet", "rabri", "shrikhand",
            "mithai", "gulab", "jalebi", "soan", "chhena", "poda", "chikki",
            "halua", "milk cake", "kaju", "basundi", "dessert", "kesari",
            "jaggery", "motichoor", "churma", "gulkand", "sundae", "jamun",
        ],
    ),
    (
        "Snacks & Savouries",
        [
            "pakora", "pakoda", "vada", "cutlet", "tikki", "samosa", "chaat",
            "bhel", "namkeen", "bhujia", "fritter", "falafel", "spring roll",
            "nugget", "crisp", "finger", "taco", "puff", "toastie", "dhokla",
            "sev", "chips",
        ],
    ),
    (
        "Breads, Parathas & Breakfast",
        [
            "paratha", "parantha", "roti", "chappati", "chapati", "phulka",
            "puri", "poori", "naan", "bhatura", "kulcha", "tortilla",
            "bread", "toast", "sandwich", "cheela", "chilla", "dosa",
            "uttapam", "idli", "appam", "pancake", "biscuit", "cookie",
            "cracker", "rusk", "bruschetta", "croissant", "bagel", "waffle",
        ],
    ),
    (
        "Rice & Grain Dishes",
        [
            "rice", "chawal", "biryani", "pulao", "pulav", "khichdi",
            "khichri", "pongal", "upma", "semolina", "vermicelli", "poha",
            "pasta", "noodle", "macaroni", "spaghetti", "congee", "porridge",
            "oat", "daliya", "ragi", "jowar", "bajra", "millet", "barley",
            "corn", "maize", "flakes", "cereal", "murmura", "moori", "chiwda",
            "muesli", "granola", "bulgur", "couscous", "quinoa",
        ],
    ),
    (
        "Pulses & Lentils",
        [
            "dal", "dahl", "lentil", "moong", "masoor", "chana", "chole",
            "rajma", "pulses", "gram", "toor", "arhar", "urad", "dalma",
            "sambar", "rasam", "lobia", "chickpea", "kabuli chana", "pulse",
        ],
    ),
    (
        "Vegetable Dishes",
        [
            "sabzi", "bhaji", "subji", "vegetable", "tamatar", "tomato",
            "palak", "spinach", "potato", "aloo", "gobi", "cauliflower",
            "brinjal", "baingan", "bhindi", "okra", "lauki", "bottle gourd",
            "karela", "bitter gourd", "pumpkin", "carrot", "gajar", "mushroom",
            "capsicum", "cabbage", "cucumber", "kheera", "onion", "pyaaz",
            "lady finger", "tinda", "parwal", "arbi", "yam", "beetroot",
            "gherkin", "curry leaves", "paneer", "cottage cheese",
        ],
    ),
    (
        "Meat, Egg & Fish",
        [
            "chicken", "mutton", "egg", "anda", "fish", "prawn", "shrimp",
            "meat", "keema", "pork", "goat", "lamb", "sausage", "ham",
            "omlet", "omelette", "salmon", "tuna", "kebab",
        ],
    ),
    (
        "Curries & Gravies",
        [
            "curry", "gravy", "masala", "korma", "bhuna", "shahi", "saag",
            "stew", "rogan", "makhan", "butter",
        ],
    ),
    (
        "Salads & Soups",
        [
            "salad", "soup", "broth", "koshimbir", "raita", "raitha",
            "pachadi", "crunch", "tossed",
        ],
    ),
    (
        "Condiments & Spices",
        [
            "powder", "spice", "seasoning", "chutney", "pickle", "achar",
            "sauce", "dressing", "gravy masala",
        ],
    ),
]

_OTHER = "Other"


def classify(food_name: str) -> str:
    """Classify a food name into a broad category family."""
    name = food_name.lower()
    for category, keywords in CATEGORY_RULES:
        if any(re.search(rf"(^|\W){re.escape(kw)}(\W|$)", name) for kw in keywords):
            return category
    return _OTHER