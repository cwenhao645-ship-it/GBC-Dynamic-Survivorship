#!/usr/bin/env Rscript
# Phase 3 minimal strengthening. R 4.4.3 / survival 3.8.3.
# Date: 2026-10-27. Original data/scripts/results are read-only.
# A: L'Ecuyer-CMRG seed 20261027, stream 1, 1000 source-patient draws.
# B: same seed, stream 2; C: NumPy PCG64 seed 20261030.
# Run: Rscript --vanilla phase3_minimal/run_phase3.R --smoke
# Run: Rscript --vanilla phase3_minimal/run_phase3.R --formal
# Explicit --formal is required; --smoke is a requested technical run.
# No argument: usage only. Source is safe; no analysis or output is started.

suppressPackageStartupMessages(library(survival))
stopifnot(as.character(getRversion()) == "4.4.3",
          as.character(packageVersion("survival")) == "3.8.3")
require_ok <- function(x, message) {
  if (!isTRUE(x)) stop(message, call. = FALSE)
  invisible(TRUE)
}
say <- function(...) {cat(format(Sys.time(), "%H:%M:%S"), ..., "\n"); flush.console()}

# Resolve code independently from private input/output roots.
.gbc_files <- unlist(lapply(sys.frames(), function(f) f$ofile))
.gbc_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(.gbc_arg)) .gbc_files <- c(.gbc_files, sub("^--file=", "", .gbc_arg[1]))
.gbc_candidates <- unique(c(Sys.getenv("GBC_CODE_ROOT", ""), getwd(),
  dirname(.gbc_files), dirname(dirname(.gbc_files))))
.gbc_candidates <- .gbc_candidates[!is.na(.gbc_candidates) & nzchar(.gbc_candidates)]
.gbc_found <- .gbc_candidates[file.exists(file.path(.gbc_candidates, "scripts/current_kernels/public_config.R"))]
if (!length(.gbc_found)) stop("Set GBC_CODE_ROOT to this public checkout root.", call. = FALSE)
source(file.path(.gbc_found[1], "scripts/current_kernels/public_config.R"))
options(gbc.code_root = gbc_code_root())

phase3_targets <- list(
  T = list(variable = "T_model", low = "T1", high = "T3/4", label = "T3/4 vs T1"),
  N = list(variable = "N_model", low = "N0", high = "N+", label = "N+ vs N0"),
  Grade = list(variable = "grade_model", low = "G1", high = "G3/4", label = "G3/4 vs G1"))

extract_csc_kernels <- function(root) {
  path <- file.path(root, "scripts/current_kernels/cause_specific.R")
  parsed <- parse(file = path, keep.source = FALSE)
  wanted <- c("assert", "fit_failure", "cox_checked", "baseline_information", "integrate_grid")
  env <- new.env(parent = .GlobalEnv)
  found <- character()
  for (node in parsed) if (is.call(node) && identical(node[[1]], as.name("<-")) &&
      is.symbol(node[[2]]) && as.character(node[[2]]) %in% wanted) {
    name <- as.character(node[[2]])
    require_ok(!name %in% found, "Repeated original CSC kernel definition")
    eval(node, env); found <- c(found, name)
  }
  require_ok(setequal(found, wanted), "Original CSC kernels unavailable")
  env$source_file <- path
  env
}

phase3_landmark <- function(d, s) {
  z <- d[d$survival_days_analysis > s * 365.25, , drop = FALSE]
  z$lm <- s; z$start <- 0
  z$u <- z$survival_days_analysis / 365.25 - s
  z$stop <- pmin(z$u, 3)
  z$event <- ifelse(z$u <= 3, as.integer(z$event_competing), 0L)
  # SEER age is integer diagnosis age, and 90+ is topcoded. This is recorded
  # attained-age proxy, not an invented birthday/exact age for 90+ patients.
  z$age_attained <- z$age_dx + s
  require_ok(all(z$stop > 0) && all(z$event %in% 0:2), "Invalid landmark time/event")
  z
}

