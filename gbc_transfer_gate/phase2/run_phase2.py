"""Phase 2: exclude Summary Distant only, retain Unknown; no models.

Date: 2026-10-26. Python 3.13.3; numpy 2.4.2; pandas 2.3.3;
pyarrow 23.0.1; openpyxl 3.1.5. CR: PCG64/default_rng seed 20260904,
B=1000. Life table: original R 4.4.3/L'Ecuyer-CMRG seed 20260905,
stream advance 5, B=1000. Source patients are the resampling unit.
Public path adapter: explicit --formal only; no arguments print help.
Only comparison CSV and decision Markdown are written to a pre-existing
GBC_OUTPUT_ROOT/phase2 outside the public checkout; existing results are never
replaced. GBC_FINAL_RUN_ROOT and GBC_PREPARATION_ROOT are read-only inputs.
The repository update only parses this file; it does not run this bootstrap.
"""
import argparse
import ast
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import threading

import numpy as np
import pandas as pd
import pyarrow
import pyarrow.parquet as pq
import openpyxl
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
                    'STOP: V2 bootstrap provenance mismatch')
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
    AJSpec, interval = load_aj(Path(os.environ['GBC_CODE_ROOT']) / 'python/scripts/stage1_burden.py')
    original_specs = make_specs(dynamic, AJSpec)
    original_point = np.stack([s.evaluate(np.ones(len(dynamic))) for s in original_specs])
    for metric, values in metric_values(original_point).items():
        for s, value in enumerate(values):
            require(abs(value - frozen[(s, metric)]['estimate']) < 1e-8,
                    f'STOP: original CR point not reproduced: {metric} L{s}')
    print('ORIGINAL AJ POINT RECONCILIATION PASS (all 30 values)', flush=True)
    if check_only:
        return None
    specs = make_specs(sens, AJSpec)
    point = np.stack([s.evaluate(np.ones(len(sens))) for s in specs])
    draws = np.empty((B, 6, 8))
    rng = np.random.default_rng(SEED)
    for b in range(B):
        sample = rng.integers(0, len(sens), size=len(sens))
        weights = np.bincount(sample, minlength=len(sens))
        for s, spec in enumerate(specs):
            draws[b, s] = spec.evaluate(weights)
        if (b + 1) % 100 == 0:
            print(f'CR patient bootstrap {b + 1}/{B}', flush=True)
    point_metrics, boot_metrics = metric_values(point), metric_values(draws)
    rows = []
    for s in range(6):
        for metric in point_metrics:
            original = frozen[(s, metric)]
            # Original interval refuses a percentile CI unless all draws are valid.
            result = interval(point_metrics[metric][s], boot_metrics[metric][:, s])
            unit = 'percent' if metric in ('GBC_CIF', 'Other_CIF') else 'percentage_points' if metric == 'Delta_CIF' else 'months'
            rows.append(comparison('competing_risk', s, metric, unit, original,
                len(specs[s].indices), result['estimate'], result['ci_lower'], result['ci_upper'],
                result['bootstrap_valid'], SEED, 'NumPy PCG64/default_rng',
                '100% valid required; original Stage1 interval'))
    require(np.all(point[:, 4:6] >= 0) and np.all(point[:, 4:6].sum(axis=1) <= 1 + 1e-10),
            'STOP: CR probability closure failed')
    return rows


def comparison(module, s, metric, unit, original, n, estimate, lo, hi, valid, seed, rng, policy):
    return dict(module=module, landmark=s, horizon_years=3, metric=metric, unit=unit,
        original_n=original['n'], sensitivity_n=n, original_estimate=original['estimate'],
        original_ci_lower=original['lo'], original_ci_upper=original['hi'],
        sensitivity_estimate=estimate, sensitivity_ci_lower=lo, sensitivity_ci_upper=hi,
        estimate_change=estimate - original['estimate'],
        change_unit='percentage_points' if unit in ('percent', 'percentage_points') else 'months',
        change_ci_status='NOT ESTIMATED; not a paired main-vs-sensitivity contrast',
        original_bootstrap_requested=1000, original_bootstrap_valid=original['valid'],
        original_seed=20260904 if module == 'competing_risk' else 20260905,
        sensitivity_bootstrap_requested=B, sensitivity_bootstrap_valid=valid,
        sensitivity_seed=seed, rng=rng,
        ci_method='Pointwise percentile 2.5/97.5; not simultaneous', validity_policy=policy,
        sensitivity_definition='Exclude Summary Stage Distant only; retain Unknown',
        time_origin='Diagnosis; selected by eventual resection')


