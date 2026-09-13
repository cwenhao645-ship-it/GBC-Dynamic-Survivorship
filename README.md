# Conditional Mortality and Survival Gap in Resected Nonmetastatic Gallbladder Adenocarcinoma

## Overview
Source code for a population-based study of changing mortality burden among survivors of resected, explicitly M0 gallbladder adenocarcinoma, NOS (ICD-O-3 morphology code 8140/3).

This code-only repository is prepared for manual upload. It has not been uploaded by this workflow. The final output mapping is synchronized; an independently executable end-to-end analysis is not certified. Known environment, aggregate-input and provenance limitations are documented in docs/reproducibility_notes.md.

## Repository Scope
This repository contains analysis code only. No patient-level SEER data are included. No result workbooks, fitted models, manuscript documents, or source-data tables are distributed. File names retained inside readers identify required private inputs, not files included in the repository.

## Data Availability
SEER Research Data cannot be redistributed by the authors. Eligible investigators must obtain independent access from NCI SEER and comply with the applicable agreement: https://seer.cancer.gov/data/access.html. The MIT license applies to code only.

## Required External Data
1. Authorized SEER Research Data: the study used the 17 Registries November 2025 submission, diagnoses through 2023, with a labels-format CSV and matching dictionary.
2. SEER Expected Survival Life Tables, exported with the documented schema: https://seer.cancer.gov/expsurvival/.
3. Private derived inputs and aggregate intermediates listed in docs/reproducibility_notes.md. Their absence is not bypassed by substituting sample data.

## Software
R version 4.4.3. Original cohort/Aalen–Johansen code also uses Python 3.12.14; model readers used a separate Python runtime. See environment/ for measured versions and provenance. Some original Excel exporters require a private Node package; no public install route has been verified. No automatic package upgrades are part of model development.

## Default Submission Workflow
The default output-only workflow reads existing frozen summary inputs. It does not fit models, bootstrap, harmonize cohorts, or calculate CIF, RMTL or RMST. Run from the repository root after setting private paths:

```r
Sys.setenv(GBC_CODE_ROOT = normalizePath("."),
           GBC_FINAL_RUN_ROOT = "/path/to/private/frozen-results",
           GBC_SUBMISSION_OUTPUT = "/path/to/private/submission",
           GBC_FIGURE_SET = "submission")
source("R/10_figures/final_figures.R")
```

```sh
python python/publication_tables.py --aggregates /path/to/private/aggregates.json --output /path/to/private/submission
```

These two commands export only Table 1, Figures 1–3, eTables 1–11 and eFigures 1–2. PDF/TIFF/preview files are alternate formats of the same figure, not extra displays. The table command copies the frozen Table 1 matrix; it does not run the patient-level demographic formatter. See R/12_submission_outputs/README.md for the input contract and numbering map. Missing aggregate inputs stop the workflow; they are not replaced by patient-level estimation.

For source-code inspection or a separately planned full analysis reproduction, see docs/analysis_workflow.md. Analysis modules are not invoked by the submission workflow and require independently authorized data, a validated environment and the documented provenance gates. Do not run analysis entry points merely to inspect code.

## Analysis Populations
- 7007 competing-risk source cohort, 2004–2023.
- 3918 dynamic survivorship cohort, 2004–2015.
- Development: 2004–2011; temporal validation: 2012–2017.
- Baseline-hazard update: 2012–2014; updating evaluation period: 2015–2017.
- Separate age <90 life-table benchmark cohort: 3796 at diagnosis, retaining unresolved cause of death where all-cause status is known.

Summary Stage is a cross-system concordance field, not an additional eligibility filter for the final explicit-M0 source cohort. Earlier strict-cohort definitions must not replace this final definition. Histology is adenocarcinoma, NOS (8140/3), not every special adenocarcinoma subtype.

## Outputs
The final manuscript has Table 1 and Figures 1–3 (4 main display items). The supplement has 11 eTables and 2 eFigures. Its tables cover cohort derivation; standardized 3-year contrasts with common support; 2-year sensitivity; model coefficients; proportional-hazards diagnostics; temporal validation; paired strategy comparisons; performance before and after baseline-hazard updating; population restricted-survival deficit; multi-horizon cumulative incidence; and crude pathology contrasts. eFigure 1 shows standardized pathologic contrasts and common support; eFigure 2 shows temporal prediction and baseline-hazard updating.

The plotting exports and table assembly use this final numbering. Standardization support is consolidated with the 3-year contrasts; updating states and paired changes are combined into one two-panel table. The supplementary updating figure retains its original scientific content. Historical diagnostic material outside this submission is not part of the default output workflow. Statistical implementations and frozen estimates are unchanged.

## Artificial Intelligence Assistance
ChatGPT (GPT-5.6 Sol; OpenAI) and Codex (GPT-5.6; OpenAI) assisted with language polishing, journal-format adaptation, and limited code modification and troubleshooting, including suggesting possible solutions to coding errors. The authors reviewed the assisted changes. This statement does not attribute study design, model selection, statistical specifications or scientific interpretation to these tools.

## Citation
Chen W, Wei J, Wang Z, et al. Conditional Mortality and Survival Gap in Resected Nonmetastatic Gallbladder Adenocarcinoma. [Journal/DOI to be added after publication]

Software citation metadata are in CITATION.cff. No DOI or repository URL has been invented.

Authors, in order: Wenhao Chen; Jinlu Wei; Zhanjin Wang; Peng Pan; Kaihao Du; Weiwei Xue; Zhan Wang.
