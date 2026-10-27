# GBC Dynamic Survivorship

## BMC Gastroenterology submission-code version — 2026-10-27

SEER code for dynamic mortality burden among survivors with recorded resection and harmonized M0 gallbladder adenocarcinoma, NOS (ICD-O-3 8140/3). This is the **BMC Gastroenterology Research Article code version**, not the earlier Scientific Reports/JAMA-oriented package. It does not imply acceptance, a publication DOI, or independent end-to-end reproduction.

**Submission alignment:** the author supplied the 2026-10-27 BMC near-submission package during this update. Its main manuscript, Figures 1–3 and fourteen-page Supplement (Tables S1–S9) were inspected read-only. S6 is adjusted pathology, S7 the unified cohort, S8 surgery codes and S9 L0 non-PH sensitivity. The frozen Phase 1/2/3/3B sources and these actual displays establish the mapping below. The current Figure 1 drawing source was not found, and exact reproduction of all manuscript packaging is not certified: [source/display map](docs/original_script_mapping.md).

## Populations, time origin and interpretation

SEER17 Registries; diagnoses2004–2023. These populations are separate:

| Population | L0–L5 counts |
|---|---|
| Harmonized M0 source, 2004–2023 | 7,007 at source selection |
| Dynamic competing risks, 2004–2015 | 3,918 / 2,496 / 1,786 / 1,423 / 1,192 / 1,047 |
| Separate life-table cohort | 3,796 / 2,469 / 1,775 / 1,420 / 1,191 / 1,048 |
| Unified intersection sensitivity | 3,736 / 2,427 / 1,746 / 1,399 / 1,173 / 1,035 |

**Landmarks start at diagnosis, not surgery.** Eventual recorded first-course resection is postdiagnosis information; a first-treatment interval is not a surgery date. Results describe retrospective survivor distributions in that selected population, not validated surgery-origin postoperative prognosis, treatment effects, or elimination of immortal-time/selection bias.

Harmonized M0 does not additionally exclude Summary Stage Distant/Unknown. The limited exclusion-of-Distant sensitivity retains Unknown; it does not replace the main cohort or establish that every discordant patient was misclassified. Registry surgery30/40 versus60 describes recorded extent: code60 does **not** establish R0 status or a standardized radical operation.

## Current analyses

- **Main:** Aalen–Johansen cause-specific CIFs, cause-specific RMTL, and matched general-population expected minus observed RMST. Each L0–L5 horizon is the next36 months, with the original time/censoring rules. CIF is not1−KM.
- **Phase2:** finite Summary-Distant exclusion sensitivity and original input/consistency gates.
- **Phase3A:** age/sex-standardized36-month GBC CIF risk differences: T3/4 vs T1, N+ vs N0, G3/4 vs G1. Two cause-specific Cox models use the binary contrast, continuous attained-age proxy and its square, and sex. Support uses sex-specific observed age-range overlap, not the retired high-dimensional cell filter. Each landmark has its own survivor target population; differences are descriptive, not causal pathology effects.
- **Phase3 unified-cohort module (analysisB):** actual patient intersection; observed RMST + GBC RMTL + other-cause RMTL =36 months, with matched expected RMST/deficit on those same patients. It is a sensitivity analysis, not replacement of either main cohort.
- **Phase3C:** descriptive registry surgery-code audit and supported30/40 versus60 CIF/RMTL; no propensity score or surgery-effect model.
- **Phase3B / L0 PH check** (`phase3_l0_ph_check`, distinct from analysisB above): original PH versus `PATH_TV` (pathology coefficients over0–12,12–24,24–36 months in both causes) and exploratory `AGE_TV` (also time-varying age terms in the GBC model). The frozen analysis used50 technical and1000 formal patient-level bootstrap draws. Paired model-difference intervals use the same resamples, never independent-CI subtraction. The3-pp flag is for human review, not equivalence or model acceptance.

Seeds, percentile definitions, failure denominators and original scientific gates are preserved. These checks do not establish absence of bias or all PH assumptions. [Methods/limits](docs/model_specifications.md).

## Layout

```text
python/scripts/              original preparation, landmarks and AJ source
python/table1_demographics.py  patient-level Table1 formatter
R/09_lifetable/               original life-table source and execution gates
R/10_figures/                 frozen-summary figure sources/adapters
phase3_minimal/               pathology / unified-cohort / surgery modules
phase3_l0_ph_check/           L0 PH / PATH_TV / AGE_TV sensitivity
scripts/current_kernels/     actual shared Cox/CIF and life-table definitions
gbc_transfer_gate/phase2/     finite sensitivity and read-only Phase3 intake
legacy/                      retired complex models and old display assembly
config/ environment/ docs/ tools/  paths, dependencies, provenance, checks
```

Model A/B/C development, temporal validation, baseline-hazard updating and old complex common-support standardization are **not current manuscript analyses**. They and the old11-eTable/2-eFigure mapping are clearly historical; Git history is preserved.

## Three different operations

### A. Public inspection / syntax checks — no SEER data

```sh
python tools/audit_public_repository.py
python tools/audit_public_repository.py --staged
python tools/audit_public_repository.py --history
Rscript --vanilla tools/check_r_sources.R --path-guards
```

The checker parses without importing analysis entry points. R `parse()` does not source a model. Inspect the diff and index manually too; a scanner cannot prove absence of every possible disclosure.

### B. Authorized analysis — private inputs required

Set variables in your shell/R session or a private configuration **outside this repository**:

```r
Sys.setenv(
  GBC_CODE_ROOT = normalizePath("."),
  GBC_FINAL_RUN_ROOT = "/private/final-run-inputs",
  GBC_PREPARATION_ROOT = "/private/preparation-inputs",
  GBC_OUTPUT_ROOT = "/private/new-reproduction-output",
  GBC_PYTHON = "/path/to/python-with-required-packages"
)
```

