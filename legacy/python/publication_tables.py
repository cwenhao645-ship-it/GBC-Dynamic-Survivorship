"""Curated publication definitions; no analysis runs on import."""
from __future__ import annotations
import copy,re
def cell(x):
    s = str(x).replace('\xad', '').replace('\ufffe', '').replace('�', '')
    if s in ('NA', 'N/A', 'None', ''):
        return '—'
    if s == 'C_FULL':
        return 'C'
    s = s.replace(' minus ', ' − ').replace('B-A', 'B−A').replace('C-A', 'C−A').replace('C-B', 'C−B').replace('AUC2', 'AUC')
    s = re.sub('(?<=\\d)-(?=\\d{4})', '–', s)
    s = re.sub('(?<![\\w])-(?=\\d)', '−', s)
    return s

TERMS = {'Age_linear': 'Age, linear (per 10 y)', 'Age_rcs1': 'Age, spline basis 1', 'Age_rcs2': 'Age, spline basis 2', 'Age': 'Age (joint)', 'age': 'Age (per 10 y)', 'T34': 'T3/4 vs T1', 'T2': 'T2 vs T1', 'Nplus': 'N+ vs N0', 'G2': 'G2 vs G1', 'G34': 'G3/4 vs G1', 'T_unknown': 'T: Unknown vs T1', 'N_unknown': 'N: Unknown vs N0', 'G_unknown': 'Grade: Unknown vs G1', 'Male': 'Male vs Female', 'Age10': 'Age (per 10 y)', 'GLOBAL': 'Global', 'T': 'T category (joint)', 'N': 'N category (joint)', 'Grade': 'Grade (joint)', 'Sex': 'Sex'}

def term(s):
    s = s.removeprefix('Dynamic_').removeprefix('Sparse_')
    if s.endswith('_by_s'):
        return TERMS[s[:-5]] + ' × (s−2)'
    return TERMS.get(s, s)

def pvalue(s):
    v = float(s)
    if v < 0.001:
        return '<.001'
    if v > 0.99:
        return '>.99'
    return (f'{v:.3f}' if v < 0.01 else f'{v:.2f}').lstrip('0')

def _legacy_matrices(aggregates):
    out = {}
    old = aggregates['supp_tables']
    flowlabels = {'01': '胆囊原发恶性肿瘤（C23.9）', '03': '年龄≥18岁', '04': '腺癌组织学8140/3', '06': '组织学阳性证实', '07': '满足国际规则原发肿瘤资格', '08': '接受预定义切除手术', '09': '明确整合M0', '11': '死因可分类，进入竞争风险源队列'}
    out[1] = [['Sequential criterion', 'Before, No.', 'Excluded, No.', 'Remaining, No.']] + [[flowlabels[r[0][:2]]] + r[1:] for r in old[0][1:] if r[0][:2] in flowlabels]
    out[2] = [r[:7] for r in old[3]]
    out[2][0] = ['Target', 'Contrast', 'LM', 'Reference, n', 'Supported, n', 'Coverage', 'Support']
    for new, oi in [(3, 4), (4, 5)]:
        src = old[oi]
        same = all((r[9] == r[10] for r in src[1:]))
        rows = []
        for r in src:
            rr = r[:10] if same else r[:11]
            if r is not src[0]:
                for j in (7, 8):
                    if rr[j] not in ('—', 'NA') and '(' not in rr[j]:
                        rr[j] += ' (—)'
            rows.append(rr)
        rows[0] = ['Target', 'Contrast', 'Cause', 'LM', 'Support', 'Supported, n', 'Coverage', 'ΔCIF, pp (95% CI)', 'ΔRMTL, mo (95% CI)'] + (['Valid bootstrap, %'] if same else ['CIF valid, %', 'RMTL valid, %'])
        out[new] = rows
    out[5] = [old[6][0][:5]] + [[r[0], r[1], term(r[2]), r[3], r[4]] for r in old[6][1:]]
    out['6A'] = [['Model', 'Cause', 'Term', 'P value']] + [[r[0], r[1], term(r[2]), pvalue(r[4])] for r in old[7][1:] if r[4] != '—']
    out['6B'] = [['Model', 'Cause', 'Term', 'D', '95% CI', 'Valid bootstrap, %']] + [[r[0], r[1], term(r[2]), r[5], r[6] + '–' + r[7], r[8]] for r in old[7][1:] if r[5] != '—']
    for new, oi in [(7, 8), (9, 10), (10, 11), (11, 12), (12, 13)]:
        out[new] = copy.deepcopy(old[oi])
    out[8] = [r[:7] for r in old[9]]
    assert all((r[-1] == '1,000' for r in old[1][1:]))
    out[13] = [r[:-1] for r in old[1]]
    out[14] = copy.deepcopy(old[2])
    for r in out[14][1:]:
        if r[2] == 'L0':
            r[-1] = 'Reference'
    for k, rows in out.items():
        out[k] = [[cell(x) for x in r] for r in rows]
        out[k][0] = [x.replace('Landmark', 'LM').replace('Calibration slope', 'Calibration\nslope') for x in out[k][0]]
    for r in out[10][1:]:
        r[0] = r[0].title()
    out[12][0][-1] = 'Year+1 −\nprimary, mo'
    return out