aj_endpoint <- function(z) {
  if (!nrow(z)) return(rep(NA_real_, 2))
  time <- sort(unique(z$stop))
  group <- match(z$stop, time)
  m <- rowsum(cbind(n = rep(1, nrow(z)), d1 = as.numeric(z$event == 1),
                   d2 = as.numeric(z$event == 2)), group, reorder = TRUE)
  risk <- rev(cumsum(rev(m[, "n"])))
  h1 <- m[, "d1"] / risk; h2 <- m[, "d2"] / risk
  surv <- cumprod(1 - h1 - h2)
  before <- c(1, head(surv, -1))
  if (!any(z$u >= 3) && tail(surv, 1) > 1e-12) return(rep(NA_real_, 2))
  out <- c(sum(before * h1), sum(before * h2))
  require_ok(all(is.finite(out)) && all(out >= -1e-12 & out <= 1 + 1e-12) &&
    sum(out) <= 1 + 1e-10, "AJ endpoint probability bound failed")
  out
}

age_sex_support <- function(z, target) {
  t <- phase3_targets[[target]]
  mask <- rep(FALSE, nrow(z)); ranges <- character()
  for (sex in c("Female", "Male")) {
    high <- z$age_attained[z$sex == sex & z[[t$variable]] == t$high]
    low <- z$age_attained[z$sex == sex & z[[t$variable]] == t$low]
    if (!length(high) || !length(low)) next
    lo <- max(min(high), min(low)); hi <- min(max(high), max(low))
    if (lo <= hi) mask <- mask | (z$sex == sex & z$age_attained >= lo & z$age_attained <= hi)
    ranges <- c(ranges, paste0(sex, ":", lo, "-", hi))
  }
  list(mask = mask, ranges = paste(ranges, collapse = "; "))
}

age_sex_design <- function(age, sex, high) {
  a <- (age - 70) / 10
  cbind(High = as.numeric(high), Age10 = a, Age10_squared = a * a,
        Male = as.numeric(sex == "Male"))
}

fit_age_sex_cause <- function(z, target, cause, kernels, diagnose = FALSE) {
  t <- phase3_targets[[target]]
  # Prespecified two-arm fitting, NOT deletion after failed fitting. Other
  # pathology levels remain in the source cohort and eligible reference.
  d <- z[z[[t$variable]] %in% c(t$low, t$high), , drop = FALSE]
  x <- age_sex_design(d$age_attained, d$sex, d[[t$variable]] == t$high)
  require_ok(nrow(d) > 0 && sum(d$event == cause) > 0 && any(d$u >= 3),
    "No cause events or 36-month fitting support")
  require_ok(qr(sweep(x, 2, colMeans(x), "-"), tol = 1e-9)$rank == ncol(x),
    "Rank-deficient fixed age/sex/pathology design")
  frame <- data.frame(start = d$start, stop = d$stop, death = as.integer(d$event == cause))
  frame$X <- I(x)
  fit <- kernels$cox_checked(Surv(start, stop, death) ~ X, frame)
  require_ok(length(coef(fit)) == ncol(x) &&
    max(abs(unname(fit$x) - unname(x))) < 1e-10, "Cox design order changed")
  require_ok(max(fit$iter) < 60 && rcond(fit$var) >= 1e-12,
    "Nonconverged/ill-conditioned fixed model")
  beta <- setNames(as.numeric(coef(fit)), colnames(x))
  baseline <- kernels$baseline_information(d, x, beta, cause)$baseline[[as.character(z$lm[1])]]
  require_ok(nrow(baseline) > 0 && all(is.finite(baseline$hazard)), "Invalid fitted cause baseline")
  ph <- NA_real_; ph_message <- ""
  if (diagnose) {
    ph_result <- tryCatch(survival::cox.zph(fit, transform = "km"), error = function(e) e)
    if (inherits(ph_result, "error")) ph_message <- conditionMessage(ph_result) else
      ph <- unname(ph_result$table["GLOBAL", "p"])
  }
  list(beta = beta, baseline = baseline, ph_global_p = ph,
       ph_message = ph_message, warnings = paste(fit$captured_warnings, collapse = "; "))
}

