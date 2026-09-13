# Reproducibility limitations and execution gates

## What is preserved
The repository contains the existing mathematical implementations, not rewritten estimators. Public changes are file organization, path configuration, comment cleanup, source-safe defaults and publication input parameterization. Main outcome analysis, model fitting and formal bootstraps were not run while preparing this copy. Patient data, models and results are not bundled.

## Gates before claiming end-to-end analysis reproduction
1. **Workbook backend:** model exporters depend on @oai/artifact-tool; the observed package is marked private. A public supported replacement or lawful redistributable dependency must be provided and tested at the I/O layer without changing numerical results. A package list alone does not resolve this.
2. **Aggregation provenance:** the project contains FINAL_RESULTS_MASTER.xlsx and the frozen predecessor summary matrices, but a complete independent generator for that exact current master/14-table input was not found. The historical table script generates a different set and is excluded. publication_tables.matrices() now assembles the final 11 eTables, and its CLI copies the frozen Table 1 matrix, but it cannot reconstruct missing source aggregates.
3. **Relocation and provenance locks:** original hash checks are intentionally retained. Public path/comment changes change the library-byte hashes used by downstream modules; report/SAP/private derived hashes also refer to the original delivery. These guards will stop a relocated run until an author-reviewed replacement provenance manifest is defined. No assertion has been removed or hash silently recomputed to force a pass.
4. **No end-to-end rerun validation:** formal reruns were outside closeout scope. Static parsing and mathematical-source comparisons establish source integrity, not independent execution success.

These limit an end-to-end reproducibility claim; they do not prevent inspecting or manually uploading a code-only repository that states these limitations.

## Required private layout
A private working copy must contain its corresponding R code paths and the original expected input/output layout. Set GBC_FINAL_RUN_ROOT to that working copy and GBC_CODE_ROOT to the code root; keep both out of public logs. Preparation code uses GBC_PREPARATION_ROOT and GBC_SEER_MAPPING. The latter points to a private copy of seer_mapping.example.yml with authorized paths, verified export fingerprints and schema. Do not upload this private configuration.

The locked R readers expect data/analysis_patient_level_v2.parquet and analysis_landmark_long_v2.parquet; outputs/DEVELOPMENT_MODELS.rds and prior aggregate workbooks/reports; spec/SAP_TECHNICAL_ADDENDUM_v1.1.md; private/preparation/outputs/STAGE1_ANALYSIS_REPORT.md and private/preparation/data_clean/01_gallbladder_harmonized_all_2004_2023.parquet. Life-table TXT/DIC belong under data_external/. Figure readers require the named private result workbooks including the master.

Preparation build_cohort() retains a comparison against data_clean/02_strict_main_candidate_2004_2023.parquet. This predecessor is an audit dependency, not the final inclusion rule. Its original source is not substituted silently; resolving or replacing that historical audit is part of the provenance gate.

## Exclusions
No raw/derived patient tables, identifier values, models, bootstrap objects, reports with local runtime paths, manuscript/Supplement/STROBE documents, figure files, screenshots, prompt histories, logs, credentials or aggregate workbooks are distributed. Generated figures and tables require an independent confidentiality review before future publication. Citation author names are retained; private contact details are not included.

## Restore instructions
Consult environment/README.md. Install the recorded R4.4.3 versions and independently authorized data using supported distribution channels. Do not infer a successful environment restore from current sessionInfo. No renv.lock was invented. Resolve all gates above before claiming this repository reproduces every submission output.

## Run safety
Model-library autorun defaults are FALSE in public copies. Follow-up and figure files still execute when explicitly sourced. The default submission figure workflow now reads only frozen summary workbooks and the existing group-level Figure 3 CSV. The table CLI reads only frozen summary matrices. Neither invokes the original subgroup CIF calculation, model fitting, bootstraps, cohort harmonization or patient-level table summaries. There is no automated full-analysis launcher.
