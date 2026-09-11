"""CGM service layer.

Orchestrates the CGM provider, the existing glucose prediction pipeline,
and the CGM repository for persistence.  This is the *only* place where
CGM data meets the ONNX model — the API layer and Flutter app never call
the preprocessor or predictor directly.

Architecture::

    CGM Provider (Mock / Dexcom / Libre)
            ↓
    CGMService
            ├── preprocess_history()   ← existing
            ├── get_glucose_predictor() ← existing
            ├── SQLiteCGMRepository     ← persistence
            ↓
    30-min / 60-min prediction
"""

from __future__ import annotations

import pandas as pd

from ..repositories.base import (
    CGMConnectionRecord,
    CGMPredictionRecord,
    CGMReadingRecord,
    CGMRepository,
    InsulinLogRecord,
    InsulinLogRepository,
    INSULIN_TYPE_RAPID,
    INSULIN_TYPE_REGULAR,
    INSULIN_TYPE_NPH,
)
from .cgm_provider import CGMProvider, CGMReading, get_cgm_provider
from .glucose_predictor import get_glucose_predictor
from .glucose_preprocessor import preprocess_history

MIN_READINGS_FOR_PREDICTION = 24


def _to_naive_utc(ts) -> pd.Timestamp:
    """Convert *any* timestamp (tz-aware or tz-naive) to a tz-naive UTC Timestamp.

    ``pd.Timestamp(...).tz_localize(None)`` crashes when the input already
    carries timezone info (e.g. ``2026-09-10T22:12:55.599227+00:00``).
    This helper handles both cases safely.
    """
    stamp = pd.Timestamp(ts)
    if stamp.tzinfo is not None:
        stamp = stamp.tz_convert("UTC").tz_localize(None)
    return stamp


