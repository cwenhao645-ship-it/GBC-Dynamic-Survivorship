# Software environment and restore limits

## Current Phase3 / L0 compute modules

The frozen analyses used **R4.4.3 / survival3.8.3**, strictly checked by the entry points. R computation also uses jsonlite2.0.0 and processx3.8.6. Public Figure3 export needs ggplot2, patchwork, readxl and Cairo; measured recent plotting versions were ggplot2 4.0.3, patchwork1.3.2 and ragg1.4.0. The PDF-only public exporter does not require ragg, Node or private QA helpers.

Cairo here is the R graphics-device capability, not an additional R package. The retained Figure2 exporter additionally uses scales and ragg; the optional YAML configuration adapter uses the R yaml package. Base R parallel is used for controlled worker pools. Original Stage1's additional dependencies remain in its recorded environment below rather than being presented as requirements of the new compute-only wrappers.

Recent analysis Python: **3.13.3**, numpy2.4.2, pandas2.3.3, pyarrow23.0.1, openpyxl3.1.5. PyYAML is used by original preparation/configuration functions; the preparation record lists6.0.3. Set GBC_PYTHON to the intended interpreter. requirements-current.txt records these Python dependencies; it is not a clean-machine execution certificate.

Install through normal supported channels. The update did not install a new Conda environment or unrelated software. Run public data-free checks before authorizing analysis. Never source legacy analysis files just to inspect syntax.

## Historical September records

sessionInfo.txt and package_versions.csv preserve the **2026-09-12** R snapshot, not a new October capture. Paths, usernames and hostnames were removed in the original public release.

Original Stage1 recorded Python3.12.14, numpy2.3.5, pandas3.0.1, pyarrow25.0.1, matplotlib3.10.6, statsmodels0.14.5, scipy1.18.1, openpyxl3.1.5; the September inspection recorded PyYAML6.0.3. These separate records must not be merged into a fictitious unified historical environment.

## Export stack and reproducibility limits

Earlier workbook/PDF packaging depended on private @oai/artifact-tool and local Codex skill helpers. A public installation/redistribution route was not established. They are not bundled or required by current compute-only entry points. Generic aggregate exports and the public Figure3 renderer are different I/O layers, not changed estimators; original workbook cosmetics/private QA are not promised on a public installation.

No renv.lock is invented: no historically validated mixed-language lockfile was found. Recorded versions, syntax checks and mathematical-source equality do not prove a complete independent restore. Authorized datasets, input provenance and frozen aggregate requirements still apply; see ../docs/reproducibility_notes.md.