predict_age_sex_pair <- function(pair, ref, high, kernels) {
  # Collapsing identical age/sex prediction rows is exact frequency aggregation,
  # not reference subsampling. Every bootstrap patient copy retains its weight.
  k <- paste(ref$age_attained, ref$sex, sep = "|")
  unique_index <- which(!duplicated(k))
  weights <- tabulate(match(k, k[unique_index]), nbins = length(unique_index))
  r <- ref[unique_index, , drop = FALSE]
  x <- age_sex_design(r$age_attained, r$sex, rep(high, nrow(r)))
  times <- sort(unique(c(pair[[1]]$baseline$time, pair[[2]]$baseline$time)))
  times <- times[times <= 3]
  a <- lapply(pair, function(f) {
    require_ok(identical(colnames(x), names(f$beta)), "Prediction design mismatch")
    h <- f$baseline$hazard[match(times, f$baseline$time)]; h[is.na(h)] <- 0
    outer(exp(drop(x %*% f$beta)), h)
  })
  p <- kernels$integrate_grid(times, a[[1]], a[[2]], 0, 3)
  require_ok(all(p[, 1:3] >= -1e-12) && all(p[, 1:3] <= 1 + 1e-12),
    "Standardized CIF probability bound failed")
  colSums(p[, 1:3, drop = FALSE] * weights) / sum(weights)
}

evaluate_pathology <- function(d, kernels, diagnose = FALSE) {
  rows <- list(); index <- 0L
  for (s in 0:5) {
    z <- phase3_landmark(d, s)
    for (target in names(phase3_targets)) {
      t <- phase3_targets[[target]]; index <- index + 1L
      lo <- z[[t$variable]] == t$low; hi <- z[[t$variable]] == t$high
      support <- age_sex_support(z, target); ref <- z[support$mask, , drop = FALSE]
      crude_low <- aj_endpoint(z[lo, , drop = FALSE])[1]
      crude_high <- aj_endpoint(z[hi, , drop = FALSE])[1]
      row <- data.frame(target = target, contrast = t$label, landmark = s,
        landmark_n = nrow(z), fit_n = sum(lo | hi), reference_n = nrow(ref),
        reference_coverage = nrow(ref) / nrow(z),
        low_n = sum(lo), high_n = sum(hi),
        low_gbc_events_36mo = sum(z$event[lo] == 1),
        high_gbc_events_36mo = sum(z$event[hi] == 1),
        low_other_events_36mo = sum(z$event[lo] == 2),
        high_other_events_36mo = sum(z$event[hi] == 2),
        topcoded_age_n = sum(as.logical(z$age_90plus_flag)),
        support_age_ranges = support$ranges,
        crude_rd_pp = 100 * (crude_high - crude_low),
        adjusted_low_cif = NA_real_, adjusted_high_cif = NA_real_, adjusted_rd_pp = NA_real_,
        gbc_ph_global_p = NA_real_, other_ph_global_p = NA_real_,
        ph_message = "", fit_message = "", status = "NOT_ESTIMABLE")
      attempt <- tryCatch({
        require_ok(nrow(ref) > 0 && sum(lo) > 0 && sum(hi) > 0, "Empty comparison/support")
        pair <- lapply(1:2, function(cause) fit_age_sex_cause(z, target, cause, kernels, diagnose))
        low <- predict_age_sex_pair(pair, ref, FALSE, kernels)
        high <- predict_age_sex_pair(pair, ref, TRUE, kernels)
        list(low = low, high = high, pair = pair)
      }, error = function(e) e)
      if (inherits(attempt, "error")) row$fit_message <- conditionMessage(attempt) else {
        row$adjusted_low_cif <- attempt$low[1]
        row$adjusted_high_cif <- attempt$high[1]
        row$adjusted_rd_pp <- 100 * (attempt$high[1] - attempt$low[1])
        row$gbc_ph_global_p <- attempt$pair[[1]]$ph_global_p
        row$other_ph_global_p <- attempt$pair[[2]]$ph_global_p
        row$ph_message <- paste(vapply(attempt$pair, `[[`, "", "ph_message"), collapse = "; ")
        row$fit_message <- paste(vapply(attempt$pair, `[[`, "", "warnings"), collapse = "; ")
        row$status <- "OK"
      }
      rows[[index]] <- row
    }
  }
  do.call(rbind, rows)
}

