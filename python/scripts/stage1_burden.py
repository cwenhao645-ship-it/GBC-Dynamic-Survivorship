"""Curated publication definitions; no analysis runs on import."""
from __future__ import annotations
import os, hashlib
from pathlib import Path
from unittest.mock import patch
import numpy as np
import pandas as pd
from scripts.pipeline import harmonize, read_config, sha256, verify_inputs
from scripts.prepare import add_maturity, make_landmarks, reverse_km_median
ROOT = Path(os.environ.get("GBC_PREPARATION_ROOT", "."))
AJ_SOURCE = "https://stat.ethz.ch/R-manual/R-devel/library/survival/html/survfit.formula.html"
SEED, B = (20260904, 1000)

YEAR, MONTH, HORIZON = (365.25, 30.4375, 1095.75)

LANDMARKS = tuple(range(6))

GROUPS = {'Overall': (None, ('All',)), 'T': ('T_model', ('T1', 'T2', 'T3/4')), 'N': ('N_model', ('N0', 'N+')), 'Grade': ('grade_model', ('G1', 'G2', 'G3/4')), 'Age': ('age_group', ('18-64', '65-74', '>=75'))}

def build_cohort():
    cfg = read_config()
    with patch('scripts.pipeline.write_json') as audit_sink:
        raw, info = verify_inputs(cfg)
    assert audit_sink.call_count == 1 and (not info['errors'])
    c = harmonize(raw, cfg)
    cfg['design'].update(summary_stage_policy='explicit_M0_only_V2', days_per_year=YEAR, prediction_horizon_years=3, zero_day_correction=0.5)
    c = add_maturity(c, cfg)
    criteria = {'01 C239 malignant gallbladder tumor': c.gallbladder_site_flag & c.malignant_flag, '02 Diagnosis 2004-2023': c.year_dx.between(2004, 2023), '03 Age >=18': c.age_dx.ge(18), '04 Histology ICD-O-3 8140': c.histology_code.eq(8140), '05 Malignant behavior /3': c.malignant_flag, '06 Positive histologic confirmation': c.histology_confirmed, '07 Primary by international rules Yes': c.international_primary_flag, '08 Strict resection (unchanged)': c.strict_resection_flag, '09 Explicit M0 only': c.M_harmonized.eq('M0'), '10 Valid nonnegative Survival Days': c.survival_days_numeric.notna() & c.survival_days_numeric.ge(0), '11 Valid competing-risk COD': c.event_competing.isin([0, 1, 2]) & ~c.outcome_conflict_flag}
    keep = pd.Series(True, index=c.index)
    flow, precursor = ([], None)
    for label, mask in criteria.items():
        before = int(keep.sum())
        keep &= mask.fillna(False)
        flow.append(dict(step=label, n_before=before, n_excluded=before - int(keep.sum()), n_after=int(keep.sum())))
        if label.startswith('09'):
            precursor = c.loc[keep].copy()
    m = c.loc[keep].copy().reset_index(drop=True)
    if m.patient_id.duplicated().any() or not m.record_id.is_unique or m.patient_id.isna().any() or m.patient_id.eq('').any():
        raise RuntimeError('Eligible patient duplicates/invalid IDs require review; no automatic selection.')
    flow.append(dict(step='12 Eligible record/duplicate check (no deletion)', n_before=len(m), n_excluded=0, n_after=len(m)))
    if int(m.T_harmonized_fine.eq('T4').sum()) <= 3:
        raise RuntimeError('T4 remains approximately two: investigate hidden Summary Stage selection.')
    m = m.drop(columns=['stage_conflict_flag', 'nonmetastatic_broad_flag', 'temporal_role'])
    m['flag_main_M0'] = m.M_harmonized.eq('M0')
    m['flag_summary_concordant'] = m.summary_stage_harmonized.isin(['Localized', 'Regional'])
    m['flag_summary_unknown'] = m.summary_stage_harmonized.eq('Unknown')
    m['flag_summary_distant'] = m.summary_stage_harmonized.eq('Distant')
    m['summary_stage_concordance_group'] = 'M0 + ' + m.summary_stage_harmonized
    m['CROSS_SYSTEM_STAGE_DISCORDANCE'] = m.flag_summary_distant
    m['T0_nonstandard_flag'] = m.T_harmonized_fine.eq('T0')
    m.loc[m.T0_nonstandard_flag, 'T_model'] = 'Unknown/nonstandard'
    m['exclude_T0'] = ~m.T0_nonstandard_flag
    m['zero_day_flag'] = m.zero_day_survival_flag
    m['exclude_zero_flag'] = ~m.zero_day_flag
    m['descriptive_source_flag'] = m.year_dx.between(2004, 2015)
    m['prediction_source_flag'] = m.year_dx.between(2004, 2017)
    m['contemporary_flag'] = m.year_dx.between(2018, 2023)
    m['temporal_role_primary'] = np.select([m.year_dx.between(2004, 2011), m.year_dx.between(2012, 2017)], ['DEVELOPMENT', 'TEMPORAL_VALIDATION'], default='CONTEMPORARY')
    m['temporal_role_secondary'] = np.select([m.year_dx.between(2012, 2014), m.year_dx.between(2015, 2017)], ['RECALIBRATION', 'POST_RECALIBRATION_EVALUATION'], default='NOT_IN_SECONDARY_UPDATING')
    for role in ('DEVELOPMENT', 'TEMPORAL_VALIDATION', 'RECALIBRATION', 'POST_RECALIBRATION_EVALUATION'):
        m['flag_' + role.lower()] = m.temporal_role_primary.eq(role) | m.temporal_role_secondary.eq(role)
    m['cohort_version'] = 'V2 explicit M0; Summary Stage does not select main cohort'
    assert m[['flag_summary_concordant', 'flag_summary_unknown', 'flag_summary_distant']].sum(axis=1).eq(1).all()
    assert m.flag_main_M0.all() and m.event_competing.isin([0, 1, 2]).all()
    old_file = ROOT / 'data_clean/02_strict_main_candidate_2004_2023.parquet'
    old = pd.read_parquet(old_file)
    assert set(old.record_id) == set(m.loc[m.flag_summary_concordant, 'record_id'])
    old_common = old.set_index('record_id').sort_index()
    new_common = m.loc[m.flag_summary_concordant].set_index('record_id').sort_index()
    shared = [x for x in c.columns if x in old_common and x in new_common and (x != 'T_model')]
    pd.testing.assert_frame_equal(old_common[shared], new_common[shared], check_dtype=False)
    info.update(raw_duplicate_patient_rows=int(c.patient_id.duplicated(keep=False).sum()), raw_exact_duplicate_rows=int(raw.duplicated(keep=False).sum()), old_main_n=len(old), old_t4=int(old.T_harmonized_fine.eq('T4').sum()))
    return (m, pd.DataFrame(flow), precursor, cfg, info)

