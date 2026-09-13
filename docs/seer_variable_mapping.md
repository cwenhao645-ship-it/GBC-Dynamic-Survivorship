# SEER source-variable mapping
The full label-to-code mapping is in config/seer_mapping.example.yml. Example file paths/hashes must be supplied privately. Source fields are not reinterpreted using outcomes.

| Concept | SEER source variable | Diagnosis years | Source coding | Derived coding and handling |
|---|---|---|---|---|
| Diagnosis year | Year of diagnosis | 2004–2023 | Numeric year | year_dx; fixed era flags |
| Age | Age recode with single ages and 90+ | All | Single-age labels, 90+ years | Numeric age; retain top-code flag |
| Sex | SEER registry Sex variable | All | Female/Male | Reported as female and male; gender identity is not separately available |
| Race/ethnicity | Race and origin recode (NHW, NHB, NHAIAN, NHAPI, Hispanic) | All | Six observed SEER categories | NHW/NHB/NHAIAN/NHAPI/Hispanic/Unknown; display source names |
| Site | Primary Site | All | 239/C239/C23.9 | Malignant gallbladder flag |
| Histology | Histologic Type ICD-O-3; Behavior code ICD-O-3 | All | 8140 and malignant /3 | Gallbladder adenocarcinoma, NOS (ICD-O-3 morphology code 8140/3) |
| Confirmation | Diagnostic Confirmation | All | Positive histology | Required |
| Primary eligibility | Primary by international rules | All | Yes | Required; not equated to first primary only |
| Resection | RX Summ--Surg Prim Site (1998-2022) | 2004–2022 | 30,40,60 | Simple/partial,total,radical/en-bloc; strict eligible set |
| Resection | RX Summ--Surg Prim Site 2023 (2023+) | 2023 | A300,A400,A600 | Same categories; no inclusion of local excision/destruction/NOS |
| T,N,M | Derived AJCC T/N/M, 6th ed (2004-2015) | 2004–2009 | Prefixed/substage labels | Parse prespecified valid suffixes; no fallback to another era |
| T,N,M | Derived AJCC T/N/M, 7th ed (2010-2015) | 2010–2015 | Prefixed/substage labels | T1/T2/T3/T4; N0/N1/N2/N3; explicit M0/M1 |
| T,N,M | Derived SEER Combined T/N/M (2016-2017) | 2016–2017 | Combined labels | Same derived categories |
| T,N,M | Derived EOD 2018 T/N/M Recode (2018+) | 2018–2023 | EOD recode | Same categories; not AJCC restaging |
| Summary Stage | Combined Summary Stage with Expanded Regional Codes (2004+) | All | Localized; regional direct/nodes/both; distant; unknown | Regional collapsed; descriptor, not an extra final M0 exclusion |
| Grade | Grade Recode (thru 2017) | 2004–2017 | I,II,III,IV/unknown labels | G1,G2,G3/4,Unknown |
| Grade | Derived Summary Grade 2018 (2018+) | 2018–2023 | Site-specific/summary grade labels | G1,G2,G3/4,Unknown; structurally absent not imputed |
| All-cause status | Vital status recode (study cutoff used) | All | Alive/Dead | event_os=0/1 |
| GBC death | SEER cause-specific death classification | All | Dead attributable to this cancer dx | event_competing=1 only when vital and other-COD fields agree |
| Other death | SEER other cause of death classification | All | Dead attributable to causes other than this cancer dx | event_competing=2 only with concordant fields |
| Unresolved death | Both death-classification fields | All | Dead (missing/unknown COD) | Missing CR event, not other-cause; all-cause death retained |
| Time | Survival Days | All | Numeric days | 0→0.5; missing/negative ineligible; never use Survival months as replacement |

T subcategories are collapsed to T1/T2/T3/4. T0 is retained as an unknown/nonstandard registration category; it is not recoded into a known T category. Unknown N and grade remain explicit model terms. The current cohort uses explicit M0 independently of Summary Stage. The retained historical comparison audit in build_cohort() verifies overlap with a restricted predecessor file; it does not impose that predecessor's filter.

Life-table keys use sex, attained single-year age and calendar year, with the exact-year integration in lifetable_rmst_gap.R. The observed export uses annual conditional survivors per1,000,000; divide by1,000,000 to obtain p, with q=1−p. The script verifies that Unknown and Other unspecified rows agree before using this export's all-races series. This equivalence is checked, not assumed for arbitrary exports.
