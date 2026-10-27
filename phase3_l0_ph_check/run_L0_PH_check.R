#!/usr/bin/env Rscript
# L0 only; frozen inputs are READ ONLY. R4.4.3 / survival3.8.3.
# Run: Rscript --vanilla phase3_l0_ph_check/run_L0_PH_check.R --formal
# --point: original-data diagnostics only. --smoke: 50 technical replicates only.
# Explicit --formal: 50 technical replicates THEN 1000 patient-level replicates.
# No argument: usage only; no private inputs are read.
# Formal RNG: original Phase3 L'Ecuyer-CMRG seed20261027, stream1.
# Smoke RNG: same master seed, independent stream3. No redraw or trimming.

options(device = function(...) stop("An explicit graphics device must be opened"))
Sys.setenv(LANG = "C", LC_ALL = "C")
invisible(Sys.setlocale("LC_CTYPE", ".UTF-8"))
.gbc_files <- unlist(lapply(sys.frames(), function(f) f$ofile))
.gbc_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(.gbc_arg)) .gbc_files <- c(.gbc_files, sub("^--file=", "", .gbc_arg[1]))
.gbc_candidates <- unique(c(Sys.getenv("GBC_CODE_ROOT", ""), getwd(),
  dirname(.gbc_files), dirname(dirname(.gbc_files))))
.gbc_candidates <- .gbc_candidates[!is.na(.gbc_candidates) & nzchar(.gbc_candidates)]
.gbc_found <- .gbc_candidates[file.exists(file.path(.gbc_candidates, "scripts/current_kernels/public_config.R"))]
if (!length(.gbc_found)) stop("Set GBC_CODE_ROOT to the public checkout root.", call. = FALSE)
source(file.path(.gbc_found[1], "scripts/current_kernels/public_config.R"))
ROOT <- gbc_code_root()
HERE <- file.path(ROOT, "phase3_l0_ph_check")
PYTHON <- Sys.getenv("GBC_PYTHON", Sys.which("python"))
original <- new.env(parent = .GlobalEnv)
source(file.path(ROOT, "phase3_minimal/run_phase3.R"), local = original, encoding = "UTF-8")
require_ok <- original$require_ok
say <- original$say
source(file.path(HERE, "L0_model_core.R"), encoding = "UTF-8")

l0_input <- function() {
  # Thin read-only Parquet / existing-workbook bridge. No Phase2, cleaning, L1-L5
  # construction or previous analysis entry point is called.
  code <- paste(c(
    "import sys,json,pandas as pd,openpyxl",
    "from pathlib import Path",
    "sys.dont_write_bytecode=True",
    "root=Path(sys.argv[1])",
    "cols=['patient_id','year_dx','age_dx','age_90plus_flag','sex','T_model','N_model','grade_model','survival_days_analysis','event_competing','event_os','M_harmonized']",
    "a=pd.read_parquet(root/'data/analysis_patient_level_v2.parquet',columns=cols)",
    "assert len(a)==7007, 'Source cohort count mismatch'",
    "d=a[a.year_dx.between(2004,2015)].sort_values('patient_id').copy()",
    "assert len(d)==3918 and d.patient_id.is_unique and not d.isna().any().any(), 'Dynamic cohort mismatch/missing'",
    "d['patient_id']=d.patient_id.astype(str)",
    "w=openpyxl.load_workbook(root/'phase3_minimal/phase3_results.xlsx',read_only=True,data_only=True)",
    "s=w['Adjusted_Pathology']; rows=list(s.iter_rows(values_only=True)); heads=rows[4]",
    "f=[dict(zip(heads,row)) for row in rows[5:] if row[0] is not None]",
    "f=[r for r in f if r['landmark'] in [0,5]]",
    "assert len(f)==6, 'Frozen L0/L5 rows missing'",
    "w.close()",
    "print(json.dumps({'source_n':len(a),'data':json.loads(d.to_json(orient='records',double_precision=15)),'frozen':f},ensure_ascii=True,allow_nan=False))"
  ), collapse = "\n")
  result <- processx::run(PYTHON, c("-B", "-X", "utf8", "-c", code, gbc_runtime()$data),
    echo = FALSE, error_on_status = TRUE, timeout = 120000)
  input <- jsonlite::fromJSON(result$stdout)
  d <- input$data; d <- d[order(d$patient_id, method = "radix"), , drop = FALSE]
  require_ok(input$source_n == 7007 && nrow(d) == 3918 && !anyDuplicated(d$patient_id) && !anyNA(d), "Frozen cohort gate failed")
  require_ok(all(d$year_dx %in% 2004:2015) && all(d$M_harmonized == "M0") &&
    all(d$sex %in% c("Female", "Male")) && all(d$survival_days_analysis > 0) &&
    all(d$event_competing %in% 0:2) && all(d$event_os == as.integer(d$event_competing > 0)), "Input time/sex/event/M0 gate failed")
  input$data <- d
  input
}