def long_data(m, cfg):
    parts = []
    for role, source, landmarks in [('DESCRIPTIVE', m.descriptive_source_flag, list(LANDMARKS)), ('PREDICTION_PREP', m.prediction_source_flag, [1, 2, 3])]:
        p = make_landmarks(m.loc[source], landmarks, cfg)
        p['analysis_role'] = role
        p['landmark_row_id'] = role + ':' + p.landmark_row_id
        p['window_end'] = p.time_to_analysis_end
        p['truncation_days'] = HORIZON
        parts.append(p)
    result = pd.concat(parts, ignore_index=True)
    assert result.landmark_row_id.is_unique
    assert not result.loc[result.analysis_role.eq('PREDICTION_PREP'), 'landmark_year'].eq(0).any()
    return result

class AJSpec:
    """Pre-group exact observed times; integer bootstrap weights equal row replication."""

    def __init__(self, indices, times, events):
        self.indices = np.asarray(indices, dtype=int)
        self.times = np.minimum(np.asarray(times, dtype=float), HORIZON)
        self.events = np.asarray(events, dtype=int).copy()
        self.events[np.asarray(times) > HORIZON] = 0
        self.unique, self.inverse = np.unique(self.times, return_inverse=True)
        self.event_indices = [np.flatnonzero(self.events == k) for k in (1, 2)]

    def evaluate(self, weights):
        w = weights[self.indices]
        counts = np.bincount(self.inverse, weights=w, minlength=len(self.unique))
        if counts.sum() == 0:
            return np.full(8, np.nan)
        risk = counts[::-1].cumsum()[::-1]
        deaths = np.stack([np.bincount(self.inverse[i], weights=w[i], minlength=len(self.unique)) for i in self.event_indices]).astype(float)
        hazard = np.divide(deaths, risk, out=np.zeros_like(deaths), where=risk > 0)
        survival_after = np.cumprod(np.clip(1 - hazard.sum(axis=0), 0, 1))
        survival_before = np.r_[1.0, survival_after[:-1]]
        increments = hazard * survival_before
        cif = increments.cumsum(axis=1)
        out = []
        for horizon in (YEAR, 2 * YEAR, HORIZON):
            j = np.searchsorted(self.unique, horizon, side='right') - 1
            supported = np.any((self.unique >= horizon) & (counts > 0)) or (j >= 0 and survival_after[j] <= 1e-12)
            out.extend((cif[:, j] if j >= 0 else np.zeros(2)) if supported else [np.nan, np.nan])
        integral = increments @ (HORIZON - self.unique)
        out.extend(integral if np.isfinite(out[4:6]).all() else [np.nan, np.nan])
        assert cif[:, -1].sum() <= 1 + 1e-10
        assert integral.sum() <= HORIZON + 1e-08
        return np.asarray(out)

