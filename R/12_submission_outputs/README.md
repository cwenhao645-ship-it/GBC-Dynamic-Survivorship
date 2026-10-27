# Current submission display mapping

This directory documents output provenance; it is not a one-click manuscript builder. No manuscript or aggregate workbook is bundled. The code update targets BMC Gastroenterology, not the historical JNO display set. The author-supplied October 27, 2026 near-submission ZIP was inspected in memory: Main_Manuscript_BMC_Gastroenterology.docx, the 14-page Additional_file_1_Supplementary_Information.pdf and Figure_1–3.pdf. These establish the titles/order below. No archive extraction, manuscript alteration, full numerical rerun or layout certification is implied.

## Main displays

| Current item | Available code/input | Verification boundary |
|---|---|---|
| Table 1. Demographic, pathology and registered surgery characteristics across landmarks | python/table1_demographics.py: build_table1; authorized private landmark records; Phase 3 Surgery_Code_Audit | Age, sex, race/ethnicity, T, N, grade and registered 30/40-versus-60 surgery. Existing formatter supplies the demographic/pathology blocks only; surgery rows require the actual aggregate audit source |
| Figure 1. Cohort derivation and analysis timeline | Supplied Figure_1.pdf and main legend; cohort derivation/risk-set summaries | Updated diagnosis-origin source/dynamic/life-table populations confirmed. Matching plotting source remains unresolved; the historical legacy model-development tracks are not the current artwork |
| Figure 2. Conditional mortality, time lost and population-referenced restricted survival | R/10_figures/figure2.R; FINAL_RESULTS_MASTER.xlsx plus frozen Stage 1/life-table fallbacks | Scientific panels confirmed: a CIF, b cause-specific RMTL, c observed/expected RMST, d other-minus-GBC CIF by horizon. Public re-export is not pixel-certified |
| Figure 3. Crude and age–sex-adjusted pathologic risk differences | R/10_figures/current_figure3.R; Adjusted_Pathology sheet of phase3_results.xlsx | Confirmed T3/4 vs T1, N+ vs N0 and G3/4 vs G1 crude/adjusted 36-month RD with 95% CI. Public PDF adapter is not the private typesetting/QA backend |

Figure 2's point-estimate fallbacks do not remove its required master-workbook CI input. Figure 3's plotting helper requires 18 aggregate rows, three contrasts × L0–L5, with corresponding crude/adjusted points and confidence intervals. It does not fit the models itself.

## Supplementary Tables S1–S9

The supplied 14-page supplement confirms all nine table assignments. Pages below are PDF page positions, not a regenerated publication layout.

| Item and confirmed title | PDF pages | Actual analysis/result source |
|---|---|---|
| S1. Cohort derivation and sequential eligibility criteria | 3 | Original harmonization/build_cohort and frozen sequential eligibility counts |
| S2. Population-referenced restricted survival | 4 | Original life-table matching and LIFETABLE_RESULTS.xlsx; observed/expected RMST, deficit and year-plus-one reference |
| S3. Conditional cumulative incidence by horizon | 5–6 | Stage 1 AJ_CIF/Bootstrap_CI summaries for 1-, 2- and 3-year horizons |
| S4. Crude pathologic contrasts across landmarks | 7 | Stage 1 crude T/N/grade risk differences and paired change-from-L0 summaries |
| S5. Summary Stage sensitivity analysis | 8–9 | gbc_transfer_gate/phase2/run_phase2.py and phase2_lifetable.R; CIF/difference, RMTL and separate-life-cohort deficit panels |
| S6. Age- and sex-adjusted three-year GBC risk differences | 10 | phase3_minimal/run_phase3.R; Adjusted_Pathology, including crude/adjusted contrasts, group/event/reference counts and valid bootstrap counts |
| S7. Shared-patient cohort restricted-time decomposition | 11 | phase3_minimal/unified_cohort.R; Unified_Cohort, actual intersection L0 n=3,736 and L5 n=1,035 |
| S8. Registered surgical-extent groups (descriptive only) | 12–13 | phase3_minimal/surgery_audit.py; Surgery_Code_Audit, 30/40 versus 60 counts/events/CIF/RMTL and sparse-caution flags |
| S9. L0 proportional-hazards model sensitivity | 14 | phase3_l0_ph_check: PH, PATH_TV (table label Pathology TV), AGE_TV (Pathology + age TV), paired model changes, selected GBC PH tests and interpretation |

S9 contains nine actual model/contrast rows, all with 1,000 valid patient-bootstrap replicates. PATH_TV L0 RDs for T, N and grade are 44.00, 20.22 and 31.32 pp; the exploratory AGE_TV values are 44.15, 20.18 and 31.46 pp. These are checked publication summaries, not hardcoded substitutes for calculation. The main manuscript places the model-setting sensitivity in Statistical analysis and reproducibility, reports PATH_TV values in Pathology contrasts and sensitivity analyses, and discusses the limited non-equivalence interpretation. Full diagnostic plots in Author_Review are not extra main figures.

No current S1–S9 publication-document assembler has been independently verified. This confirmed map does not claim that the old 14-matrix/11-eTable assembler produces the current supplement or that private workbook/figure cosmetics are publicly reproducible. The manuscript availability paragraph still says revised Phase 3 code is not yet integrated into GitHub; after the public update is remotely verified, the author must manually reconcile that sentence. The archive and submission documents are not modified here.

## Legacy exclusion

The old eTables 1–11, eFigures 1–2, old Figure 3 complex-support display, Model A/B/C, validation and baseline updating are not the current submission mapping. Their sources are retained under legacy/ for provenance and are not default exports. The supplied near-submission package confirms current scientific numbering; final author approval, any later manuscript revision, missing Figure 1 source, the Table 1 surgery-row delivery gap and exact publication-output assembly remain separate checks.