NOTES = {1: '各步按所列顺序实施。Summary Stage仅用于一致性及敏感性描述，不作为明确M0主队列的排除条件。零排除且不增加资格信息的重复检查未列出。M0表示无远处转移。', 2: 'LM为landmark。共同支持按性别、其余两项病理特征及年龄重叠确定。PASS为参考覆盖率≥90%，LIMITED为70%至不足90%，FAIL为<70%。每个LM的标准化限定在其支持参考子集中。', 3: '差值为较高病理类别减参考类别。CIF为累积发生率；RMTL为限制平均损失时间；GBC为胆囊癌；LM为landmark；pp为百分点，mo为月，CI为置信区间。PASS为覆盖率≥90%，LIMITED为70%至不足90%，FAIL为<70%、不估计。括号内的破折号表示保留点估计，但有效bootstrap比例<95%，不报告95% CI；单独破折号表示不估计。两种指标的有效bootstrap比例逐行相同，合并报告。', 4: '2年窗口采用与3年窗口相同的LM特异性模型和支持参考子集。CIF为累积发生率；RMTL为限制平均损失时间；GBC为胆囊癌；LM为landmark；pp为百分点，mo为月，CI为置信区间。PASS为覆盖率≥90%，LIMITED为70%至不足90%，FAIL为<70%、不估计。括号内破折号表示保留点估计，但有效bootstrap比例<95%，不报告95% CI；单独破折号表示不估计。两种指标的有效bootstrap比例逐行相同，合并报告。', 5: 'β为死因别log-hazard尺度的回归系数，CI为患者bootstrap 95%置信区间，GBC为胆囊癌。年龄样条各系数须联合解释。参照为女性、T1、N0及G1；s为诊断后已生存年数。Unknown登记状态指示项及预设模型C的landmark交互项使用ridge惩罚θ=1，其余项不惩罚。', '6A': 'GBC为胆囊癌。缩放Schoenfeld得分检验用于描述，不据此重新选择模型；联合项及全局项按原模型诊断报告。s为诊断后已生存年数。', '6B': 'GBC为胆囊癌，CI为置信区间。每次加入一个年龄或T3/4与q(v)=log(max(v,0.25))的交互项；v为距L1（模型A）或距当前landmark（模型B、C）的年数。D=δlog(6)，表示0.5至3年的log-hazard比变化；年龄按每10岁，T3/4参照T1。有效bootstrap比例≥95%且95% CI完全高于log(1.5)或低于−log(1.5)时达到实质性门槛；本表报告估计及区间，不使用布尔标签。', 7: '所有指标括号内为患者bootstrap 95%置信区间。AUC为受试者工作特征曲线下面积；O/E为观察与平均预测风险比；O−E为观察减平均预测风险，pp为百分点；ICI为综合校准指数；LM为landmark，GBC为胆囊癌。Brier等指标使用逆概率删失加权；模型在开发后固定。n为相应LM人群数，Events为窗口内相应死亡事件数。', 8: '差值为首个模型减第二个模型；AUC正值表示首个模型判别较高，Brier负值表示预测误差较低。AUC为受试者工作特征曲线下面积，GBC为胆囊癌，LM为landmark，CI为置信区间。95% CI来自同次患者抽样的配对比较，未作多重比较调整。', 9: '括号为患者bootstrap 95%置信区间。O/E为观察与平均预测风险比，O−E为观察减平均预测风险，pp为百分点；GBC为胆囊癌，LM为landmark。Period为诊断年份组；n为该组相应LM人数，Events为窗口内相应死亡数。', 10: '2012–2014年仅更新死因别基线风险（baseline-hazard updating）；Original与Updated在相同2015–2017年患者中评估，回归系数及其他模型设定不变。括号为患者bootstrap 95%置信区间。AUC为受试者工作特征曲线下面积；O/E为观察与平均预测风险比；O−E为观察减平均预测风险，pp为百分点；ICI为综合校准指数；GBC为胆囊癌，LM为landmark。', 11: '所有差值为Updated减Original。Δ绝对O−E、ΔBrier、ΔICI及Δ绝对(slope−1)为负表示相应误差减小；ΔAUC为正表示判别增加。区间为患者配对bootstrap 95%置信区间，同时包含更新与评估抽样不确定性。AUC为受试者工作特征曲线下面积；O−E为观察减平均预测风险，pp为百分点；ICI为综合校准指数；GBC为胆囊癌，LM为landmark。', 12: '本表为独立定义的全因死亡生命表人群，保留死因未解析病例后限制诊断年龄<90岁；与竞争风险人群不同。RMST为限制平均生存时间，mo为月，LM为landmark。括号为患者bootstrap 95%置信区间；生命表固定。Gap为同一匹配人群的期望减观察RMST。Year+1仅将生命表日历年键后移1年，最后一列为该敏感性差距减主分析差距。', 13: 'CIF为Aalen–Johansen累积发生率，GBC为胆囊癌，LM为landmark，CI为置信区间；各LM为重叠的条件幸存者人群。所有区间均基于1000次有效患者水平bootstrap抽样。', 14: '差值为较高病理类别减参考类别的3年胆囊癌（GBC）累积发生率（CIF）差，pp为百分点，LM为landmark，CI为置信区间。Change from L0为同次患者bootstrap的配对变化及95% CI；L0作为Reference，不另报零差值区间。'}