def event_counts(p):
    return dict(n_at_risk=len(p), cancer_events_3y=int(p.cancer_event.sum()), other_events_3y=int(p.other_event.sum()), early_censored_3y=int(p.censored_before_window_end.sum()), complete_no_event_3y=int(p.window_complete_no_event.sum()), n_at_3y_horizon=int(p.time_from_landmark.ge(HORIZON).sum()))

def estimate(source, long):
    desc = long.loc[long.analysis_role.eq('DESCRIPTIVE')]
    positions = pd.Series(np.arange(len(source)), index=source.record_id)
    specs, meta = ([], [])
    for family, (variable, levels) in GROUPS.items():
        for level in levels:
            for landmark in LANDMARKS:
                p = desc.loc[desc.landmark_year.eq(landmark)]
                if variable:
                    p = p.loc[p[variable].eq(level)]
                idx = positions.loc[p.record_id].to_numpy()
                specs.append(AJSpec(idx, p.time_from_landmark.to_numpy(), p.event_original.to_numpy()))
                meta.append(dict(family=family, group=level, landmark_year=landmark, **event_counts(p)))
    point = np.stack([s.evaluate(np.ones(len(source))) for s in specs])
    bootstrap = np.empty((B, len(specs), 8))
    rng = np.random.default_rng(SEED)
    draw_digest = hashlib.sha256()
    for b in range(B):
        draw = rng.integers(0, len(source), size=len(source))
        draw_digest.update(draw.astype('<i8').tobytes())
        weights = np.bincount(draw, minlength=len(source))
        for j, s in enumerate(specs):
            bootstrap[b, j] = s.evaluate(weights)
    from statsmodels.duration.survfunc import CumIncidenceRight
    maximum_error = 0.0
    for spec, own in zip(specs, point):
        ref = CumIncidenceRight(spec.times, spec.events, freq_weights=np.ones(len(spec.times)))
        for k in range(2):
            for h in (1, 2, 3):
                j = np.searchsorted(ref.times, h * YEAR, side='right') - 1
                value = float(ref.cinc[k][j]) if j >= 0 else 0.0
                maximum_error = max(maximum_error, abs(value - own[(h - 1) * 2 + k]))
            jumps = np.diff(np.r_[0.0, ref.cinc[k]])
            integral = np.sum(jumps * (HORIZON - ref.times))
            maximum_error = max(maximum_error, abs(integral - own[6 + k]))
    assert maximum_error < 1e-08
    return (pd.DataFrame(meta), point, bootstrap, maximum_error, draw_digest.hexdigest())

def interval(value, draws):
    finite = np.isfinite(draws)
    if not np.isfinite(value) or not finite.all():
        return dict(estimate=float(value), ci_lower=np.nan, ci_upper=np.nan, bootstrap_valid=int(finite.sum()))
    lo, hi = np.quantile(draws, [0.025, 0.975], method='linear')
    return dict(estimate=float(value), ci_lower=float(lo), ci_upper=float(hi), bootstrap_valid=len(draws))