class CGMService:
    """Service that wraps a CGM provider, the prediction model, and the
    persistence repository.

    The provider is resolved lazily via ``get_cgm_provider()`` so tests can
    swap it out with ``set_cgm_provider()`` before any call.
    """

    def __init__(
        self,
        provider: CGMProvider | None = None,
        repository: CGMRepository | None = None,
        insulin_repository: InsulinLogRepository | None = None,
    ) -> None:
        self._provider = provider
        self._repository = repository
        self._insulin_repository = insulin_repository
        self._selected_insulin_type: str | None = None

    @property
    def provider(self) -> CGMProvider:
        if self._provider is None:
            self._provider = get_cgm_provider()
        return self._provider

    @property
    def repository(self) -> CGMRepository | None:
        return self._repository

    # ── Provider status ────────────────────────────────────────────────

    def get_status(self) -> dict:
        """Return connection metadata for the active provider."""
        readings = self.provider.get_readings(limit=1)
        result = {
            "provider_name": self.provider.name,
            "is_connected": self.provider.is_available,
            "reading_count": len(self.provider.get_readings()),
            "latest_timestamp": readings[0].timestamp.isoformat() if readings else None,
        }
        # Include persisted connection state if available.
        if self._repository is not None:
            conn = self._repository.get_connection(self.provider.name)
            if conn is not None:
                result["connected_at"] = conn.connected_at
                result["last_sync_at"] = conn.last_sync_at
        return result

    # ── Readings ───────────────────────────────────────────────────────

    def get_latest_reading(self) -> CGMReading:
        """Return the single most recent reading from the provider."""
        return self.provider.get_latest_reading()

    def get_history(self, limit: int = 288) -> list[CGMReading]:
        """Return recent readings newest-first (default 24 h at 5-min)."""
        return self.provider.get_readings(limit=limit)

    # ── Prediction ─────────────────────────────────────────────────────

    def predict_from_history(self) -> dict:
        """Fetch CGM history, preprocess it, and run the ONNX model.

        Returns
        -------
        dict with keys ``prediction_30_min``, ``prediction_60_min``,
        ``unit``, and ``readings_used``.

        Raises
        ------
        ValueError
            If fewer than ``MIN_READINGS_FOR_PREDICTION`` readings are
            available.
        RuntimeError
            If the ONNX model fails to produce a prediction.
        """
        readings = self.provider.get_readings()

        print(f"[PREDICTION] Starting prediction")
        print(f"[PREDICTION] Readings available: {len(readings)}")

        if len(readings) < MIN_READINGS_FOR_PREDICTION:
            print(f"[PREDICTION] ❌ Insufficient readings: {len(readings)} < {MIN_READINGS_FOR_PREDICTION}")
            raise ValueError(
                f"At least {MIN_READINGS_FOR_PREDICTION} CGM readings are "
                f"required for prediction. Only {len(readings)} available."
            )

        df = self._readings_to_dataframe(readings)

        # Sort ascending by timestamp so preprocess_history's .tail(24)
        # always selects the 24 most recent readings.
        if "timestamp" in df.columns:
            df = df.sort_values("timestamp").reset_index(drop=True)

        # Merge real insulin data into the bolus column if available.
        df = self._merge_insulin_data(df)

        # ── STEP 7: IOB calculations via build_features ──
        from .glucose_preprocessor import build_features, FEATURE_COLS
        features_df = build_features(df)

        # Extract the "current" IOB values from the last row of the
        # 288-row features DataFrame.  This represents the IOB at the
        # most recent CGM reading time — the value the model actually sees.
        last_row = features_df.iloc[-1]

        iob_analogue = round(float(last_row["IOB_analogue"]), 3)
        iob_regular = round(float(last_row["IOB_regular"]), 3)
        iob_nph = round(float(last_row["IOB_NPH"]), 3)

        # Total IOB = sum of all insulin types the user has taken.
        # Each IOB column only contains doses of its own type (rapid,
        # regular, NPH), so summing them gives the correct total.
        total_iob = round(iob_analogue + iob_regular + iob_nph, 3)

        print(f"[IOB] Starting IOB calculation")
        print(f"[IOB] IOB_analogue(last row): {iob_analogue:.6f}")
        print(f"[IOB] IOB_regular(last row): {iob_regular:.6f}")
        print(f"[IOB] IOB_NPH(last row): {iob_nph:.6f}")
        print(f"[IOB] Calculated IOB: {total_iob:.6f} U")

        # ── IOB trace for cross-cycle comparison ──
        self._debug_iob_trace(df, features_df, iob_analogue, iob_regular,
                              iob_nph, total_iob)

        # ── Wall-clock IOB sanity check ──
        # Compute what IOB *should* be using actual elapsed time since each
        # dose, independent of row-index arithmetic.  This lets us compare
        # the row-based result against reality.
        import datetime as _dt
        _debug_logs = (
            self._insulin_repository.get_all_logs(limit=1000)
            if self._insulin_repository is not None
            else []
        )
        _now_utc = _dt.datetime.now(_dt.timezone.utc)
        _now_naive = _to_naive_utc(_now_utc)
        for _dl in _debug_logs:
            try:
                _dose_ts = _to_naive_utc(_dl.logged_at)
                _elapsed_min = (_now_naive - _dose_ts).total_seconds() / 60.0
                if _dl.insulin_type in (INSULIN_TYPE_RAPID, INSULIN_TYPE_REGULAR):
                    _tau = max(0.0, _elapsed_min)
                    if _dl.insulin_type == INSULIN_TYPE_REGULAR:
                        _tau_onset, _tau_end = 30, 480
                        if _tau < _tau_onset:
                            _s = 1.0
                        else:
                            _s = max(0.0, 1.0 - ((_tau - _tau_onset) / (_tau_end - _tau_onset)) ** 2)
                    else:
                        _tau_end, _tau_peak = 240, 75
                        _s = max(0.0, 1 - (_tau / _tau_end) * (1 + (_tau_end - _tau) / (_tau_end - _tau_peak)))
                    print(f"[IOB-WALLCLOCK] dose={_dl.dose_units}U "
                          f"type={_dl.insulin_type} elapsed={_elapsed_min:.0f}min "
                          f"s={_s:.4f} wallclock_iob={_dl.dose_units * _s:.3f}U")
            except Exception:
                pass

        predictor = get_glucose_predictor()

        scaled_features = preprocess_history(
            df,
            predictor.feature_mean,
            predictor.feature_scale,
        )

        result = predictor.predict_scaled(scaled_features)
        result["unit"] = "mg/dL"
        result["readings_used"] = len(readings)
        result["total_iob"] = total_iob

        print(f"[PREDICTION] 30 min result: {result['prediction_30_min']}")
        print(f"[PREDICTION] 60 min result: {result['prediction_60_min']}")
        print(f"[PREDICTION] Total IOB: {total_iob}")
        print(f"[PREDICTION] Readings used: {len(readings)}")
        print(f"[PREDICTION] Full result dict keys: {list(result.keys())}")

        # Persist the prediction if a repository is available.
        if self._repository is not None:
            self._repository.insert_prediction(
                CGMPredictionRecord(
                    id=None,
                    prediction_30_min=result["prediction_30_min"],
                    prediction_60_min=result["prediction_60_min"],
                    readings_used=result["readings_used"],
                )
            )

        return result

    # ── Persistence helpers ───────────────────────────────────────────

    def persist_reading(self, reading: CGMReading) -> int | None:
        """Persist a CGM reading to the database. Returns row id or None."""
        if self._repository is None:
            return None
        return self._repository.insert_reading(
            CGMReadingRecord(
                id=None,
                provider=self.provider.name,
                glucose_value=reading.cbg,
                basal=reading.basal,
                hr=reading.hr,
                gsr=reading.gsr,
                carb_input=reading.carb_input,
                bolus=reading.bolus,
                timestamp=reading.timestamp.isoformat(),
            )
        )

    def get_persisted_readings(self, limit: int = 288) -> list[CGMReadingRecord]:
        """Return persisted readings from the database."""
        if self._repository is None:
            return []
        return self._repository.get_readings(self.provider.name, limit=limit)

    def get_latest_stored_prediction(self) -> CGMPredictionRecord | None:
        """Return the latest persisted prediction."""
        if self._repository is None:
            return None
        return self._repository.get_latest_prediction()

    def get_connection_state(self, provider_name: str) -> CGMConnectionRecord | None:
        """Return persisted connection state for a provider."""
        if self._repository is None:
            return None
        return self._repository.get_connection(provider_name)

    def persist_connection(self, record: CGMConnectionRecord) -> None:
        """Persist connection state."""
        if self._repository is not None:
            self._repository.upsert_connection(record)

    def remove_connection(self, provider_name: str) -> None:
        """Remove persisted connection state."""
        if self._repository is not None:
            self._repository.delete_connection(provider_name)

    # ── Helpers ────────────────────────────────────────────────────────

    @staticmethod
    def _readings_to_dataframe(readings: list[CGMReading]) -> pd.DataFrame:
        """Convert provider readings to the DataFrame format expected by
        ``preprocess_history``.

        The preprocessor expects columns: ``cbg``, ``basal``, ``hr``, ``gsr``,
        ``carbInput``, ``bolus``, and optionally ``timestamp``.  Missing
        columns are filled with zeros by ``build_features``.
        """
        data = [r.to_dict() for r in readings]
        df = pd.DataFrame(data)
        # Ensure timestamp is parsed (preprocessor uses it for time-of-day)
        if "timestamp" in df.columns:
            df["timestamp"] = pd.to_datetime(df["timestamp"], format="ISO8601")
        return df

    @staticmethod
    def _debug_iob_trace(
        df: pd.DataFrame,
        features_df: pd.DataFrame,
        iob_analogue: float,
        iob_regular: float,
        iob_nph: float,
        total_iob: float,
    ) -> None:
        """Emit per-call IOB trace so we can compare across prediction cycles."""
        import datetime as _dt

        now = _dt.datetime.now(_dt.timezone.utc)
        n = len(df)
        first_ts = df["timestamp"].iloc[0] if "timestamp" in df.columns else "N/A"
        last_ts = df["timestamp"].iloc[-1] if "timestamp" in df.columns else "N/A"

        bolus_mask = df["bolus"] > 0
        bolus_rows = df.index[bolus_mask].tolist()
        bolus_distances = {int(r): int(n - 1 - r) for r in bolus_rows}
        bolus_times = {}
        for r in bolus_rows:
            if "timestamp" in df.columns:
                bolus_times[int(r)] = str(df.at[r, "timestamp"])

        basal_mask = df["basal"] > 0
        basal_rows = df.index[basal_mask].tolist()
        basal_distances = {int(r): int(n - 1 - r) for r in basal_rows}

        last_iob_analogue = float(features_df["IOB_analogue"].iloc[-1])
        last_iob_regular = float(features_df["IOB_regular"].iloc[-1])
        last_iob_nph = float(features_df["IOB_NPH"].iloc[-1])

        print(f"[IOB-TRACE] ═══════════════════════════════════════════")
        print(f"[IOB-TRACE] TIME            : {now.isoformat()}")
        print(f"[IOB-TRACE] DF_ROWS         : {n}")
        print(f"[IOB-TRACE] DF_FIRST_TS     : {first_ts}")
        print(f"[IOB-TRACE] DF_LAST_TS      : {last_ts}")
        print(f"[IOB-TRACE] BOLUS_ROWS      : {bolus_rows}")
        print(f"[IOB-TRACE] BOLUS_DISTANCES : {bolus_distances}  (rows-to-end)")
        print(f"[IOB-TRACE] BOLUS_TIMES     : {bolus_times}")
        print(f"[IOB-TRACE] BASAL_ROWS      : {basal_rows}")
        print(f"[IOB-TRACE] BASAL_DISTANCES : {basal_distances}  (rows-to-end)")
        print(f"[IOB-TRACE] IOB_analogue[last] = {last_iob_analogue:.6f}")
        print(f"[IOB-TRACE] IOB_regular[last]  = {last_iob_regular:.6f}")
        print(f"[IOB-TRACE] IOB_NPH[last]      = {last_iob_nph:.6f}")
        print(f"[IOB-TRACE] TOTAL_IOB          = {total_iob:.6f}")
        print(f"[IOB-TRACE] ═══════════════════════════════════════════")

    def _merge_insulin_data(self, df: pd.DataFrame) -> pd.DataFrame:
        """Merge real insulin log data into type-specific columns of the
        CGM readings DataFrame.

        Each insulin dose is assigned to the nearest *preceding* CGM
        reading timestamp (matching the 5-minute interval grid).

        Insulin types are routed to separate columns so that
        ``build_features()`` computes IOB correctly for each type:
          - rapid  → ``bolus_rapid`` → ``compute_iob_rapid()`` → IOB_analogue
          - regular → ``bolus_regular`` → ``compute_iob_regular()`` → IOB_regular
          - nph    → ``basal`` → ``compute_iob_nph()`` → IOB_NPH
        """
        if self._insulin_repository is None:
            print(f"[IOB] No insulin repository available — IOB will be 0.0")
            return df

        if "timestamp" not in df.columns:
            return df

        # Fetch all insulin logs (newest first).
        insulin_logs = self._insulin_repository.get_all_logs(limit=1000)

        print(f"[IOB] Insulin records found: {len(insulin_logs)}")

        if not insulin_logs:
            self._selected_insulin_type = None
            print(f"[IOB] No insulin logs found — IOB will be 0.0")
            return df

        df = df.copy()
        # Initialize type-specific dose columns to zero.
        df["bolus_rapid"] = 0.0
        df["bolus_regular"] = 0.0
        df["basal"] = 0.0
        # Legacy bolus column = sum of rapid + regular (used by model features).
        df["bolus"] = 0.0

        import datetime as _dt
        _now_utc = _dt.datetime.now(_dt.timezone.utc)
        _now_naive = _to_naive_utc(_now_utc)

        for log in insulin_logs:
            try:
                dose_time = _to_naive_utc(log.logged_at)
            except Exception:
                continue

            _elapsed_min = (_now_naive - dose_time).total_seconds() / 60.0
            print(f"[IOB] Dose: {log.dose_units}U {log.insulin_type} "
                  f"at {log.logged_at} (elapsed: {_elapsed_min:.0f}min)")

            # Find the nearest preceding CGM interval by scanning df rows.
            # df rows are in ascending timestamp order.
            # We need the row whose timestamp is <= dose_time and closest to it.
            best_idx = None
            best_ts = None
            for df_idx in df.index:
                cgm_ts = df.at[df_idx, "timestamp"]
                if pd.notna(cgm_ts):
                    cgm_naive = _to_naive_utc(cgm_ts)
                    if cgm_naive <= dose_time:
                        if best_ts is None or cgm_naive > best_ts:
                            best_ts = cgm_naive
                            best_idx = df_idx

            if best_idx is None:
                continue

            # Route each dose to its type-specific column.
            if log.insulin_type == INSULIN_TYPE_NPH:
                df.loc[best_idx, "basal"] += log.dose_units
            elif log.insulin_type == INSULIN_TYPE_REGULAR:
                df.loc[best_idx, "bolus_regular"] += log.dose_units
                df.loc[best_idx, "bolus"] += log.dose_units
            else:
                # rapid and any other bolus type → analogue column
                df.loc[best_idx, "bolus_rapid"] += log.dose_units
                df.loc[best_idx, "bolus"] += log.dose_units

        total_rapid = df["bolus_rapid"].sum()
        total_regular = df["bolus_regular"].sum()
        total_nph = df["basal"].sum()
        print(f"[IOB] Dose totals → rapid={total_rapid:.1f}U "
              f"regular={total_regular:.1f}U nph={total_nph:.1f}U "
              f"bolus_total={df['bolus'].sum():.1f}U")

        return df
