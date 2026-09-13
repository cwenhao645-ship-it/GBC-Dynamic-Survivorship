"""Final Table 1 demographic formatting from validated private landmark records."""
N=[3918,2496,1786,1423,1192,1047]
RACES=[('Hispanic','Hispanic (All Races)'),('NHAIAN','Non-Hispanic American Indian/Alaska Native'),('NHAPI','Non-Hispanic Asian or Pacific Islander'),('NHB','Non-Hispanic Black'),('Unknown','Non-Hispanic Unknown Race'),('NHW','Non-Hispanic White')]

def build_table1(landmarks):
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
    
    return table, section_rows