def result_tables(meta, point, boot):
    aj, rmtl, ci, attenuation, age = ([], [], [], {}, [])
    lookup = {(r.family, r.group, r.landmark_year): i for i, r in meta.iterrows()}
    for i, r in meta.iterrows():
        key = r.to_dict()
        for k, cause in enumerate(('Cancer', 'Other')):
            for h in (1, 2, 3):
                metric = (h - 1) * 2 + k
                x = dict(**key, cause=cause, horizon_years=h, **interval(point[i, metric], boot[:, i, metric]))
                ci.append(dict(**x, metric='CIF', unit='probability'))
                if r.family == 'Overall':
                    aj.append(x)
                elif r.family == 'Age' and h == 3:
                    age.append(x)
            x = dict(**key, cause=cause, horizon_years=3, **interval(point[i, 6 + k], boot[:, i, 6 + k]))
            ci.append(dict(**x, metric='RMTL', unit='days'))
            if r.family == 'Overall':
                x.update(rmtl_months=x['estimate'] / MONTH, ci_lower_months=x['ci_lower'] / MONTH, ci_upper_months=x['ci_upper'] / MONTH)
                rmtl.append(x)
    decisions = {}
    for family in ('T', 'N', 'Grade'):
        levels = GROUPS[family][1]
        rows = []
        base_hi, base_lo = (lookup[family, levels[-1], 0], lookup[family, levels[0], 0])
        base_rd = point[base_hi, 4] - point[base_lo, 4]
        base_b = boot[:, base_hi, 4] - boot[:, base_lo, 4]
        for s in LANDMARKS:
            for level in levels:
                i = lookup[family, level, s]
                rows.append(dict(row_type='GROUP_CANCER_CIF', contrast=level, **meta.iloc[i].to_dict(), **interval(point[i, 4], boot[:, i, 4]), unit='probability'))
            hi, lo = (lookup[family, levels[-1], s], lookup[family, levels[0], s])
            rd, rd_b = (point[hi, 4] - point[lo, 4], boot[:, hi, 4] - boot[:, lo, 4])
            common = dict(family=family, landmark_year=s, contrast=f'{levels[-1]} minus {levels[0]}', unit='probability_difference')
            rows.append(dict(row_type='RISK_DIFFERENCE', **common, **interval(rd, rd_b)))
            change = interval(rd - base_rd, rd_b - base_b)
            rows.append(dict(row_type='RD_CHANGE_FROM_L0', **common, **change))
            if s == 5:
                decisions[family] = 'YES' if change['ci_upper'] < 0 else 'NO' if change['ci_lower'] > 0 else 'UNCLEAR'
        attenuation[family + '_attenuation'] = pd.DataFrame(rows)
    contrast_rows = []
    for family, group in [('Overall', 'All'), ('Age', '>=75')]:
        for s in LANDMARKS:
            i = lookup[family, group, s]
            for metric, a, b, unit in [('Other_minus_cancer_CIF3', 5, 4, 'probability_difference'), ('Other_minus_cancer_RMTL', 7, 6, 'days')]:
                contrast_rows.append(dict(family=family, group=group, landmark_year=s, metric=metric, unit=unit, **interval(point[i, a] - point[i, b], boot[:, i, a] - boot[:, i, b])))
    contrasts = pd.DataFrame(contrast_rows)
    crossovers = {}
    for metric in ('Other_minus_cancer_CIF3', 'Other_minus_cancer_RMTL'):
        p = contrasts.loc[contrasts.family.eq('Overall') & contrasts.metric.eq(metric)]
        hits = p.loc[p.estimate.gt(0), 'landmark_year']
        crossovers[metric] = f'L{hits.iloc[0]}' if len(hits) else 'None at L0-L5'
    older = contrasts.loc[contrasts.family.eq('Age') & contrasts.metric.eq('Other_minus_cancer_CIF3')].sort_values('landmark_year')
    decisions['Age'] = 'YES' if older.iloc[0].ci_upper < 0 and older.iloc[-1].ci_lower > 0 else 'UNCLEAR'
    ci = pd.concat([pd.DataFrame(ci), contrasts], ignore_index=True)
    for frame in attenuation.values():
        extra = frame.loc[frame.row_type.ne('GROUP_CANCER_CIF')].drop(columns='group').rename(columns={'row_type': 'metric', 'contrast': 'group'})
        ci = pd.concat([ci, extra], ignore_index=True)
    ci['bootstrap_requested'] = B
    ci['seed'] = SEED
    ci['resampling_unit'] = 'Source patient; same draw across all L0-L5 and strata'
    ci['interval_method'] = 'Pointwise percentile 2.5/97.5; not simultaneous'
    output = {'AJ_CIF': pd.DataFrame(aj), 'RMTL': pd.DataFrame(rmtl), **attenuation, 'Age_dynamic_risk': pd.DataFrame(age), 'Bootstrap_CI': ci}
    for frame in output.values():
        frame['source_years'] = '2004-2015'
    for name, unit in [('AJ_CIF', 'probability'), ('RMTL', 'days'), ('Age_dynamic_risk', 'probability')]:
        output[name]['estimate_unit'] = unit
    output['Bootstrap_CI']['AJ_method_source'] = AJ_SOURCE
    return (output, decisions, crossovers, contrasts)
