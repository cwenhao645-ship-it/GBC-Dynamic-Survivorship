# Derived-variable dictionary
No patient example rows are supplied. Identifiers are private linkage keys only and are never predictors.

| Variable | Type | Definition/coding | Unknown handling | Analysis role |
|---|---|---|---|---|
| year_dx | integer | Diagnosis year, 2004–2023 | Invalid year fails eligibility | Fixed cohort era; centered-year adjustment is historical only |
| age_dx | numeric | Single diagnosis age; 90+ top-coded at 90 | Not imputed; topcode is a proxy | Current attained-age proxy, linear and quadratic terms |
| age_90plus_flag | logical | Original 90+ category | No midpoint invented | Exclude from life-table benchmark only |
| sex | category | SEER registry Sex variable; female and male (stored as Female/Male) | Unrecognized codes audited | Age/sex adjustment; life-table matching |
| race_ethnicity | category | Hispanic, NHW, NHB, NHAIAN, NHAPI, Unknown | Preserve Unknown | Table 1; not forced into prediction models |
| T_model / T_core (T_group) | category | T1, T2, T3/4, Unknown | T0/nonstandard retained as Unknown/nonstandard, folded into Unknown for modeling | Pathology predictor |
| N_model (N_group) | category | N0, N+ (N1/N2/N3), Unknown | Other levels are not forced into the binary fit; eligible reference patients may retain them | Current N+ vs N0 contrast |
| grade_model (grade_group) | category | G1, G2, G3/4, Unknown | Other levels are not forced into the binary fit; eligible reference patients may retain them | Current G3/4 vs G1 contrast |
| M_harmonized | category | M0/M1/Unknown from year-specific source | Only explicit M0 eligible | Eligibility |
| summary_stage_harmonized | category | Localized, Regional, Distant, Unknown | Unknown retained among explicit M0 in final source | Concordance/sensitivity descriptor |
| survival_days_numeric | numeric | Original numeric Survival Days | Missing/negative excluded by frozen rule | Eligibility/time QA |
| survival_days_analysis | numeric | Same time; original 0 days corrected to 0.5 days | No months replacement | Event/censoring time from diagnosis |
| vital_raw / event_os | category/integer | Alive→0, Dead→1 | Unknown status not assumed alive | All-cause event; reverse-KM inversion |
| event_competing | integer | 0 censored/alive; 1 GBC death; 2 other-cause death | Unknown COD not coded as other-cause death | Competing risks |
| unknown_cod_flag | logical | SEER unresolved death classification | Excluded from CR; retained in eligible all-cause benchmark | Population distinction |
| descriptive_source_flag | logical | Fixed 2004–2015 dynamic source membership | No outcome-based selection | 3918 cohort |
| landmark_year | integer | L0–L5 current descriptive analysis; historical prediction roles remain in source files | Not imputed | Survivor condition; never pool roles |
| time_from_landmark | numeric days | survival_days_analysis − 365.25×landmark | Strictly positive eligibility | Future window |
| time_to_analysis_end | numeric days | min(future time,1095.75) | Right-censored window | Future event analysis |
| event_within_window | integer | Original CR event if future time≤1095.75; otherwise0 | Early censor remains0 | Fixed 3-year estimand |
| analysis_role | category | DESCRIPTIVE or PREDICTION_PREP | Roles not pooled | Distinguish overlapping long records |
| age_attained / Age10 | numeric | age_dx + landmark; Age10=(age_attained−70)/10 | Recorded age, not birthday-exact age | Current quadratic age adjustment |
| Age10_squared | numeric | Age10 squared | No imputation or coefficient freezing across bootstrap | Current age adjustment |
| High / Male | binary | Target high versus reference pathology group; Male versus Female | Original two-arm fitting and sex-specific age support | Current cause-specific models |
| copy_id / period | internal integer | Bootstrap-copy identity and (0,12],(12,24],(24,36] follow-up segment | One terminal event per copy, not per split row | L0 PH sensitivity only; never a predictor ID |

## Retired model-only fields

Age_linear/Age_rcs1/Age_rcs2 (four-knot age RCS), T_unknown/N_unknown/G_unknown ridge indicators and *_by_s interactions belong to historical Model A/B/C under legacy/. They are not the current age/sex-only pathology model. Older configuration temporal-role fields are retained for preparation compatibility, not as current manuscript analyses.

The six-category race display preserves the SEER export terminology; it is not claimed to be patient self-report. Diagnosis, not surgery, is the time origin.


Sex is a registry variable; the analysis data do not separately provide gender identity. The eligible histology is gallbladder adenocarcinoma, NOS (ICD-O-3 morphology code 8140/3), not all adenocarcinoma subtypes.