l0_check_point <- function(point, frozen) {
  ph <- point$summary[point$summary$model == "PH", ]
  f <- frozen[frozen$landmark == 0, ]; j <- match(ph$target, f$target)
  require_ok(!anyNA(j) && all(ph$status == "OK") &&
    max(abs(ph$rd_pp - f$adjusted_rd_pp[j])) < 1e-8 &&
    all(ph$reference_n == f$reference_n[j]) &&
    all(ph$high_n == f$high_n[j]) && all(ph$low_n == f$low_n[j]) &&
    all(ph$high_gbc_events == f$high_gbc_events_36mo[j]) &&
    all(ph$low_gbc_events == f$low_gbc_events_36mo[j]), "STOP: frozen L0 PH estimates/counts do not reproduce")
  say("PASS: source7007 / L0=3918; original L0 PH RD and reference/arm/event counts reproduced")
}

l0_bootstrap <- function(data, kernels, B, stream, workers) {
  RNGkind("L'Ecuyer-CMRG"); set.seed(20261027L)
  for (i in seq_len(stream)) assign(".Random.seed", parallel::nextRNGStream(.Random.seed), envir = .GlobalEnv)
  draws <- lapply(seq_len(B), function(b) sample.int(nrow(data), nrow(data), replace = TRUE))
  cl <- NULL
  if (workers > 1L) {
    cl <- parallel::makePSOCKcluster(workers, outfile = "")
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterCall(cl, function(here, data) {
      source(file.path(here, "run_L0_PH_check.R"), local = .GlobalEnv, encoding = "UTF-8")
      assign(".l0_data", data, envir = .GlobalEnv)
      assign(".l0_kernels", original$extract_csc_kernels(ROOT), envir = .GlobalEnv)
      TRUE
    }, HERE, data)
  }
  output <- vector("list", B)
  safe <- function(d, original, kernels) {
    tryCatch(l0_evaluate(d, original, kernels)$summary, error = function(e) {
      z <- expand.grid(model = c("PH", "PATH_TV", "AGE_TV"), target = names(original$phase3_targets), stringsAsFactors = FALSE)
      z$rd_pp <- NA_real_; z$high_cif <- z$low_cif <- NA_real_
      z$status <- "NOT_ESTIMABLE"; z$reason <- conditionMessage(e); z
    })
  }
  for (first in seq.int(1L, B, by = 10L)) {
    batch <- first:min(first + 9L, B)
    if (is.null(cl)) answers <- lapply(draws[batch], function(i) safe(data[i, , drop = FALSE], original, kernels)) else {
      answers <- parallel::parLapply(cl, draws[batch], function(i) {
        tryCatch(l0_evaluate(.l0_data[i, , drop = FALSE], original, .l0_kernels)$summary, error = function(e) {
          z <- expand.grid(model = c("PH", "PATH_TV", "AGE_TV"), target = names(original$phase3_targets), stringsAsFactors = FALSE)
          z$rd_pp <- NA_real_; z$high_cif <- z$low_cif <- NA_real_
          z$status <- "NOT_ESTIMABLE"; z$reason <- conditionMessage(e); z
        })
      })
    }
    for (j in seq_along(batch)) {
      ans <- answers[[j]]; ans$replicate <- batch[j]
      output[[batch[j]]] <- ans
    }
    if (first == 1L || max(batch) %% 50L == 0L || max(batch) == B)
      say(if (B == 50L) "TECHNICAL" else "FORMAL", "patient bootstrap", max(batch), "/", B)
  }
  # Binding only once: all failures are retained with replicate number/reason.
  fields <- Reduce(union, lapply(output, names))
  output <- lapply(output, function(x) {for (n in setdiff(fields, names(x))) x[[n]] <- NA; x[, fields]})
  do.call(rbind, output)
}

l0_interval <- function(x, B) {
  good <- is.finite(x)
  if (sum(good) / B < .95) c(NA_real_, NA_real_) else unname(quantile(x[good], c(.025, .975), type = 7))
}