phase3_pathology <- function(d, crude, kernels, B = 1000L, smoke = FALSE) {
  started <- proc.time()[3]
  d <- d[order(d$patient_id, method = "radix"), , drop = FALSE]
  require_ok(nrow(d) == 3918 && !anyNA(d) && !anyDuplicated(d$patient_id), "Original CR data gate failed")
  require_ok(all(d$event_os == as.integer(d$event_competing > 0)), "Overlapping event classification")
  point <- evaluate_pathology(d, kernels, diagnose = TRUE)
  key <- function(a) paste(a$target, a$landmark)
  j <- match(key(point), key(crude))
  require_ok(nrow(point) == 18 && !anyNA(j) &&
    max(abs(point$crude_rd_pp - crude$crude_rd_pp[j])) < 1e-8,
    "STOP: frozen crude pathology contrasts do not reproduce")
  point$crude_lower95_pp <- crude$crude_lower95_pp[j]
  point$crude_upper95_pp <- crude$crude_upper95_pp[j]
  point$crude_bootstrap_valid <- crude$crude_bootstrap_valid[j]
  say("A point estimates: ", sum(point$status == "OK"), "/18 estimable; original crude contrasts reproduced")
  draws <- array(NA_real_, c(18L, 4L, B), dimnames = list(NULL,
    c("adjusted_rd_pp", "adjusted_low_cif", "adjusted_high_cif", "crude_rd_pp"), NULL))
  reasons <- matrix("", B, 18L)
  RNGkind("L'Ecuyer-CMRG"); set.seed(20261027L)
  assign(".Random.seed", parallel::nextRNGStream(.Random.seed), envir = .GlobalEnv)
  # Generate source-patient draws in the master R stream before dispatch. This
  # preserves exactly the same samples/results with one or two workers.
  samples <- lapply(seq_len(B), function(b) sample.int(nrow(d), nrow(d), replace = TRUE))
  workers <- if (smoke) 1L else 2L
  if (workers > 1L) {
    cl <- parallel::makePSOCKcluster(workers, outfile = "")
    on.exit(parallel::stopCluster(cl), add = TRUE)
    runner <- file.path(getOption("gbc.code_root"), "phase3_minimal/run_phase3.R")
    parallel::clusterCall(cl, function(runner, data) {
      source(runner, local = .GlobalEnv)
      assign(".phase3_d", data, envir = .GlobalEnv)
      assign(".phase3_kernels", extract_csc_kernels(dirname(dirname(runner))), envir = .GlobalEnv)
      TRUE
    }, runner, d)
  }
  collect <- function(ans, b) {
    require_ok(identical(key(ans), key(point)), "Bootstrap result layout changed")
    draws[, , b] <<- as.matrix(ans[, dimnames(draws)[[2]]])
    reasons[b, ] <<- ifelse(ans$status == "OK", "", ans$fit_message)
    if (b == 1L || b %% 50L == 0L || b == B) say("A patient bootstrap", b, "/", B)
  }
  if (workers == 1L) for (b in seq_len(B)) {
    collect(evaluate_pathology(d[samples[[b]], , drop = FALSE], kernels), b)
  } else for (first in seq.int(1L, B, by = 50L)) {
    batch <- first:min(first + 49L, B)
    answers <- parallel::parLapply(cl, samples[batch], function(draw)
      evaluate_pathology(.phase3_d[draw, , drop = FALSE], .phase3_kernels))
    for (j in seq_along(batch)) collect(answers[[j]], batch[j])
  }
  interval <- function(x) {
    # Original standardization gate: >=95% valid, failed draws remain in the
    # denominator. No redraw, trimming, winsorization or post-failure rescue.
    if (smoke || mean(is.finite(x)) < .95) return(c(NA_real_, NA_real_))
    unname(quantile(x[is.finite(x)], c(.025, .975), type = 7))
  }
  point$bootstrap_attempts <- B
  point$bootstrap_valid <- vapply(1:18, function(i) sum(is.finite(draws[i, 1, ])), integer(1))
  point$bootstrap_valid_fraction <- point$bootstrap_valid / B
  ci <- t(vapply(1:18, function(i) interval(draws[i, 1, ]), numeric(2)))
  point$adjusted_lower95_pp <- ci[, 1]; point$adjusted_upper95_pp <- ci[, 2]
  for (k in 2:3) {
    ci <- t(vapply(1:18, function(i) interval(draws[i, k, ]), numeric(2)))
    point[[paste0(dimnames(draws)[[2]][k], "_lower95")]] <- ci[, 1]
    point[[paste0(dimnames(draws)[[2]][k], "_upper95")]] <- ci[, 2]
  }
  point$adjusted_minus_crude_pp <- point$adjusted_rd_pp - point$crude_rd_pp
  point$adjusted_change_from_L0_pp <- point$absolute_rd_change_from_L0_pp <- NA_real_
  point$adjusted_change_lower95_pp <- point$adjusted_change_upper95_pp <- NA_real_
  point$absolute_change_lower95_pp <- point$absolute_change_upper95_pp <- NA_real_
  point$ci_split_max_endpoint_difference_pp <- NA_real_
  for (i in 1:18) {
    i0 <- which(point$target == point$target[i] & point$landmark == 0)
    change <- draws[i, 1, ] - draws[i0, 1, ]
    absolute_change <- abs(draws[i, 1, ]) - abs(draws[i0, 1, ])
    point$adjusted_change_from_L0_pp[i] <- point$adjusted_rd_pp[i] - point$adjusted_rd_pp[i0]
    point$absolute_rd_change_from_L0_pp[i] <- abs(point$adjusted_rd_pp[i]) - abs(point$adjusted_rd_pp[i0])
    point[i, c("adjusted_change_lower95_pp", "adjusted_change_upper95_pp")] <- interval(change)
    point[i, c("absolute_change_lower95_pp", "absolute_change_upper95_pp")] <- interval(absolute_change)
    if (!smoke && B >= 1000 && all(is.finite(draws[i, 1, ]))) {
      halves <- cbind(quantile(draws[i, 1, 1:500], c(.025, .975), names = FALSE),
        quantile(draws[i, 1, 501:1000], c(.025, .975), names = FALSE))
      point$ci_split_max_endpoint_difference_pp[i] <- max(abs(halves[, 1] - halves[, 2]))
    }
  }
  point$status[point$status == "OK" & point$bootstrap_valid_fraction < .95] <- "CI_NOT_ESTIMABLE"
  point$status[point$status == "OK" & point$bootstrap_valid_fraction < 1] <- "WARN_SOME_BOOTSTRAP_FAILURES"
  point$age_encoding <- "Recorded diagnosis age + landmark; 90+ is lower-bound proxy"
  point$adjustment <- "Target binary + recorded attained age (linear, quadratic) + sex"
  point$reference <- "LM survivors in sex-specific observed high/low age-range overlap"
  failure_table <- do.call(rbind, lapply(1:18, function(i) {
    x <- table(reasons[nzchar(reasons[, i]), i]); if (!length(x)) return(NULL)
    data.frame(target = point$target[i], landmark = point$landmark[i], reason = names(x), n = as.integer(x))
  }))
  list(summary = point, failures = failure_table,
       seconds = unname(proc.time()[3] - started), B = B, seed = 20261027L,
       stream_advance = 1L, workers = workers, smoke = smoke)
}

