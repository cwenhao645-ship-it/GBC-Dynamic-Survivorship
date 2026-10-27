"""Public read-only Phase2 intake gates and AJ point reconciliation only.

This module contains deterministic intake gates and AJ point checks only.
Original Phase2 resampling execution and writers are intentionally omitted;
the separate run_phase2.py entry point retains the formal implementation.
Exclude Summary Distant only, retain Unknown; no model fitting or file writes.
"""
import ast
import os
from pathlib import Path
import sys

import numpy as np
import pyarrow.parquet as pq
from openpyxl import load_workbook

sys.dont_write_bytecode = True
YEAR, MONTH, HORIZON = 365.25, 30.4375, 1095.75
SEED, B = 20260904, 1000


def require(ok, message):
    if not bool(ok):
        raise RuntimeError(message)


def sheet_records(path, sheet, first_header):
    book = load_workbook(path, read_only=True, data_only=True)
    try:
        headers = None
        records = []
        for row in book[sheet].values:
            if headers is None:
                if row and row[0] == first_header:
                    headers = row
                continue
            if row and any(v is not None for v in row):
                records.append(dict(zip(headers, row)))
        require(headers is not None, f'Missing header in {sheet}')
        return records
    finally:
        book.close()


def load_aj(source):
    # Reuse only these exact definitions, not the module's imports/main/writers.
    tree = ast.parse(source.read_text(encoding='utf-8'))
    nodes = [n for n in tree.body if isinstance(n, (ast.ClassDef, ast.FunctionDef))
             and n.name in ('AJSpec', 'interval')]
    require(len(nodes) == 2, 'Original AJSpec/interval definitions not found')
    scope = dict(np=np, YEAR=YEAR, MONTH=MONTH, HORIZON=HORIZON)
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(source), 'exec'), scope)
    return scope['AJSpec'], scope['interval']


def preflight(root):
    upstream = Path(os.environ['GBC_PREPARATION_ROOT']).resolve()
    patient = pq.read_table(root / 'data/analysis_patient_level_v2.parquet').to_pandas()
    dynamic = patient.loc[patient.year_dx.between(2004, 2015)].copy()
    allcause = pq.read_table(upstream / 'data_clean/01_gallbladder_harmonized_all_2004_2023.parquet').to_pandas()
    eligible = (allcause.gallbladder_site_flag & allcause.malignant_flag
        & allcause.year_dx.between(2004, 2023) & allcause.age_dx.ge(18)
        & allcause.strict_8140_flag & allcause.histology_confirmed
        & allcause.international_primary_flag & allcause.strict_resection_flag
        & allcause.M_harmonized.eq('M0') & allcause.survival_days_numeric.ge(0)
        & allcause.event_os.isin([0, 1]))
    precursor = allcause.loc[eligible]
    require(len(precursor) == 7100 and int(precursor.unknown_cod_flag.sum()) == 93,
            'STOP: all-cause precursor count mismatch')
    require(set(precursor.loc[~precursor.unknown_cod_flag, 'record_id']) == set(patient.record_id),
            'STOP: competing-risk/all-cause precursor identities mismatch')
    life = precursor.loc[precursor.year_dx.between(2004, 2015)
        & ~precursor.age_90plus_flag].sort_values('patient_id', kind='stable').copy()
    actual = [len(patient), len(dynamic), len(life),
        int(patient.summary_stage_harmonized.eq('Distant').sum()),
        int(dynamic.summary_stage_harmonized.eq('Distant').sum()),
        int(life.summary_stage_harmonized.eq('Distant').sum())]
    require(actual == [7007, 3918, 3796, 354, 205, 204],
            f'STOP: frozen key counts mismatch: {actual}')
    require(patient.patient_id.is_unique and patient.record_id.is_unique
            and life.patient_id.is_unique, 'STOP: duplicated source patients')
    require(patient.M_harmonized.eq('M0').all(), 'STOP: main source contains non-M0')
    counts = [int(dynamic.survival_days_analysis.gt(s * YEAR).sum()) for s in range(6)]
    require(counts == [3918, 2496, 1786, 1423, 1192, 1047], 'STOP: original CR landmark counts mismatch')
    require([int(life.survival_days_analysis.gt(s * YEAR).sum()) for s in range(6)]
            == [3796, 2469, 1775, 1420, 1191, 1048], 'STOP: original life landmark counts mismatch')
    long = pq.read_table(root / 'data/analysis_landmark_long_v2.parquet').to_pandas()
    desc = long.loc[long.analysis_role.eq('DESCRIPTIVE')]
    for s in range(6):
        risk = dynamic.loc[dynamic.survival_days_analysis.gt(s * YEAR)].set_index('record_id')
        stored = desc.loc[desc.landmark_year.eq(s)].set_index('record_id')
        require(stored.index.is_unique and set(stored.index) == set(risk.index),
                f'STOP: frozen long identities mismatch at L{s}')
        risk = risk.loc[stored.index]
        require(np.allclose(stored.time_from_landmark, risk.survival_days_analysis - s * YEAR,
                            atol=1e-10, rtol=0), f'STOP: landmark times mismatch L{s}')
        require(np.array_equal(stored.event_original.to_numpy(), risk.event_competing.to_numpy()),
                f'STOP: landmark event mismatch L{s}')
        require(np.allclose(stored.time_to_analysis_end,
                            np.minimum(risk.survival_days_analysis - s * YEAR, HORIZON),
                            atol=1e-10, rtol=0), f'STOP: landmark truncation mismatch L{s}')
    sens = dynamic.loc[dynamic.summary_stage_harmonized.ne('Distant')].copy()
    life_sens = life.loc[life.summary_stage_harmonized.ne('Distant')].copy()
    require(len(sens) == 3713 and len(life_sens) == 3592, 'STOP: sensitivity count mismatch')
    require(int(sens.summary_stage_harmonized.eq('Unknown').sum()) == 20,
            'STOP: Unknown was not preserved')
    require(int(dynamic.T_harmonized_fine.eq('T4').sum()) == 83
            and int(sens.T_harmonized_fine.eq('T4').sum()) == 0, 'STOP: T4 audit mismatch')
    print(f'COUNT GATE PASS: source/dynamic/life={actual[:3]}, Distant={actual[3:]}', flush=True)
    print('SENSITIVITY: CR=3713; life=3592; Unknown retained; dynamic T4 83 -> 0', flush=True)
    return patient, dynamic, life, sens, life_sens, long


