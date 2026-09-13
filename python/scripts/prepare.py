"""Curated publication definitions; no analysis runs on import."""
from __future__ import annotations
import numpy as np
import pandas as pd
def add_maturity(c: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Use diagnosis-year administrative opportunity, never achieved individual follow-up."""
    c = c.copy()
    d = cfg['design']
    cutoff = pd.Timestamp(d['cutoff'])
    jan = pd.to_datetime(c.year_dx.astype(str) + '-01-01')
    dec = pd.to_datetime(c.year_dx.astype(str) + '-12-31')
    c['administrative_cutoff'] = d['cutoff']
    c['potential_followup_days_min'] = (cutoff - dec).dt.days
    c['potential_followup_days_max'] = (cutoff - jan).dt.days
    c['maturity_date_precision'] = 'DIAGNOSIS_YEAR_ONLY; no patient diagnosis date invented'
    for s in d['landmarks_primary'] + d['landmarks_exploratory']:
        total = s + d['prediction_horizon_years']
        c[f'eligible_horizon_L{s}_3y'] = c.year_dx.le(cutoff.year - total)
        c[f'guaranteed_days_horizon_L{s}_3y'] = c.potential_followup_days_min.ge(total * d['days_per_year'])
        c[f'possible_days_horizon_L{s}_3y'] = c.potential_followup_days_max.ge(total * d['days_per_year'])
        c[f'boundary_uncertain_L{s}_3y'] = c[f'possible_days_horizon_L{s}_3y'] & ~c[f'guaranteed_days_horizon_L{s}_3y']
    short = d['contemporary_short_horizon_years']
    c['eligible_contemporary_L0_1y'] = c.year_dx.le(cutoff.year - short)
    c['guaranteed_days_contemporary_L0_1y'] = c.potential_followup_days_min.ge(short * d['days_per_year'])
    c['primary_prediction_era_flag'] = c.year_dx.between(*d['primary_prediction_years'])
    c['followup_exceeds_calendar_max_flag'] = c.survival_days_numeric.gt(c.potential_followup_days_max + 1)
    return c

def make_landmarks(frame: pd.DataFrame, landmarks: list[int], cfg: dict, mature_filter: bool=False) -> pd.DataFrame:
    """Construct right-censored future windows; survival equal to landmark is not at risk."""
    pieces = []
    d = cfg['design']
    horizon = d['prediction_horizon_years'] * d['days_per_year']
    for s in landmarks:
        mask = frame.survival_days_analysis.gt(s * d['days_per_year'])
        if mature_filter:
            mask &= frame[f'eligible_horizon_L{s}_3y']
        part = frame.loc[mask].copy()
        part['landmark_year'] = s
        part['landmark_days'] = s * d['days_per_year']
        part['landmark_row_id'] = part.record_id + f':L{s}'
        part['calendar_year_dx'] = part.year_dx
        part['time_from_landmark'] = part.survival_days_analysis - part.landmark_days
        part['time_to_analysis_end'] = part.time_from_landmark.clip(upper=horizon)
        part['administrative_prediction_end'] = horizon
        part['event_original'] = part.event_competing.astype(int)
        part['event_within_window'] = part.event_original.where(part.time_from_landmark.le(horizon), 0)
        part['cancer_event'] = part.event_within_window.eq(1)
        part['other_event'] = part.event_within_window.eq(2)
        part['censored_before_window_end'] = part.event_original.eq(0) & part.time_from_landmark.lt(horizon)
        part['window_complete_no_event'] = part.event_within_window.eq(0) & part.time_from_landmark.ge(horizon)
        part['time_unit'] = 'days; 365.25 days/year'
        assert part.time_from_landmark.gt(0).all() and part.time_to_analysis_end.le(horizon).all()
        assert (part.cancer_event.astype(int) + part.other_event.astype(int) + part.censored_before_window_end.astype(int) + part.window_complete_no_event.astype(int)).eq(1).all()
        pieces.append(part)
    result = pd.concat(pieces, ignore_index=True)
    assert result.landmark_row_id.is_unique
    return result

def reverse_km_median(frame: pd.DataFrame, days_per_year: float) -> float:
    """Descriptive reverse-KM follow-up median, deaths censored; not a prognostic model."""
    tab = frame.groupby('survival_days_analysis').agg(n=('record_id', 'size'), censor_events=('event_os', lambda x: int(x.eq(0).sum())))
    remaining, survival = (len(frame), 1.0)
    for time, row in tab.iterrows():
        survival *= 1 - row.censor_events / remaining
        if survival <= 0.5:
            return float(time / days_per_year)
        remaining -= int(row.n)
    return np.nan