def case_check(root, patient, long):
    fields = ['Year of diagnosis', 'Patient ID', 'SEER Combined Mets at DX-liver (2010+)',
        'Derived SEER Combined T (2016-2017)', 'Derived SEER Combined N (2016-2017)',
        'Derived SEER Combined M (2016-2017)', 'Derived SEER Combined M Src (2016-2017)',
        '7th Edition Stage Group Recode (2016-2017)', 'Derived SEER Cmb Stg Grp (2016-2017)',
        'RX Summ--Surg Prim Site (1998-2022)']
    raw = pd.read_csv(Path(os.environ['GBC_PREPARATION_ROOT']) / 'data_raw/gallbladder_SEER_2004_2023_raw.csv',
                      dtype=str, keep_default_na=False, usecols=fields)
    aligned = raw.iloc[patient.raw_row_number.to_numpy(int) - 1].reset_index(drop=True)
    require(np.array_equal(aligned['Patient ID'].to_numpy(), patient.patient_id.astype(str).to_numpy())
        and np.array_equal(aligned['Year of diagnosis'].astype(int).to_numpy(), patient.year_dx.to_numpy()),
        'STOP: original case linkage mismatch')
    mask = patient.M_harmonized.eq('M0').to_numpy() & aligned[fields[2]].eq('Yes').to_numpy()
    require(mask.sum() == 1, 'STOP: conflict count changed; do not guess')
    item = patient.iloc[np.flatnonzero(mask)[0]]
    record = aligned.iloc[np.flatnonzero(mask)[0]]
    counts = [int(item.survival_days_analysis > s * YEAR) for s in (1, 2, 3)]
    stored_n = int(long.record_id.eq(item.record_id).sum())
    require(item.year_dx == 2016 and record[fields[5]] == 'c0' and counts == [0, 0, 0]
            and stored_n == 0, 'STOP: single-case participation changed')
    # Identifiers and exact survival duration are deliberately not returned.
    return dict(status='UNRESOLVED', year=2016, T=record[fields[3]], N=record[fields[4]],
        M=record[fields[5]], M_source=record[fields[6]], stage_group=record[fields[7]],
        combined_stage=record[fields[8]], surgery=record[fields[9]], liver='Yes',
        landmark_eligible=counts, stored_landmark_rows=stored_n)


def life_sensitivity(root, rscript, original, sensitivity):
    frozen = [r for r in sheet_records(root / 'outputs/LIFETABLE_RESULTS.xlsx', 'rmst_gap', 'landmark')
              if r['analysis_type'] == 'PRIMARY']
    require(len(frozen) == 6, 'STOP: original life results incomplete')
    fields = ['patient_id', 'record_id', 'year_dx', 'age_dx', 'sex', 'survival_days_analysis',
              'event_os', 'summary_stage_harmonized']
    payload = dict(root=str(root), code_root=os.environ['GBC_CODE_ROOT'], patients=json.loads(sensitivity[fields].to_json(orient='records', double_precision=15)),
        original_patients=json.loads(original[fields].to_json(orient='records', double_precision=15)),
        frozen_original_points=[{k: r[k] for k in ['landmark', 'observed_RMST_months', 'expected_RMST_months', 'gap_months']} for r in frozen])
    env = dict(os.environ, LC_ALL='C', LANG='C')
    proc = subprocess.Popen([str(rscript), '--vanilla', str(Path(__file__).with_name('phase2_lifetable.R'))],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        encoding='utf-8', env=env)
    def relay():
        for line in proc.stderr:
            print(line.rstrip(), flush=True)
    worker = threading.Thread(target=relay, daemon=True)
    worker.start()
    proc.stdin.write(json.dumps(payload, allow_nan=False))
    proc.stdin.close()
    raw_result = proc.stdout.read()
    code = proc.wait()
    worker.join()
    require(code == 0, f'STOP: life-table helper failed (exit {code})')
    result = json.loads(raw_result)
    require(result['B'] == B and result['seed'] == 20260905,
            'STOP: life bootstrap metadata mismatch')
    rows = []
    mapping = [('Observed_RMST', 'observed_RMST_months', 'observed'),
               ('Expected_RMST', 'expected_RMST_months', 'expected'),
               ('RMST_deficit', 'gap_months', 'gap')]
    for item in result['summary']:
        s = int(item['landmark'])
        original_row = next(r for r in frozen if r['landmark'] == s)
        for metric, field, prefix in mapping:
            original_dict = dict(n=int(original_row['n']), estimate=original_row[field],
                lo=original_row[prefix + '_lower95'], hi=original_row[prefix + '_upper95'],
                valid=int(round(original_row[prefix + '_valid_fraction'] * B)))
            valid = int(round(item[prefix + '_valid_fraction'] * B))
            rows.append(comparison('life_table', s, metric, 'months', original_dict, int(item['n']),
                item[field], item[prefix + '_lower95'], item[prefix + '_upper95'],
                valid, 20260905, "R L'Ecuyer-CMRG; stream advance 5",
                '>=95% valid required; original life-table interval'))
    require(len(rows) == 18, 'STOP: incomplete life-table summary')
    return rows, result