def frozen_cr(root):
    path = root / 'outputs/STAGE1_RESULTS_v2.xlsx'
    aj = sheet_records(path, 'AJ_CIF', 'family')
    rmtl = sheet_records(path, 'RMTL', 'family')
    ci = sheet_records(path, 'Bootstrap_CI', 'family')
    out = {}
    for row in aj:
        if row['family'] == 'Overall' and row['group'] == 'All' and row['horizon_years'] == 3:
            metric = 'GBC_CIF' if row['cause'] == 'Cancer' else 'Other_CIF'
            out[(int(row['landmark_year']), metric)] = dict(n=int(row['n_at_risk']),
                estimate=row['estimate'] * 100, lo=row['ci_lower'] * 100,
                hi=row['ci_upper'] * 100, valid=int(row['bootstrap_valid']))
    for row in rmtl:
        if row['family'] == 'Overall' and row['group'] == 'All' and row['horizon_years'] == 3:
            metric = 'GBC_RMTL' if row['cause'] == 'Cancer' else 'Other_RMTL'
            out[(int(row['landmark_year']), metric)] = dict(n=int(row['n_at_risk']),
                estimate=row['rmtl_months'], lo=row['ci_lower_months'],
                hi=row['ci_upper_months'], valid=int(row['bootstrap_valid']))
    for row in ci:
        if row['family'] == 'Overall' and row['group'] == 'All' and row['metric'] == 'Other_minus_cancer_CIF3':
            require(row['seed'] == SEED and row['bootstrap_requested'] == B,
                    'STOP: V2 resampling provenance mismatch')
            s = int(row['landmark_year'])
            out[(s, 'Delta_CIF')] = dict(n=out[(s, 'GBC_CIF')]['n'],
                estimate=row['estimate'] * 100, lo=row['ci_lower'] * 100,
                hi=row['ci_upper'] * 100, valid=int(row['bootstrap_valid']))
    require(len(out) == 30, 'STOP: incomplete original CR results')
    return out


def make_specs(data, AJSpec):
    times = data.survival_days_analysis.to_numpy(float)
    events = data.event_competing.to_numpy(int)
    specs = []
    for s in range(6):
        idx = np.flatnonzero(times > s * YEAR)
        specs.append(AJSpec(idx, times[idx] - s * YEAR, events[idx]))
    return specs


def metric_values(array):
    return {'GBC_CIF': array[..., 4] * 100, 'Other_CIF': array[..., 5] * 100,
            'GBC_RMTL': array[..., 6] / MONTH, 'Other_RMTL': array[..., 7] / MONTH,
            'Delta_CIF': (array[..., 5] - array[..., 4]) * 100}


def cr_sensitivity(root, dynamic, sens, frozen, check_only=False):
    AJSpec, interval = load_aj(Path(__file__).resolve().parents[2] / 'python/scripts/stage1_burden.py')
    original_specs = make_specs(dynamic, AJSpec)
    original_point = np.stack([s.evaluate(np.ones(len(dynamic))) for s in original_specs])
    for metric, values in metric_values(original_point).items():
        for s, value in enumerate(values):
            require(abs(value - frozen[(s, metric)]['estimate']) < 1e-8,
                    f'STOP: original CR point not reproduced: {metric} L{s}')
    print('ORIGINAL AJ POINT RECONCILIATION PASS (all 30 values)', flush=True)
    if check_only:
        return None
    raise RuntimeError('This intake helper permits check_only=True; use run_phase2.py for formal resampling.')