These are placeholders, not bundled data. Create a new empty output root outside the checkout before running; path checks require that root to exist. See [module requirements](phase3_minimal/README.md), [workflow](docs/analysis_workflow.md) and [environment](environment/README.md). Current public entry points require an explicit mode; no-mode help does not fit models.

```sh
Rscript --vanilla phase3_minimal/run_phase3.R --smoke
Rscript --vanilla phase3_minimal/run_phase3.R --formal
Rscript --vanilla phase3_l0_ph_check/run_L0_PH_check.R --point
Rscript --vanilla phase3_l0_ph_check/run_L0_PH_check.R --smoke
Rscript --vanilla phase3_l0_ph_check/run_L0_PH_check.R --formal
```

`--formal` is expensive and is **not** a repository check. The Phase3 intake actually runs surgery-code analysis too; do not treat it as harmless metadata inspection. The L0 check does not rerun L1–L5, Phase2 or analysisB/C. Public calculation outputs aggregate CSV/JSON/RDS as documented; private Node/Codex workbook/PDF-QA tools are not required by these compute entry points.

The retained full `R/09_lifetable/lifetable_rmst_gap.R` is an original reference module with autorun disabled; its old publication-export stack still needs a private Node artifact package. It is not the public default launcher. Current Phase 2/3 calculations extract the included matching/RMST kernels and do not depend on that exporter.

For an independently authorized S5 reproduction, `python gbc_transfer_gate/phase2/run_phase2.py --formal --rscript <installed-R4.4.3-Rscript>` runs the original finite CR/life-table sensitivity, not the read-only intake helper `phase2.py`. Create the empty private `GBC_OUTPUT_ROOT/phase2` directory first. It refuses output inside input/code roots or overwriting existing comparison/decision files. This optional formal run is not performed by a GitHub update.

### C. Display export — existing frozen summaries, no estimation

The supplied submission contains **Table 1 and Figures 1–3; Supplementary Tables S1–S9**. [The map](docs/original_script_mapping.md) and [display contract](R/12_submission_outputs/README.md) identify the confirmed assignments and remaining source gaps. Figure 3 uses the 18-row Phase 3 `Adjusted_Pathology` summary, not the retired group-CIF/complex-support figure. The original Table 1 formatter supplies the demographic/pathology blocks; the manuscript's added surgery rows are documented Phase 3 audit outputs, not yet part of that formatter.

```sh
Rscript --vanilla R/10_figures/current_figure3.R --input /private/phase3_results.xlsx --output /private/new-reproduction-output/displays/Figure3.pdf
```

This generic public exporter reads actual summaries and does not refit models. Set `GBC_CODE_ROOT` and `GBC_OUTPUT_ROOT`; create the output parent first. New display outputs must be inside the protected output root and must not already exist. Figure 2 additionally requires `GBC_SUBMISSION_OUTPUT/Main` inside that root. Drawing sources preserve the scientific plot specification, but pixel-identical export was not recertified. The supplied Figure 1 has the current diagnosis-origin design; its actual drawing code is missing locally, so legacy code is not falsely presented as its source. No single command claims to regenerate every submission file from absent data/aggregates.

## Data access and licensing

No raw/derived patient-level SEER data, survival records, identifiers, model objects or official life-table exports are distributed. Obtain independent access through [NCI SEER](https://seer.cancer.gov/data/access.html), subject to current eligibility and agreements, and obtain the documented [expected-survival life tables](https://seer.cancer.gov/expsurvival/) independently. De-identification does not grant redistribution rights.

Inputs include the frozen7007-row patient table, descriptive landmark-long table, upstream harmonized precursor, authorized raw export/dictionary for surgery-code provenance, Stage1/LifeTable aggregate workbooks and exact life-table export. The L0 check also needs the frozen Phase3 workbook for consistency checks/L5 context. See [private input gates](docs/reproducibility_notes.md). Independent regeneration of every historical intermediate/submission master is not certified.

The existing [MIT license](LICENSE) covers original software/documentation only, **not SEER data, external life tables or third-party software**. Private input layouts/configuration and generated records must never be committed. No dataset DOI is invented.

## Software / limitations

The current executed analysis uses **R4.4.3 / survival3.8.3**, with strict version checks. Recent Phase2/3 Python was3.13.3; original Stage1 used a separate recorded environment. [Environment records](environment/README.md) distinguish these; a new lockfile is not presented as a validated historical restore.

The update preserves statistical definitions, does not substitute simulated inputs or suppress failed draws, and did not rerun formal bootstraps. Mathematical-source checks and parsing do **not** justify a claim of fully reproducible or one-click end-to-end execution. Authorized data, frozen inputs, original provenance gates, the missing current Figure 1 source and private document assembly remain limitations. The supplied manuscript's data-availability paragraph still says revised Phase 3 code is not public; after this update is pushed and verified, the author must manually reconcile that sentence. No manuscript is edited here.

## AI assistance

ChatGPT and Codex (OpenAI) assisted with code drafting/refactoring, debugging, documentation, statistical-programming/methodological checks and language work. Specifications and scientific decisions were provided or reviewed by the researcher. Authors remain responsible for checking all code, results, manuscript alignment and disclosures before submission. This repository update is source synchronization and limited verification, not a new statistical study. No unverified exact model attribution or claim of completed author review is added.

## Citation

Use [CITATION.cff](CITATION.cff). Add final article metadata only when they exist. Repository: <https://github.com/cwenhao645-ship-it/GBC-Dynamic-Survivorship>.
