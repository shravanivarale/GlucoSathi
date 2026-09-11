"""CGM provider abstraction.

Defines the ``CGMProvider`` interface that all glucose monitor integrations
must implement.  ``MockCGMProvider`` is the default — it returns realistic
sample readings so the full CGM → prediction pipeline can be tested without
a real device or API.

Future providers (Dexcom, Libre, etc.) will implement the same interface and
be wired in via configuration or dependency injection.
"""

from __future__ import annotations

import math
import random
from abc import ABC, abstractmethod
from datetime import datetime, timedelta, timezone


class CGMReading:
    """A single normalized CGM glucose reading."""

    __slots__ = ("timestamp", "cbg", "basal", "hr", "gsr", "carb_input", "bolus")

    def __init__(
        self,
        timestamp: datetime,
        cbg: float,
        basal: float = 0.0,
        hr: float = 0.0,
        gsr: float = 0.0,
        carb_input: float = 0.0,
        bolus: float = 0.0,
    ) -> None:
        self.timestamp = timestamp
        self.cbg = cbg
        self.basal = basal
        self.hr = hr
        self.gsr = gsr
        self.carb_input = carb_input
        self.bolus = bolus

    def to_dict(self) -> dict:
        return {
            "timestamp": self.timestamp.isoformat(),
            "cbg": self.cbg,
            "basal": self.basal,
            "hr": self.hr,
            "gsr": self.gsr,
            "carbInput": self.carb_input,
            "bolus": self.bolus,
        }


class CGMProvider(ABC):
    """Interface that all CGM provider implementations must satisfy."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Human-readable provider name (e.g. 'Dexcom', 'Mock')."""

    @property
    @abstractmethod
    def is_available(self) -> bool:
        """Whether the provider is currently reachable / configured."""

    @abstractmethod
    def get_latest_reading(self) -> CGMReading:
        """Return the single most recent glucose reading."""

    @abstractmethod
    def get_readings(
        self,
        since: datetime | None = None,
        limit: int = 288,
    ) -> list[CGMReading]:
        """Return recent readings, newest first.

        Parameters
        ----------
        since:
            If given, only return readings at or after this timestamp.
        limit:
            Maximum number of readings to return (default 288 = 24 h at 5-min
            intervals).
        """


class MockCGMProvider(CGMProvider):
    """In-memory mock provider that generates a realistic sinusoidal glucose
    trace with occasional noise.  Useful for end-to-end pipeline testing.

    Each call to ``get_latest_reading()`` produces a new reading with the
    current timestamp so that Flutter polling sees fresh data.
    """

    READING_INTERVAL_MIN = 5

    def __init__(self) -> None:
        self._base_time = datetime.now(timezone.utc)
        # Pre-generate 288 readings (24 h) of realistic data for history
        self._readings = self._generate_trace(288)
        self._last_generated = self._base_time

    # ------------------------------------------------------------------
    # CGMProvider interface
    # ------------------------------------------------------------------

    @property
    def name(self) -> str:
        return "Mock"

    @property
    def is_available(self) -> bool:
        return True

    def get_latest_reading(self) -> CGMReading:
        """Generate a new reading on the 5-minute grid.

        The timestamp is rounded down to the nearest 5-minute mark so that
        each call advances the CGM window by a full interval.  This ensures
        the IOB row-index calculation sees a 5-minute gap between readings,
        matching real CGM behavior.
        """
        now = datetime.now(timezone.utc)
        # Snap to the 5-minute grid so each call moves the window by 5 min.
        minute_floor = (now.minute // self.READING_INTERVAL_MIN) * self.READING_INTERVAL_MIN
        grid_ts = now.replace(minute=minute_floor, second=0, microsecond=0)

        # Only generate if we haven't already produced this grid slot.
        if grid_ts <= self._last_generated:
            # Already generated this slot — return the existing newest reading.
            return self._readings[0]

        new_reading = self._generate_single_reading(grid_ts)
        self._readings.insert(0, new_reading)
        if len(self._readings) > 288:
            self._readings = self._readings[:288]
        self._last_generated = grid_ts
        elapsed = (grid_ts - self._base_time).total_seconds() / 60
        print(f"[CGM-MOCK] get_latest_reading: grid_ts={grid_ts.isoformat()}, "
              f"elapsed_since_start={elapsed:.1f}min")
        print(f"[CGM-MOCK] ✅ NEW reading: ts={grid_ts.isoformat()}, "
              f"cbg={new_reading.cbg}, total={len(self._readings)}")
        print(f"[CGM-MOCK]   Window: {self._readings[-1].timestamp.isoformat()} "
              f"→ {self._readings[0].timestamp.isoformat()}")
        return self._readings[0]

    def get_readings(
        self,
        since: datetime | None = None,
        limit: int = 288,
    ) -> list[CGMReading]:
        if since is None:
            return self._readings[:limit]
        return [r for r in self._readings if r.timestamp >= since][:limit]

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _generate_single_reading(self, ts: datetime) -> CGMReading:
        """Generate one realistic reading at the given timestamp."""
        minute_of_day = ts.hour * 60 + ts.minute

        base = 100.0 + 20.0 * math.sin(
            2 * math.pi * (minute_of_day - 360) / 1440
        )
        for meal_offset, meal_peak, meal_sigma in [
            (480, 90, 40),
            (750, 110, 45),
            (1140, 95, 40),
        ]:
            dt_min = minute_of_day - meal_offset
            base += meal_peak * math.exp(-(dt_min ** 2) / (2 * meal_sigma ** 2))

        noise = random.gauss(0, 3)
        cbg = max(60.0, min(300.0, base + noise))

        hr = 72.0 + 8.0 * math.sin(
            2 * math.pi * minute_of_day / 1440
        ) + random.gauss(0, 2)
        gsr = 5.0 + 1.5 * math.sin(
            2 * math.pi * (minute_of_day - 200) / 1440
        ) + random.gauss(0, 0.3)

        return CGMReading(
            timestamp=ts,
            cbg=round(cbg, 1),
            hr=round(hr, 1),
            gsr=round(gsr, 2),
        )

    def _generate_trace(self, n: int) -> list[CGMReading]:
        """Generate *n* simulated 5-min-interval readings for history."""
        readings: list[CGMReading] = []
        now = self._base_time
        for i in range(n):
            ts = now - timedelta(minutes=self.READING_INTERVAL_MIN * i)
            readings.append(self._generate_single_reading(ts))
        return readings


# ---------------------------------------------------------------------------
# Singleton accessor (mirrors ``get_glucose_predictor`` pattern)
# ---------------------------------------------------------------------------

_provider: CGMProvider | None = None


def get_cgm_provider() -> CGMProvider:
    """Return the application-wide CGM provider instance."""
    global _provider
    if _provider is None:
        print("[CGM-DEBUG]   Initializing MockCGMProvider (synthetic CGM)…")
        _provider = MockCGMProvider()
        print(f"[CGM-DEBUG]   MockCGMProvider initialized ✓ — "
              f"{len(_provider._readings)} readings generated")
    return _provider


def set_cgm_provider(provider: CGMProvider) -> None:
    """Override the provider (useful in tests)."""
    global _provider
    _provider = provider
