# Derived-variable dictionary
No patient example rows are supplied. Identifiers are private linkage keys only and are never predictors.

| Variable | Type | Definition/coding | Unknown handling | Analysis role |
|---|---|---|---|---|
| year_dx | integer | Diagnosis year, 2004–2023 | Invalid year fails eligibility | Era definition; centered year in standardization |
| age_dx | numeric | Single diagnosis age; 90+ top-coded at 90 | Not imputed | Prediction/standardization |
| age_90plus_flag | logical | Original 90+ category | No midpoint invented | Exclude from life-table benchmark only |
| sex | category | SEER registry Sex variable; female and male (stored as Female/Male) | Unrecognized codes audited | Predictor; life-table matching |
| race_ethnicity | category | Hispanic, NHW, NHB, NHAIAN, NHAPI, Unknown | Preserve Unknown | Table 1; not forced into prediction models |
| T_model / T_core (T_group) | category | T1, T2, T3/4, Unknown | T0/nonstandard retained as Unknown/nonstandard, folded into Unknown for modeling | Pathology predictor |
| N_model (N_group) | category | N0, N+ (N1/N2/N3), Unknown | Explicit indicator | Predictor |
| grade_model (grade_group) | category | G1, G2, G3/4, Unknown | Explicit indicator; no complete-case deletion | Predictor |
| M_harmonized | category | M0/M1/Unknown from year-specific source | Only explicit M0 eligible | Eligibility |
| summary_stage_harmonized | category | Localized, Regional, Distant, Unknown | Unknown retained among explicit M0 in final source | Concordance/sensitivity descriptor |
| survival_days_numeric | numeric | Original numeric Survival Days | Missing/negative excluded by frozen rule | Eligibility/time QA |
| survival_days_analysis | numeric | Same time; original 0 days corrected to 0.5 days | No months replacement | Event/censoring time from diagnosis |
| vital_raw / event_os | category/integer | Alive→0, Dead→1 | Unknown status not assumed alive | All-cause event; reverse-KM inversion |
| event_competing | integer | 0 censored/alive; 1 GBC death; 2 other-cause death | Unknown COD not coded as other-cause death | Competing risks |
| unknown_cod_flag | logical | SEER unresolved death classification | Excluded from CR; retained in eligible all-cause benchmark | Population distinction |
| descriptive_source_flag | logical | Fixed 2004–2015 dynamic source membership | No outcome-based selection | 3918 cohort |
| landmark_year | integer | L0–L5 descriptive; L1–L3 prediction | Not imputed | Survivor condition |
| time_from_landmark | numeric days | survival_days_analysis − 365.25×landmark | Strictly positive eligibility | Future window |
| time_to_analysis_end | numeric days | min(future time,1095.75) | Right-censored window | Future event analysis |
| event_within_window | integer | Original CR event if future time≤1095.75; otherwise0 | Early censor remains0 | Fixed 3-year estimand |
| analysis_role | category | DESCRIPTIVE or PREDICTION_PREP | Roles not pooled | Distinguish overlapping long records |
| Age_linear, Age_rcs1, Age_rcs2 | numeric | Four-knot age RCS, centered at age70 and divided by10 | No knots re-estimated in validation | A/B/C |
| Male,T2,T34,Nplus,G2,G34 | binary | Indicators relative to Female,T1,N0,G1 | Unknown has separate indicators | A/B/C |
| T_unknown,N_unknown,G_unknown | binary | Unknown registration states | Ridge theta=1 | A/B/C |
| *_by_s | numeric | Specified interactions with s−2 | Definitions frozen | C only |

The six-category race display preserves the SEER export terminology; it is not claimed to be patient self-report. Diagnosis, not surgery, is the time origin.


Sex is a registry variable; the analysis data do not separately provide gender identity. The eligible histology is gallbladder adenocarcinoma, NOS (ICD-O-3 morphology code 8140/3), not all adenocarcinoma subtypes.