WIDTHS = {1: [150, 37, 37, 37], 2: [20, 55, 17, 35, 35, 32, 35], 3: [16, 37, 24, 15, 25, 23, 22, 43, 43, 28], 4: [16, 37, 24, 15, 25, 23, 22, 43, 43, 28], 5: [20, 35, 85, 95, 26], '6A': [22, 42, 150, 47], '6B': [20, 35, 80, 30, 61, 35], 7: [27, 14, 17, 19, 19, 30, 30, 30, 31, 32, 30], 8: [32, 34, 19, 25, 99, 26, 26], 9: [17, 30, 15, 33, 20, 20, 41, 41, 39, 42], 10: [26, 15, 27, 14, 17, 18, 27, 27, 27, 29, 30, 27], 11: [17, 28, 17, 43, 43, 40, 40, 42], 12: [18, 23, 29, 45, 45, 45, 28, 28], 13: [22, 27, 42, 35, 135], 14: [25, 60, 22, 77, 77]}


# Historical numbers below are input provenance, never submission output numbers.
# Common-support columns are already present in the 3-year contrast matrix;
# the separate support table is consolidated, not printed a second time.
_MIGRATE = {1: 1, 2: 3, 3: 4, 4: 5, "5A": "6A", "5B": "6B",
            6: 7, 7: 8, 9: 12, 10: 13, 11: 14}