def interval_text(row, prefix):
    return f"{row[prefix + '_estimate']:.4f} [{row[prefix + '_ci_lower']:.4f}, {row[prefix + '_ci_upper']:.4f}]"


def write_decision(path, frame, life_meta, case):
    lines = ['# Phase 2：最小敏感性与方法学核查', '', '原Phase 2规格日期：2026-10-26。最终判断：**GO_AFTER_FIX**。', '',
        '本阶段的数值敏感性已完成。该判断允许基于下述边界准备转投；不代表已修改论文或证明科学创新性。', '',
        '## 1. 冻结核查与执行范围', '',
        '- PASS：Source 7007；Dynamic 3918；Life-table L0 3796；Distant 分别为354/205/204。',
        '- PASS：原动态L0–L5=3918/2496/1786/1423/1192/1047；冻结long的身份、事件、时间和截尾逐LM核对一致。',
        '- PASS：唯一敏感性为排除Summary Stage=Distant并保留Unknown；CR L0=3713，Life L0=3592。',
        '- 动态Unknown仍保留20例；动态T4从83例变为0例。该敏感性缩窄局部侵犯范围，不能解释为删除205个已证实错误病例。',
        '- 原主结果和CI直接读取冻结工作簿；未重新bootstrap主队列。原CR的30个点值及生命表18个点值已用原估计函数复现，容差1e-8。',
        '- 未运行开发、验证、更新或标准化；未修改冻结输入、原脚本、论文、图表或GitHub。', '',
        '## 2. 方法与随机数', '',
        'CR：通过AST载入公共python/scripts/stage1_burden.py保留的原AJSpec和interval定义；风险集T>s×365.25，后续1095.75天，0天原有0.5天处理不变，提前删失保持右删失。',
        'CR bootstrap：B=1000，seed=20260904，NumPy default_rng/PCG64；对3713名来源患者按保留后的原始顺序有放回抽样，同一draw及其整数权重跨全部LM与两原因共用。Delta每draw先算Other−GBC，再取2.5/97.5百分位，未相减边际CI。原Stage1规则要求该指标1000次全部有效才发布CI。',
        "Life-table bootstrap：B=1000，seed=20260905，原R4.4.3的L'Ecuyer-CMRG、stream advance5；3592名患者按原patient_id稳定排序。每次draw在同一来源患者中保留重复计数，全部LM共享draw；重新进行匹配，并在同一匹配子集上重新积分observed与expected。沿用原至少95%有效重复才发布CI的规则。",
        '匹配：sex×floor(age_dx+s+j)×(year_dx+s+j)，j=0,1,2；all-races生命表的Expected rate（每百万人的年条件存活数）除以1,000,000得到年条件存活概率；原分段指数expected积分和右连续KM observed积分，月份=30.4375天。无尾部外推。本轮不增加原calendar-year+1变体。',
        '所有区间为点态探索性percentile CI，不是同时区间。estimate_change仅为两个点值之差，不提供main-vs-sensitivity差的CI；没有证明等效性或设定事后MCID。', '',
        f"Python {sys.version.split()[0]}; NumPy {np.__version__}; pandas {pd.__version__}; pyarrow {pyarrow.__version__}; openpyxl {openpyxl.__version__}; R {life_meta['versions']['R']}; survival {life_meta['versions']['survival']}; jsonlite {life_meta['versions']['jsonlite']}。",
        f"生命表54000行、all-races唯一键10800；六LM点估计匹配率均为100%。整次draw失败数={life_meta['qc']['whole_draw_failures']}；48行指标的实际有效重复范围为{int(frame.sensitivity_bootstrap_valid.min())}–{int(frame.sensitivity_bootstrap_valid.max())}/1000。", '',
        '## 3. 完整并列结果', '',
        '每格为点估计 [95% CI]；CIF单位%，Delta单位百分点，RMTL/RMST单位月。完整精度见sensitivity_comparison.csv。', '']
    for module, title in [('competing_risk', '竞争风险：五项指标'), ('life_table', '生命表：三项指标')]:
        lines += [f'### {title}', '', '| LM | 指标 | 原n | 敏感性n | 原结果 [95% CI] | 敏感性 [95% CI] | 点值变化 | 有效B |',
                  '|---|---|---:|---:|---|---|---:|---:|']
        for row in frame.loc[frame.module.eq(module)].to_dict('records'):
            lines.append(f"| L{row['landmark']} | {row['metric']} | {row['original_n']} | {row['sensitivity_n']} | {interval_text(row, 'original')} | {interval_text(row, 'sensitivity')} | {row['estimate_change']:+.4f} | {row['sensitivity_bootstrap_valid']}/1000 |")
        lines.append('')
    lines += ['## 4. 竞争风险结果稳健性', '']
    for lm in (4, 5):
        r = frame.loc[(frame.metric == 'Delta_CIF') & (frame.landmark == lm)].iloc[0]
        conclusion = '点态区间仍高于0' if r.sensitivity_ci_lower > 0 else '点态区间包含或低于0，不能确认Other超过GBC'
        lines.append(f"- L{lm}：原差值{r.original_estimate:.4f} pp [{r.original_ci_lower:.4f}, {r.original_ci_upper:.4f}]；敏感性{r.sensitivity_estimate:.4f} pp [{r.sensitivity_ci_lower:.4f}, {r.sensitivity_ci_upper:.4f}]；变化{r.estimate_change:+.4f} pp；{conclusion}。")
    delta = frame.loc[frame.metric.eq('Delta_CIF')].sort_values('landmark')
    same_sign = bool(np.all(np.sign(delta.original_estimate) == np.sign(delta.sensitivity_estimate)))
    lines += [f"- L0–L5 Delta的点估计正负方向{'全部一致' if same_sign else '存在变化'}；这只说明本次排除下的描述性方向，不是永久交叉年份或多重比较控制后的证据。"]
    for metric in ['GBC_CIF', 'Other_CIF', 'GBC_RMTL', 'Other_RMTL']:
        z = frame.loc[frame.metric.eq(metric)].sort_values('landmark')
        lines.append(f"- {metric}：L0敏感性{z.iloc[0].sensitivity_estimate:.4f}，L5敏感性{z.iloc[-1].sensitivity_estimate:.4f}；六LM相对原点值的最大绝对变化{z.estimate_change.abs().max():.4f} {z.iloc[0].change_unit}。")
    lines += ['', '## 5. RMST deficit稳健性', '']
    gaps = frame.loc[frame.metric.eq('RMST_deficit')].sort_values('landmark')
    for _, r in gaps.iterrows():
        lines.append(f"- L{r.landmark}：原{r.original_estimate:.4f}月，敏感性{r.sensitivity_estimate:.4f}月 [{r.sensitivity_ci_lower:.4f}, {r.sensitivity_ci_upper:.4f}]；变化{r.estimate_change:+.4f}月。")
    all_positive = bool((gaps.sensitivity_ci_lower > 0).all())
    decreasing = bool(np.all(np.diff(gaps.sensitivity_estimate) <= 0))
    lines += [f"- 敏感性六个deficit点态CI{'均在0以上' if all_positive else '并非均在0以上'}；点估计随landmark{'逐步缩小' if decreasing else '不完全单调'}。",
        f"- 六LM deficit最大绝对点值变化为{gaps.estimate_change.abs().max():.4f}月。未以CI重叠检验‘无差异’，也未把统计稳定解释为临床等效。",
        '- 每个LM的observed/expected均来自同一3592人来源下的新匹配风险集。CR与Life的纳排仍不同，不能把CR RMTL与Life observed强行闭合。', '',
        '## 6. 2016年单例冲突', '',
        f"- **{case['status']}**：原T/N/M={case['T']}/{case['N']}/{case['M']}，M来源={case['M_source']}，liver=Yes，7th stage group={case['stage_group']}，Combined stage={case['combined_stage']}，手术码={case['surgery']}。没有病历依据判定哪一个登记字段正确；分期未被修改。",
        '- 本轮按原始行号关联原CSV，校验7007例Patient ID和年份；只输出上述非标识字段。',
        '- 关键参与核查：该例虽按诊断年被标为2012–2017 validation source及2015–2017更新后评价source，但严格L1/L2/L3风险集资格均为0，冻结landmark-long中实际0行。',
        '- 因此没有直接参与现有L1–L3预测、IPCW、AJ或校准性能点估计，不在2012–2014更新拟合，也不在本轮2004–2015主动态/Life敏感性。无需为它重跑模型。',
        '- 原次要bootstrap从全source抽人后构建风险集；删除一个非风险集source行可能改变有限随机draw，不能声称已做删除对照或CI完全不变。登记冲突继续UNRESOLVED，但没有证据显示它改变了现有实际风险集点估计。',
        '- 证据：run_v2_stage1.py:126–166；02_validation.R:112–152、230–236、401–405、659–665；03_recalibration.R:160–179、200、276、356–368。', '',
        '## 7. 分期语义与时间零点', '',
        '- **WARN**：M0指按各时代登记derived字段harmonize的M0，不等于逐人临床排除远处转移；Summary Distant可以包含更广泛直接蔓延或跨体系节点差异。当前敏感性是范围检查，不是证明354例都误入。',
        '- **WARN/UNRESOLVED**：实际时间零点仍为诊断日；最终切除状态和病理信息属于诊断后信息。首次治疗天数不等于手术时间。不能宣称本轮消除了immortal time bias。',
        '- 可支持：在最终接受切除、登记derived M0的人群内，从诊断日起算、存活并可观察至各LM者未来3年死亡构成、时间负担及另定义生命表人群的描述性差距。',
        '- 不支持：真正以切除完成为零点的术后第N年风险、初诊时已经可用的治疗选择工具、手术因果获益、治愈或归一化。若坚持这些目标，现有数据不足，该用途STOP。', '',
        '## 8. 最终判断与剩余科学阻断', '',
        '**GO_AFTER_FIX**。本次有限敏感性和数值核查已执行；完整结果如上，不把它们自动等同于科学增量已足够。',
        '- 必须落实到后续转投材料：如实呈现敏感性是否支持原方向、T4 83→0带来的范围变化；统一分期语义和诊断时钟；保留单例UNRESOLVED及其实际未入风险集的说明。本文档提供结论，未自动修改论文。',
        '- 剩余科学问题：CIF/RMTL共享同一曲线，RMST deficit还共享observed survival；指标增多不能算多项独立发现。本轮没有新增文献创新性或临床效用证据。',
        '- 没有因为统计结果可复现就认定Scientific Reports的科学增量问题已解决；也不增加复杂模型或下载数据库。', '',
        '## 9. 输出和复现', '',
        '- run_phase2.py --formal --rscript <Rscript>：显式正式入口；无参数仅打印帮助。所有根目录由GBC_CODE_ROOT/GBC_FINAL_RUN_ROOT/GBC_PREPARATION_ROOT/GBC_OUTPUT_ROOT配置；须预先建立仓库外phase2输出子目录，已有结果拒绝覆盖。',
        '- sensitivity_comparison.csv：48行，CR 30行+Life 18行；原/敏感性估计与CI并列，单位、样本量、B、seed、区间方法逐行注明；不含患者数据。',
        '- run_phase2.py、phase2_lifetable.R：当前有限敏感性源；phase2.py另为Phase3使用的只读intake。AJ及生命表匹配/积分函数从公共源读取，不需要仓库外自定义代码。',
        '- 无中间患者表、图表、哈希、日志、原始draws文件；bootstrap仅在内存中。',
        '- 原结果来源：outputs/STAGE1_RESULTS_v2.xlsx 的AJ_CIF/RMTL/Bootstrap_CI；outputs/LIFETABLE_RESULTS.xlsx 的rmst_gap PRIMARY。',
        '- 正式定义和证据背景：../SCIENTIFIC_AUDIT.md。阶段完成后停止。', '']
    with path.open('x', encoding='utf-8') as output_decision:
        output_decision.write('\n'.join(lines))