phase3_main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (!any(args %in% c("--formal", "--smoke")) || "--help" %in% args) {
    cat("Set GBC_CODE_ROOT, GBC_FINAL_RUN_ROOT, GBC_PREPARATION_ROOT, GBC_OUTPUT_ROOT, GBC_PYTHON.\n")
    cat("Run Rscript --vanilla phase3_minimal/run_phase3.R --formal (or explicit --smoke).\n")
    return(invisible(NULL))
  }
  require_ok(sum(args %in% c("--formal", "--smoke")) == 1L, "Choose exactly one run mode")
  cfg <- gbc_runtime()
  here <- file.path(cfg$code, "phase3_minimal")
  root <- normalizePath(cfg$data, winslash = "/", mustWork = TRUE)
  smoke <- "--smoke" %in% args
  if (!smoke) require_ok(!file.exists(file.path(cfg$output,"phase3_minimal")),
    "Choose a fresh private output root: phase3_minimal destination already exists")
  B <- if (smoke) 10L else 1000L
  python <- cfg$python
  say("PHASE3", if (smoke) "SMOKE" else "FORMAL", "B=", B, "; read-only frozen inputs")
  input <- processx::run(python, c("-B", "-X", "utf8", file.path(here, "phase3_data.py"),
    "--root", root, "--B", B, "--mode", if (smoke) "smoke" else "formal"),
    stdout = "|", stderr = "|", windows_hide_window = TRUE, error_on_status = TRUE)
  cat(input$stderr)
  obj <- jsonlite::fromJSON(input$stdout)
  kernels <- extract_csc_kernels(cfg$code)
  if (!smoke) {
    test <- phase3_pathology(obj$cr_patients, obj$crude, kernels, 10L, smoke = TRUE)
    require_ok(all(is.finite(test$summary$adjusted_rd_pp)) &&
      all(test$summary$bootstrap_valid_fraction == 1), "A small-scale test failed; formal A not started")
    say("A small-scale test PASS; seconds", round(test$seconds, 1))
  }
  a <- phase3_pathology(obj$cr_patients, obj$crude, kernels, B, smoke)
  source(file.path(here, "unified_cohort.R"), local = TRUE)
  # Original all-cause life cohort intentionally retains unresolved COD; only
  # its OS outcome is used for original KM reconciliation. The intersection's
  # two causes are read from the validated competing-risk patient frame.
  life_for_b <- obj$life_patients
  life_for_b$event_competing <- NULL
  b <- phase3_unified(root, obj$cr_patients, life_for_b, obj$frozen_cr,
    obj$frozen_life, B = B, mode = if (smoke) "smoke" else "formal")
  if (smoke) {
    print(a$summary[, c("target", "landmark", "crude_rd_pp", "adjusted_rd_pp", "reference_n", "bootstrap_valid_fraction")])
    print(b$summary[, c("landmark", "n", "observed_RMST_months", "expected_RMST_months", "gap_months", "identity_error_months")])
    say("SMOKE COMPLETE; no formal files written; A seconds", round(a$seconds, 1))
    return(invisible(list(a = a, b = b)))
  }
  # Only aggregate results enter the public-format output. No source patients,
  # identifiers, fitted model frames, private skill or Node runtime is exported.
  result <- list(Adjusted_Pathology = a$summary, Unified_Cohort = b$summary,
    Surgery_Code_Audit = obj$surgery_rows, pathology_failures = a$failures,
    unified_failures = b$failures, unified_qc = b$qc, matching_qc = b$matching_qc,
    surgery_metadata = obj$surgery_metadata, configuration = b$configuration,
    frozen_cr_reference = obj$frozen_cr, frozen_life_reference = obj$frozen_life,
    frozen_crude_pathology_reference = obj$crude)
  destination <- file.path(cfg$output, "phase3_minimal")
  gbc_export_aggregate(result, destination)
  for (name in c("Adjusted_Pathology", "Unified_Cohort", "Surgery_Code_Audit"))
    utils::write.csv(result[[name]], file.path(destination, paste0(name, ".csv")), row.names = FALSE, na = "")
  say("PHASE3 COMPLETE. Aggregate results:", destination)

}

if (sys.nframe() == 0L) phase3_main()