l0_summarize <- function(point, boot, frozen, B = 1000L) {
  rows <- list()
  for (i in seq_len(nrow(point$summary))) {
    row <- point$summary[i, ]; s <- boot[boot$target == row$target & boot$model == row$model, ]
    require_ok(nrow(s) == B && !anyDuplicated(s$replicate), "Bootstrap attempt count changed")
    ci <- l0_interval(s$rd_pp, B)
    row$lower95_pp <- ci[1]; row$upper95_pp <- ci[2]
    row$bootstrap_attempts <- B; row$bootstrap_valid <- sum(is.finite(s$rd_pp)); row$bootstrap_valid_fraction <- row$bootstrap_valid / B
    ph <- boot[boot$target == row$target & boot$model == "PH", ]; j <- match(s$replicate, ph$replicate)
    delta <- s$rd_pp - ph$rd_pp[j]; dc <- l0_interval(delta, B)
    pp <- point$summary[point$summary$target == row$target & point$summary$model == "PH", ]
    row$delta_vs_ph_pp <- row$rd_pp - pp$rd_pp; row$delta_lower95_pp <- dc[1]; row$delta_upper95_pp <- dc[2]
    row$paired_valid <- sum(is.finite(delta)); row$paired_valid_fraction <- row$paired_valid / B
    f <- frozen[frozen$target == row$target & frozen$landmark == 0, ]; f5 <- frozen[frozen$target == row$target & frozen$landmark == 5, ]
    row$frozen_ph_rd_pp <- f$adjusted_rd_pp; row$frozen_ph_lower95_pp <- f$adjusted_lower95_pp; row$frozen_ph_upper95_pp <- f$adjusted_upper95_pp
    row$frozen_l5_rd_pp <- f5$adjusted_rd_pp; row$frozen_l5_lower95_pp <- f5$adjusted_lower95_pp; row$frozen_l5_upper95_pp <- f5$adjusted_upper95_pp
    row$ci_width_pp <- diff(ci); row$ci_width_ratio_to_ph <- diff(ci) / (f$adjusted_upper95_pp - f$adjusted_lower95_pp)
    row$direction_changed <- sign(row$rd_pp) != sign(pp$rd_pp)
    row$manual_review_3pp <- abs(row$delta_vs_ph_pp) >= 3
    row$role <- if (row$model == "PH") "Original specification refit" else if (row$model == "PATH_TV") "Prespecified primary sensitivity" else "Diagnostic-driven exploratory sensitivity"
    row$status <- if (row$bootstrap_valid_fraction >= .95) "ESTIMABLE" else "INSUFFICIENT_VALID_BOOTSTRAPS"
    rows[[i]] <- row
  }
  do.call(rbind, rows)
}

l0_main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (!any(args %in% c("--formal", "--smoke", "--point")) || "--help" %in% args) {
    cat("Set GBC_CODE_ROOT, GBC_FINAL_RUN_ROOT, GBC_PREPARATION_ROOT, GBC_OUTPUT_ROOT, GBC_PYTHON.\n")
    cat("Run Rscript --vanilla phase3_l0_ph_check/run_L0_PH_check.R --formal.\n")
    cat("--point: point diagnostics only; --smoke: 50 technical draws only. No default analysis.\n")
    return(invisible(NULL))
  }
  require_ok(sum(args %in% c("--formal", "--smoke", "--point")) == 1L, "Choose exactly one run mode")
  cfg <- gbc_runtime()
  if ("--formal" %in% args) require_ok(!file.exists(file.path(cfg$output,"phase3_l0_ph_check")),
    "Choose a fresh private output root: L0 destination already exists")
  input <- l0_input(); kernels <- original$extract_csc_kernels(ROOT)
  say("Locked: 3 periods; pathology TV both causes; exploratory age2 TV GBC only; no sex TV")
  point <- l0_evaluate(input$data, original, kernels, verify = TRUE)
  l0_check_point(point, input$frozen)
  print(point$summary[, c("target", "model", "rd_pp", "status")], row.names = FALSE)
  # Model objects are no longer needed for delivery/checkpoint; no patient-level
  # records, source identifiers or fitted model frames enter the saved bundle.
  point$models <- NULL
  if ("--point" %in% args) return(invisible(point))
  smoke <- l0_bootstrap(input$data, kernels, 50L, 3L, 2L)
  smoke_qc <- aggregate(is.finite(smoke$rd_pp), smoke[, c("target", "model")], sum)
  names(smoke_qc)[3] <- "valid_of_50"; print(smoke_qc, row.names = FALSE)
  require_ok(all(smoke_qc$valid_of_50 >= 48), "Technical test failed: review failures before formal bootstrap; no redraw")
  if ("--smoke" %in% args) return(invisible(smoke_qc))
  boot <- l0_bootstrap(input$data, kernels, 1000L, 1L, 2L)
  comparison <- l0_summarize(point, boot, input$frozen)
  # Public export is aggregate-only and has no Codex/Node/skill dependency.
  bundle <- list(point = point, comparison = comparison, smoke_qc = smoke_qc,
    bootstrap = boot, frozen = input$frozen, B = 1000L, seed = 20261027L)
  bundle$point$residuals <- NULL
  destination <- file.path(cfg$output, "phase3_l0_ph_check")
  gbc_export_aggregate(bundle, destination)
  utils::write.csv(point$diagnostics, file.path(destination, "PH_Diagnostics.csv"), row.names = FALSE, na = "")
  utils::write.csv(comparison, file.path(destination, "Model_Comparison.csv"), row.names = FALSE, na = "")
  utils::write.csv(smoke_qc, file.path(destination, "Smoke_QC.csv"), row.names = FALSE, na = "")
  utils::write.csv(boot, file.path(destination, "Bootstrap_QC.csv"), row.names = FALSE, na = "")
  utils::write.csv(point$events, file.path(destination, "Period_Events.csv"), row.names = FALSE, na = "")
  utils::write.csv(point$calibration, file.path(destination, "Apparent_Calibration.csv"), row.names = FALSE, na = "")
  say("L0 PH CHECK COMPLETE. Aggregate results:", destination)

}

if (sys.nframe() == 0L) l0_main()