TITLES = {
    1: "Cohort Derivation and Sequential Eligibility Criteria",
    2: "Measured-Covariate-Standardized 3-Year Conditional Prognostic Contrasts and Common Support",
    3: "Two-Year Horizon Sensitivity Analysis of Standardized Conditional Prognostic Contrasts",
    4: "Development-Model Coefficients",
    5: "Proportional-Hazards and Model Diagnostics",
    6: "Temporal Validation Performance",
    7: "Paired Differences Between Conditional Prediction Strategies",
    8: "Performance Before and After Baseline-Hazard Updating",
    9: "Expected Restricted Survival and General-Population Survival Deficit",
    10: "Conditional Cumulative Incidence at 1-, 2-, and 3-Year Horizons",
    11: "Crude Pathologic Prognostic Contrasts Across Landmarks",
}

def matrices(aggregates):
    """Format frozen summary matrices into the 11 final submission eTables."""
    old = _legacy_matrices(aggregates)
    out = {k: copy.deepcopy(old[v]) for k, v in _MIGRATE.items()}
    out[1][3][0] = "腺癌未另行说明型（8140/3）"
    # Preserve support/reportability cells already carried by the contrast rows.
    support = {(r[0], r[2]): r for r in old[2][1:]}
    if len(support) != len(old[2]) - 1:
        raise ValueError("Duplicate frozen common-support keys")
    for row in out[2][1:]:
        s = support[(row[0], row[3])]
        if row[4:7] != [s[6], s[4], s[5]]:
            raise ValueError("Frozen contrast and support tables disagree")
    out["8A"] = [["Cause", "LM", "Model", "Original O/E (95% CI)",
                  "Updated O/E (95% CI)", "Δ|O−E|, pp (95% CI)"]]
    out["8B"] = [["Cause", "LM", "Model", "Original Brier (95% CI)",
                  "Updated Brier (95% CI)", "ΔBrier (95% CI)", "ΔAUC (95% CI)"]]
    indexed = {(r[0], r[1], r[2], r[3]): r for r in old[10][1:]}
    if len(indexed) != len(old[10]) - 1:
        raise ValueError("Duplicate frozen updating state keys")
    seen = set()
    for change in old[11][1:]:
        model, cause, lm = change[:3]
        key = (model, cause, lm)
        if key in seen:
            raise ValueError("Duplicate frozen paired updating key")
        seen.add(key)
        original = indexed[("Original", model, cause, lm)]
        updated = indexed[("Updated", model, cause, lm)]
        out["8A"].append([cause, lm, model, original[8], updated[8], change[3]])
        out["8B"].append([cause, lm, model, original[7], updated[7], change[4], change[5]])
    if len(indexed) != 2 * len(seen):
        raise ValueError("Unmatched frozen updating states")
    return out

_OLD_NOTES, _OLD_WIDTHS = NOTES, WIDTHS
NOTES = {k: _OLD_NOTES[v] for k, v in _MIGRATE.items()}
WIDTHS = {k: _OLD_WIDTHS[v] for k, v in _MIGRATE.items()}
NOTES[1] = NOTES[1].replace("一致性及敏感性描述", "跨系统一致性描述")
NOTES[2] += "共同支持要求每个性别×其余两项病理类别分层内，两种目标类别各≥5名独立患者，并限制至年龄重叠范围。跨landmark配对变化由同次源患者重抽样差值直接计算，各landmark使用各自支持参考子集。"
NOTES[4] = NOTES[4].replace("预设模型C", "模型C")
NOTES["8A"] = "2012–2014年仅更新死因别基线风险；原始与更新后模型在相同2015–2017年患者中评估。GBC为胆囊癌，LM为landmark，O/E为观察与平均预测风险比，pp为百分点，CI为置信区间。Δ|O−E|为更新后减原始的绝对风险误差，负值表示误差减小。配对95% CI同时包含更新和评估人群的患者抽样不确定性。"
NOTES["8B"] = "AUC为受试者工作特征曲线下面积，GBC为胆囊癌，LM为landmark，CI为置信区间。差值均为更新后减原始；ΔBrier负值表示预测误差减小，ΔAUC正值表示判别增加。区间来自配对患者bootstrap，同时纳入更新与评估抽样不确定性。"
WIDTHS["8A"] = [28, 15, 20, 64, 64, 70]
WIDTHS["8B"] = [27, 14, 18, 48, 48, 53, 53]
del _OLD_NOTES, _OLD_WIDTHS

