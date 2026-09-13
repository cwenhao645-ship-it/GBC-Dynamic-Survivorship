"""Curated publication definitions; no analysis runs on import."""
from __future__ import annotations
import os,configparser,csv,hashlib,json,re
from collections import Counter
from pathlib import Path
import numpy as np
import pandas as pd
import yaml
ROOT = Path(os.environ.get("GBC_PREPARATION_ROOT", "."))
def read_config() -> dict:
    """Read the single source of coding and design decisions."""
    return yaml.safe_load((Path(os.environ["GBC_SEER_MAPPING"])).read_text(encoding='utf-8'))

def sha256(path: Path) -> str:
    """Fingerprint bytes without changing the input."""
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def write_json(path: Path, value: dict) -> None:
    """Write an auditable derived JSON artifact, never a RAW file."""
    if ROOT / 'data_raw' in path.parents:
        raise ValueError('RAW writes are forbidden')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, default=str), encoding='utf-8')

def verify_inputs(cfg: dict) -> tuple[pd.DataFrame, dict]:
    """Check hashes, DIC, CSV widths, dimensions, and schema before cleaning."""
    opt = cfg['input']
    cp, dp = (ROOT / opt['csv'], ROOT / opt['dic'])
    if not cp.is_file() or not dp.is_file():
        raise RuntimeError('INPUT_FILES_MISSING')
    initial = {'csv': sha256(cp), 'dic': sha256(dp)}
    for kind, digest in initial.items():
        if digest != opt[f'{kind}_sha256']:
            raise RuntimeError(f'RAW_HASH_DRIFT: {kind}; do not overwrite the configured lock')
    dic = configparser.ConfigParser(interpolation=None)
    dic.read(dp, encoding=opt['encoding'])
    db = dic['System']['Database name']
    if not db.startswith(opt['database_required']):
        raise RuntimeError('DATABASE_VERSION_MISMATCH')
    with cp.open(encoding=opt['encoding'], newline='') as stream:
        reader = csv.reader(stream, strict=True)
        header = next(reader)
        widths = Counter((len(row) for row in reader))
    dic_names = [dic['Variables'][f'Var{i}Name'] for i in range(1, len(header) + 1)]
    n = sum(widths.values())
    info = {'status': 'VERIFIED', 'csv_path': str(cp), 'dic_path': str(dp), 'database': db, 'rows': n, 'columns': len(header), 'csv_sha256': initial['csv'], 'dic_sha256': initial['dic'], 'csv_size_bytes': cp.stat().st_size, 'dic_size_bytes': dp.stat().st_size, 'header_checksum': hashlib.sha256(json.dumps(header, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest(), 'header_checksum_definition': 'SHA256 UTF-8 JSON array of CSV header, compact separators', 'header_matches_dic': header == dic_names, 'row_widths': dict(widths), 'reference_rows': opt['reference_rows'], 'reference_columns': opt['reference_columns'], 'export_options': dict(dic['Export Options']), 'raw_modified': False, 'provenance_note': 'User-confirmed de-identified SEER Research Data export'}
    errors = []
    if n != opt['reference_rows'] or len(header) != opt['reference_columns']:
        errors.append('DIMENSION_REFERENCE_MISMATCH')
    if dict(widths) != {len(header): n}:
        errors.append('MALFORMED_ROW_WIDTH')
    if len(set(header)) != len(header) or header != dic_names:
        errors.append('DIC_HEADER_MISMATCH')
    if dic['Export Options']['Field delimiter'] != 'comma' or dic['Export Options']['Variable format'] != 'labels':
        errors.append('UNVERIFIED_EXPORT_FORMAT')
    info['errors'] = errors
    if errors:
        info['status'] = 'FAILED'
    write_json(ROOT / 'outputs/audit/raw_integrity.json', info)
    if errors:
        raise RuntimeError('; '.join(errors))
    raw = pd.read_csv(cp, dtype=str, keep_default_na=False, na_filter=False, encoding=opt['encoding'])
    assert raw.shape == (n, len(header))
    assert all((sha256(p) == initial[k] for k, p in [('csv', cp), ('dic', dp)]))
    return (raw, info)

def coding_period(years: pd.Series, periods: dict) -> pd.Series:
    """Assign calendar bins from prespecified inclusive year bounds."""
    out = pd.Series('OUTSIDE_SCOPE', index=years.index, dtype='string')
    for label, (lo, hi) in periods.items():
        out.loc[years.between(lo, hi)] = label
    return out

def expand_codes(ranges: str) -> set[int]:
    """Expand an official explicit ICD-O morphology whitelist."""
    out = set()
    for token in ranges.split(','):
        limits = [int(x) for x in token.split('-')]
        out.update(range(limits[0], limits[-1] + 1))
    return out

def parse_stage(value: str, kind: str, cfg: dict) -> tuple[str, str]:
    """Normalize a verified category while retaining non-applicable, blank and invalid states."""
    if value in cfg['semantic']['blank_labels']:
        return ('Unknown', 'STRUCTURAL_BLANK')
    if value in cfg['semantic']['stage_na_labels']:
        return ('Unknown', 'NOT_APPLICABLE')
    if value == 'Unknown':
        return ('Unknown', 'UNKNOWN')
    val = re.sub('^[cp]', '', value, flags=re.I).upper()
    if val.startswith(kind):
        val = val[1:]
    if val not in cfg['stage']['normalized_values'][kind]:
        return ('Unknown', 'INVALID')
    if val == 'X':
        return ('Unknown', 'UNKNOWN')
    if kind == 'T' and val not in ('0', 'IS'):
        val = val[0]
    return (kind + val, 'OBSERVED')

def parse_size(value: str, cfg: dict) -> tuple[float, str, str]:
    """Use exact measurable sizes only; nonnumeric registry states retain distinct semantics."""
    if value.isdigit() and cfg['size']['exact_range'][0] <= int(value) <= cfg['size']['exact_range'][1]:
        return (float(value), 'EXACT', 'OBSERVED')
    status = cfg['size']['labels'].get(value)
    if value in cfg['semantic']['blank_labels']:
        return (np.nan, 'STRUCTURAL_BLANK', 'STRUCTURAL_BLANK')
    if status is None:
        return (np.nan, 'INVALID', 'INVALID')
    semantic = {'NO_PRIMARY_EVIDENCE': 'TRUE_ZERO', 'MICROSCOPIC_FOCUS': 'OBSERVED', 'SITE_SPECIFIC': 'NOT_APPLICABLE', 'UNKNOWN': 'UNKNOWN', 'NOT_APPLICABLE/INCONSISTENT': 'NOT_APPLICABLE'}[status]
    return (np.nan, status, semantic)

def parse_nodes(value: str, kind: str, cfg: dict) -> tuple[float, str, str]:
    """Keep zero, lower bounds, unspecified counts, and no-assessment separate."""
    opt = cfg['nodes']
    if value.isdigit() and opt['exact_min'] <= int(value) <= opt['exact_max']:
        return (float(value), 'EXACT', 'TRUE_ZERO' if int(value) == 0 else 'OBSERVED')
    status = opt[f'{kind}_special'].get(value.lstrip('0') or '0')
    if value in cfg['semantic']['blank_labels']:
        return (np.nan, 'STRUCTURAL_BLANK', 'STRUCTURAL_BLANK')
    if status is None:
        return (np.nan, 'INVALID', 'INVALID')
    return (np.nan, status, status if status in ('UNKNOWN', 'NOT_ASSESSED') else 'OBSERVED')

def construct_outcome(vital: str, cancer: str, other: str, cfg: dict) -> tuple[float, float, bool, bool]:
    """Cross-check three source fields; never classify unknown COD as other death."""
    opt = cfg['outcome']
    os = {opt['vital_alive']: 0.0, opt['vital_dead']: 1.0}.get(vital, np.nan)
    unknown = cancer == opt['unknown_cod'] or other == opt['unknown_cod']
    if vital == opt['vital_alive'] and cancer == opt['cancer_none'] and (other == opt['other_none']):
        return (os, 0.0, False, False)
    if vital == opt['vital_dead'] and cancer == opt['cancer_event'] and (other == opt['other_none']):
        return (os, 1.0, False, False)
    if vital == opt['vital_dead'] and cancer == opt['cancer_none'] and (other == opt['other_event']):
        return (os, 2.0, False, False)
    if vital == opt['vital_dead'] and cancer == opt['unknown_cod'] and (other == opt['unknown_cod']):
        return (os, np.nan, True, False)
    return (os, np.nan, unknown, True)

def harmonize(raw: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Build source-linked derived fields, never imposing predictor complete-case selection."""
    names, design = (cfg['columns'], cfg['design'])
    c = pd.DataFrame(index=raw.index)
    c['record_id'] = [cfg['input']['csv_sha256'][:12] + f':{i + 1:06d}' for i in raw.index]
    c['raw_row_number'] = np.arange(1, len(raw) + 1)
    for key, col in names.items():
        c[key + '_raw'] = raw[col]
    c['patient_id'] = raw[names['patient_id']]
    c['original_patient_id'] = c.patient_id
    c['year_dx'] = pd.to_numeric(raw[names['year_dx']], errors='coerce').astype('Int64')
    c['coding_era'] = coding_period(c.year_dx, design['coding_eras'])
    c['temporal_role'] = coding_period(c.year_dx, design['temporal_roles'])
    c['size_missingness_era'] = coding_period(c.year_dx, design['size_missingness_eras'])
    age = raw[names['age']]
    c['age_dx'] = pd.to_numeric(age.str.extract('^(\\d+)(?:\\+)? years$')[0], errors='coerce')
    c['age_dx_topcoded90'] = c.age_dx
    c['age_90plus_flag'] = age.eq(str(design['topcoded_age']) + '+ years')
    c['age_group'] = pd.cut(c.age_dx, bins=[17, 64, 74, np.inf], labels=['18-64', '65-74', '>=75']).astype('string')
    for target, key in [('sex', 'sex'), ('race_ethnicity', 'race'), ('marital_status', 'marital')]:
        c[target] = raw[names[key]].map(cfg['demographics'][key]).fillna('Unknown')
        c[target + '_unmapped_flag'] = ~raw[names[key]].isin(cfg['demographics'][key])
    c['histology_code'] = pd.to_numeric(raw[names['histology']], errors='coerce').astype('Int64')
    c['malignant_flag'] = raw[names['behavior']].isin(design['malignant_labels'])
    c['gallbladder_site_flag'] = raw[names['site']].isin(design['primary_site_codes'])
    c['strict_8140_flag'] = c.histology_code.isin(cfg['histology']['strict_codes']) & c.malignant_flag
    c['broad_adenocarcinoma_flag'] = c.histology_code.isin(expand_codes(cfg['histology']['broad_ranges'])) & c.malignant_flag
    c['broad_histology_definition'] = cfg['histology']['broad_definition']
    c['histology_confirmed'] = raw[names['confirmation']].isin(cfg['histology']['confirmation_labels'])
    c['histologic_confirmation'] = c.histology_confirmed
    c['international_primary_flag'] = raw[names['primary']].isin(cfg['histology']['primary_labels'])
    c['first_primary_flag'] = raw[names['sequence']].isin(cfg['histology']['first_primary_labels'])
    opt = cfg['surgery']
    recent = c.year_dx >= opt['new_start']
    c['surgery_old_raw'], c['surgery_new_raw'] = (raw[opt['old_column']], raw[opt['new_column']])
    c['surgery_code'] = raw[opt['old_column']].where(~recent, raw[opt['new_column']])
    c['surgery_code_raw'] = c.surgery_code
    c['surgery_source'] = np.where(recent, opt['new_column'], opt['old_column'])
    c['surgery_era'] = np.where(recent, '2023+', '1998-2022')
    groups = {code: group for group, codes in opt['code_groups'].items() for code in codes}
    c['surgery_group'] = c.surgery_code.map(groups).fillna('NEEDS_MANUAL_REVIEW')
    c['strict_resection_flag'] = c.surgery_code.isin(opt['strict_codes'])
    c['broad_resection_flag'] = c.surgery_code.isin(opt['strict_codes'] + opt['broad_add_codes'])
    for kind in ('T', 'N', 'M'):
        values = pd.Series('', index=raw.index)
        sources = pd.Series('OUTSIDE_SCOPE', index=raw.index)
        for label, item in cfg['stage']['sources'].items():
            mask = c.year_dx.between(*item['years'])
            values.loc[mask] = raw.loc[mask, item[kind]]
            sources.loc[mask] = label
        parsed = pd.DataFrame([parse_stage(v, kind, cfg) for v in values], index=raw.index)
        c[kind + '_source_raw'] = values
        c[kind + '_source'] = sources
        c[kind + '_harmonized_fine'] = parsed[0]
        c[kind + '_status'] = parsed[1]
    c['T_nonstandard_registry_flag'] = c.T_harmonized_fine.isin(cfg['stage']['nonstandard_T_values'])
    c['T_model'] = c.T_harmonized_fine.map(cfg['stage']['T_model_mapping']).fillna('Unknown')
    c['N_model'] = c.N_harmonized_fine.map(cfg['stage']['N_model_mapping']).fillna('Unknown')
    c['M_harmonized'] = c.M_harmonized_fine
    c['summary_stage'] = raw[names['summary']].map(cfg['stage']['summary_mapping']).fillna('Unknown')
    c['summary_stage_unmapped_flag'] = ~raw[names['summary']].isin(cfg['stage']['summary_mapping'])
    c['summary_stage_harmonized'] = c.summary_stage.map(cfg['stage']['summary_collapsed_mapping'])
    nondistant = c.summary_stage.isin(cfg['stage']['explicit_non_distant'])
    c['stage_conflict_flag'] = c.M_harmonized.eq('M0') & c.summary_stage.eq('Distant') | c.M_harmonized.eq('M1') & nondistant
    c['nonmetastatic_broad_flag'] = (c.M_harmonized.eq('M0') | c.M_harmonized.eq('Unknown') & c.M_status.eq('UNKNOWN')) & nondistant & ~c.stage_conflict_flag
    opt = cfg['grade']
    recent = c.year_dx >= opt['switch_year']
    c['grade_fine_raw'] = raw[opt['old_column']].where(~recent, raw[opt['new_column']])
    c['grade_source'] = np.where(recent, opt['new_column'], opt['old_column'])
    c['grade_source_era'] = np.where(recent, 'DERIVED_2018+', 'HISTORIC_THROUGH_2017')
    c['grade_model'] = c.grade_fine_raw.map(opt['mapping']).fillna('Unknown')
    c['grade_status'] = np.where(c.grade_model.eq('Unknown'), 'UNKNOWN', 'OBSERVED')
    c.loc[c.grade_fine_raw.isin(cfg['semantic']['blank_labels']), 'grade_status'] = 'STRUCTURAL_BLANK'
    c.loc[c.grade_fine_raw.isin(opt['non_epithelial_labels']), 'grade_status'] = 'NOT_APPLICABLE'
    known_grade = list(opt['mapping']) + opt['non_epithelial_labels'] + cfg['semantic']['blank_labels']
    c.loc[~c.grade_fine_raw.isin(known_grade), 'grade_status'] = 'INVALID'
    size = pd.DataFrame([parse_size(v, cfg) for v in raw[names['size']]], index=raw.index)
    c['tumor_size_mm'], c['tumor_size_status'], c['tumor_size_semantic'] = (size[0], size[1], size[2])
    c['tumor_size_missing_flag'] = c.tumor_size_mm.isna()
    c['tumor_size_imputable_flag'] = c.tumor_size_semantic.eq('UNKNOWN')
    for key, kind in [('nodes_exam', 'examined'), ('nodes_pos', 'positive')]:
        vals = pd.DataFrame([parse_nodes(v, kind, cfg) for v in raw[names[key]]], index=raw.index)
        c['nodes_' + kind], c['nodes_' + kind + '_status'], c['nodes_' + kind + '_semantic'] = (vals[0], vals[1], vals[2])
    c['nodes_examined_numeric'] = c.nodes_examined
    c['nodes_examined_lower_bound'] = c.nodes_examined
    c.loc[c.nodes_examined_status.eq('AT_LEAST_90'), 'nodes_examined_lower_bound'] = cfg['nodes']['lower_bound_code']
    c['nodal_assessment_flag'] = pd.Series(pd.NA, index=raw.index, dtype='boolean')
    c.loc[c.nodes_examined.eq(0), 'nodal_assessment_flag'] = False
    assessed = c.nodes_examined.gt(0) | c.nodes_examined_status.isin(['AT_LEAST_90', 'ASPIRATION_OR_CORE_ONLY', 'SAMPLING_COUNT_UNKNOWN', 'DISSECTION_COUNT_UNKNOWN', 'EXAMINED_COUNT_UNKNOWN'])
    c.loc[assessed, 'nodal_assessment_flag'] = True
    c['exact_node_count_flag'] = c.nodes_examined_status.eq('EXACT') & c.nodes_positive_status.eq('EXACT')
    c['node_count_conflict_flag'] = c.exact_node_count_flag & (c.nodes_positive > c.nodes_examined)
    c['node_exact_usable_flag'] = c.exact_node_count_flag & c.nodes_examined.gt(0) & ~c.node_count_conflict_flag
    c['node_assessment_group'] = 'Unknown'
    c.loc[c.nodes_examined.eq(0), 'node_assessment_group'] = 'No nodes examined'
    c.loc[c.nodes_examined.between(1, cfg['nodes']['group_cut'] - 1), 'node_assessment_group'] = '1-5 examined'
    c.loc[c.nodes_examined.ge(cfg['nodes']['group_cut']) | c.nodes_examined_status.eq('AT_LEAST_90'), 'node_assessment_group'] = '>=6 examined'
    c.loc[assessed & c.nodes_examined.isna() & ~c.nodes_examined_status.eq('AT_LEAST_90'), 'node_assessment_group'] = 'Examined but count unknown'
    c['LNR'] = np.nan
    c['LODDS'] = np.nan
    exact = c.node_exact_usable_flag
    c.loc[exact, 'LNR'] = c.loc[exact, 'nodes_positive'] / c.loc[exact, 'nodes_examined']
    correction = cfg['nodes']['lodds_continuity']
    c.loc[exact, 'LODDS'] = np.log((c.loc[exact, 'nodes_positive'] + correction) / (c.loc[exact, 'nodes_examined'] - c.loc[exact, 'nodes_positive'] + correction))
    c['chemotherapy'] = raw[names['chemo']].map(cfg['treatment']['chemo']).fillna('NEEDS_MANUAL_REVIEW')
    c['radiation'] = np.where(raw[names['radiation']].isin(cfg['treatment']['radiation_yes']), 'Yes', 'No/Unknown')
    c['radiation_unmapped_flag'] = ~raw[names['radiation']].isin(cfg['treatment']['radiation_yes'] + cfg['treatment']['radiation_other'])
    c['survival_days_raw'] = raw[names['survival_days']]
    days = pd.to_numeric(c.survival_days_raw.where(~c.survival_days_raw.isin(cfg['outcome']['survival_unknown'])), errors='coerce')
    c['survival_days_numeric'] = days
    c['zero_day_survival_flag'] = days.eq(0)
    c['survival_days_analysis'] = days.mask(c.zero_day_survival_flag, design['zero_day_correction'])
    c['survival_years'] = c.survival_days_analysis / design['days_per_year']
    c['survival_months_numeric'] = pd.to_numeric(raw[names['survival_months']].replace('Unknown', np.nan), errors='coerce')
    events = pd.DataFrame([construct_outcome(v, a, b, cfg) for v, a, b in zip(raw[names['vital']], raw[names['cancer_cod']], raw[names['other_cod']])], index=raw.index)
    c['event_os'], c['event_competing'], c['unknown_cod_flag'], c['outcome_conflict_flag'] = (events[0], events[1], events[2], events[3])
    c['core_complete_case_flag'] = c[cfg['predictors']['core']].notna().all(axis=1) & ~c[cfg['predictors']['core']].isin(['Unknown']).any(axis=1)
    c['core_invalid_state_flag'] = c[['T_status', 'N_status', 'M_status', 'grade_status']].eq('INVALID').any(axis=1)
    return c.copy()