def _configured_directory(name, default=None):
    value = os.environ.get(name, default)
    require(bool(value), f"Set {name} before an authorized formal run")
    path = Path(value).expanduser().resolve(strict=True)
    require(path.is_dir(), f"{name} must name an existing directory")
    return path


def _within(path, directory):
    # pathlib uses the host's case-aware path semantics, including Windows.
    return path == directory or directory in path.parents


def main():
    parser = argparse.ArgumentParser(
        description="Original limited Phase 2 sensitivity: exclude Summary Distant only. "
                    "Requires authorized private data and runs 1000 patient bootstrap attempts. "
                    "No arguments print help; no analysis starts implicitly.")
    parser.add_argument("--formal", action="store_true",
                        help="Explicit authorization to run the original finite sensitivity")
    parser.add_argument("--rscript", type=Path, default=None,
                        help="Installed R 4.4.3 Rscript executable; alternatively put Rscript on PATH")
    if len(sys.argv) == 1:
        parser.print_help()
        return
    args = parser.parse_args()
    if not args.formal:
        parser.error("No analysis started: --formal is required")
    code = _configured_directory("GBC_CODE_ROOT", str(Path(__file__).resolve().parents[2]))
    root = _configured_directory("GBC_FINAL_RUN_ROOT")
    preparation = _configured_directory("GBC_PREPARATION_ROOT")
    output_root = _configured_directory("GBC_OUTPUT_ROOT")
    output = (output_root / "phase2").resolve(strict=True)
    require(output.is_dir(), "Create the private GBC_OUTPUT_ROOT/phase2 directory before running")
    for protected in (code, root, preparation):
        require(not _within(output, protected),
                "STOP: output must be outside the public checkout and frozen private input roots")
    configured_python = os.environ.get("GBC_PYTHON", sys.executable)
    python = Path(configured_python).resolve(strict=True)
    require(python.is_file(), "GBC_PYTHON must be the installed Python executable")
    require(os.path.samefile(python, Path(sys.executable)),
            "Invoke this script with GBC_PYTHON so the configured environment is actually used")
    rscript_value = args.rscript or shutil.which("Rscript")
    require(rscript_value is not None, "Supply --rscript for installed R 4.4.3")
    rscript = Path(rscript_value).resolve(strict=True)
    require(rscript.is_file(), "Rscript executable not found")
    os.environ["GBC_CODE_ROOT"] = str(code)
    os.environ["GBC_FINAL_RUN_ROOT"] = str(root)
    os.environ["GBC_PREPARATION_ROOT"] = str(preparation)
    os.environ["GBC_OUTPUT_ROOT"] = str(output_root)
    os.environ["GBC_PYTHON"] = str(python)
    require((code / "python/scripts/stage1_burden.py").is_file(),
            "Public AJ source is missing")
    require((code / "scripts/current_kernels/lifetable_core.R").is_file(),
            "Public life-table kernel is missing")
    require(Path(__file__).with_name("phase2_lifetable.R").is_file(),
            "Phase 2 life-table helper is missing")
    csv = output / "sensitivity_comparison.csv"
    decision = output / "PHASE2_DECISION.md"
    require(not csv.exists() and not decision.exists(),
            "STOP: output already exists; choose a new pre-existing private output root")
    try:
        patient, dynamic, life, sens, life_sens, long = preflight(root)
        original = frozen_cr(root)
        case = case_check(root, patient, long)
        rows = cr_sensitivity(root, dynamic, sens, original)
        life_rows, life_meta = life_sensitivity(root, rscript, life, life_sens)
        frame = pd.DataFrame(rows + life_rows)
        require(len(frame) == 48 and not frame[["sensitivity_estimate", "sensitivity_ci_lower", "sensitivity_ci_upper"]].isna().any().any(),
                "STOP: incomplete estimates/intervals; do not release partial results")
        require((frame.sensitivity_ci_lower <= frame.sensitivity_ci_upper).all(),
                "STOP: invalid percentile interval layout")
        # Exclusive creation protects existing outputs even if another process starts.
        with csv.open("x", encoding="utf-8-sig", newline="") as output_csv:
            frame.to_csv(output_csv, index=False, float_format="%.12g")
        write_decision(decision, frame, life_meta, case)
        print("PHASE 2 COMPLETE: 48 comparison rows; no frozen output changed", flush=True)
        print(frame.loc[frame.metric.isin(["Delta_CIF", "RMST_deficit"]),
            ["landmark", "metric", "original_estimate", "sensitivity_estimate", "sensitivity_ci_lower", "sensitivity_ci_upper"]].to_string(index=False), flush=True)
    except Exception as exc:
        if not decision.exists():
            with decision.open("x", encoding="utf-8") as output_decision:
                output_decision.write("# Phase 2\n\nFinal status: STOP\n\n" + str(exc)
                    + "\n\nNo frozen cohort or source was changed. No valid complete sensitivity result is claimed.\n")
        raise


if __name__ == "__main__":
    main()
