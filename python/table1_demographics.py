"""Final Table 1 demographic formatting from validated private landmark records."""
N=[3918,2496,1786,1423,1192,1047]
RACES=[('Hispanic','Hispanic (All Races)'),('NHAIAN','Non-Hispanic American Indian/Alaska Native'),('NHAPI','Non-Hispanic Asian or Pacific Islander'),('NHB','Non-Hispanic Black'),('Unknown','Non-Hispanic Unknown Race'),('NHW','Non-Hispanic White')]

def build_table1(landmarks, surgery_summary=None):
    l = landmarks.copy()
    assert l.groupby('landmark_year').size().tolist() == N
    assert not l.duplicated(['patient_id', 'landmark_year']).any()
    l['T_submit']=l.T_model.replace({'Unknown/nonstandard':'Unknown','Unknown / nonstandard':'Unknown','T0/nonstandard':'Unknown'})
    groups=[l[l.landmark_year==s] for s in range(6)]
    def count(var,key):
        return [f'{int((g[var]==key).sum())} ({100*(g[var]==key).mean():.1f})' for g in groups]
    table=[['Characteristic']+[f'L{s}, n = {n}' for s,n in enumerate(N)]]
    table.append(['Age at diagnosis, median (IQR), y']+[f'{g.age_dx.median():.1f} ({g.age_dx.quantile(.25):.1f}–{g.age_dx.quantile(.75):.1f})' for g in groups])
    blocks=[('Sex, No. (%)','sex',[('Female','Female'),('Male','Male')]),('Race and ethnicity, No. (%)','race_ethnicity',RACES),('T category, No. (%)','T_submit',[(v,v) for v in ['T1','T2','T3/4','Unknown']]),('N category, No. (%)','N_model',[(v,v) for v in ['N0','N+','Unknown']]),('Histologic grade, No. (%)','grade_model',[(v,v) for v in ['G1','G2','G3/4','Unknown']])]
    section_rows=[]
    for title,var,levels in blocks:
        section_rows.append(len(table)); table.append([title]+['']*6)
        for key,label in levels: table.append([label]+count(var,key))
        assert all(sum(int((g[var]==key).sum()) for key,label in levels)==len(g) for g in groups)
    if surgery_summary is not None:
        partition = surgery_partition([len(g) for g in groups], surgery_summary)
        section_rows.append(len(table))
        table.append(['Recorded surgical extent, No. (%)'] + [''] * 6)
        labels = [
            ('30/40', 'Code 30/40 (simple/partial or total primary-site resection)'),
            ('60', 'Code 60 (extended/radical registration category)'),
        ]
        for group, label in labels:
            table.append([label] + [
                f"{r['n']:,} ({r['percentage']:.1f})"
                for r in partition if r['surgery_group'] == group
            ])

    return table, section_rows


def surgery_partition(landmark_counts, surgery_summary):
    """Read the frozen Dynamic LANDMARK_ESTIMATE partition, never refit it.

    Labels are the exact two groups in phase3_minimal/surgery_audit.py.
    No individual surgery code is mapped here; Unknown is not imputed.
    """
    import math

    records = (surgery_summary.to_dict(orient='records')
               if hasattr(surgery_summary, 'to_dict') else list(surgery_summary))
    selected = [r for r in records
                if r.get('row_type') == 'LANDMARK_ESTIMATE'
                and r.get('cohort') == 'Dynamic']
    if len(selected) != 12:
        raise ValueError('STOP: exactly 12 frozen Dynamic LANDMARK_ESTIMATE rows are required')
    counts = list(landmark_counts)
    if counts != N:
        raise ValueError('STOP: Table1 landmark denominators differ from the frozen dynamic cohort')
    indexed = {}
    for row in selected:
        group = str(row.get('surgery_group'))
        if group not in ('30/40', '60'):
            raise ValueError('STOP: unexpected or Unknown frozen surgery group; no recoding permitted')
        try:
            landmark = float(row['landmark'])
            n = float(row['n'])
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError('STOP: invalid frozen surgery landmark/count') from exc
        if (not math.isfinite(landmark) or not landmark.is_integer()
                or int(landmark) not in range(6) or not math.isfinite(n)
                or not n.is_integer() or n < 0):
            raise ValueError('STOP: surgery landmarks/counts must be finite valid integers')
        key = (int(landmark), group)
        if key in indexed:
            raise ValueError('STOP: duplicated frozen landmark/surgery group')
        indexed[key] = int(n)
    output = []
    for landmark, denominator in enumerate(counts):
        if sum(indexed.get((landmark, group), -1) for group in ('30/40', '60')) != denominator:
            raise ValueError(f'STOP: surgery groups do not partition the L{landmark} denominator')
        for group in ('30/40', '60'):
            n = indexed[(landmark, group)]
            output.append(dict(landmark=landmark, surgery_group=group, n=n,
                               denominator=denominator, percentage=100 * n / denominator))
    return output