def main():
    """Output assembly only: no patient input, estimators or model imports."""
    import argparse
    import csv
    import json
    from pathlib import Path
    parser = argparse.ArgumentParser(description="Assemble Table 1 and eTables 1–11 from frozen summary inputs.")
    parser.add_argument("--aggregates", required=True, type=Path,
                        help="Private frozen aggregate JSON with supp_tables and table1 matrices")
    parser.add_argument("--output", required=True, type=Path,
                        help="Private submission output directory; do not commit generated files")
    args = parser.parse_args()
    aggregates = json.loads(args.aggregates.read_text(encoding="utf-8-sig"))
    tables = matrices(aggregates)
    table1 = copy.deepcopy(aggregates["table1"])
    if not table1 or len(table1[0]) != 7 or any(len(r) != 7 for r in table1):
        raise ValueError("Frozen Table 1 must have characteristic plus six landmark columns")
    # Section headings are not missing observations; show blank numeric cells.
    for i in (2, 5, 12, 17, 21):
        if any(value not in ("", "NA", None) for value in table1[i][1:]):
            raise ValueError("Unexpected values in a frozen Table 1 section heading")
        table1[i][1:] = [""] * 6
    expected = {1, 2, 3, 4, "5A", "5B", 6, 7, "8A", "8B", 9, 10, 11}
    if set(tables) != expected:
        raise ValueError("Unexpected final submission table mapping")
    # Validate every matrix before creating output files.
    for rows in [table1, *tables.values()]:
        if not rows or any(not isinstance(r, list) or len(r) != len(rows[0]) for r in rows):
            raise ValueError("Nonrectangular frozen summary matrix")
    sections = {"5A": "Panel A. Scaled Schoenfeld Diagnostics",
                "5B": "Panel B. Proportional-Hazards Materiality Probes",
                "8A": "Panel A. Calibration",
                "8B": "Panel B. Prediction Error and Discrimination"}
    def save(path, rows):
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8-sig", newline="") as handle:
            csv.writer(handle).writerows(rows)
    table1_notes = [
        "L0 is diagnosis; L1–L5 condition on survival for 1–5 years since diagnosis. Columns contain overlapping survivor populations; no independent-group tests are performed. Categorical data are No. (%); Unknown registry states are retained.",
        "Age at diagnosis is reported as median (IQR), in years.",
        "Race and ethnicity use the SEER Race and Origin Recode. The six observed categories retain registry terminology and are not described as self-reported.",
    ]
    save(args.output / "Main" / "Table1.csv", table1 + [[note] + [""] * 6 for note in table1_notes])
    for number in range(1, 12):
        keys = [f"{number}A", f"{number}B"] if number in (5, 8) else [number]
        width = max(len(tables[key][0]) for key in keys)
        rows = [[f"eTable {number}. {TITLES[number]}"]]
        for key in keys:
            if key in sections:
                rows.append([sections[key]])
            rows.extend(tables[key])
            rows.extend([[NOTES[key]], []])
        save(args.output / "Supplement" / f"eTable{number}.csv",
             [row + [""] * (width - len(row)) for row in rows])
    print("Completed Table 1 + eTables 1–11; frozen summary assembly only.")

if __name__ == "__main__":
    main()
