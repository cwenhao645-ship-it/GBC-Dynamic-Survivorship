# Environment provenance
sessionInfo.txt and package_versions.csv were captured from the installed R 4.4.3 environment on 2026-09-12 after loading the actual analysis and plotting packages. No clinical analysis was executed for this capture. Paths, usernames and hostnames are not included.

The original Stage 1 report records Python 3.12.14, numpy 2.3.5, pandas 3.0.1, pyarrow 25.0.1, matplotlib 3.10.6, statsmodels 0.14.5, scipy 1.18.1 and openpyxl 3.1.5. The preparation environment was independently inspected on 2026-09-12: Python 3.12.14 and these named installed packages agree; PyYAML is 6.0.3. Model scripts originally used a separate Python 3.13 reader executable and a separate verification runtime. A single unified Python lock has not been validated.

The observed workbook dependency @oai/artifact-tool is version 2.8.59 and its package metadata mark it private. It is not bundled here; a public installation route has not been established. This blocks an unrestricted end-to-end public rerun.

No renv.lock is provided: no historically validated lockfile exists in the inspected project, and generating one from a current environment would not prove restoration of the original complete mixed-language execution environment. Version records are evidence, not a successful restoration test. yaml 2.3.10 is installed for the public path-loader wrapper.

