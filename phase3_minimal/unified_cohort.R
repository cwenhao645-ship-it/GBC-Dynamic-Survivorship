# Analysis: Phase 3 patient-identity intersection and 36-month time decomposition.
# Date: 2026-10-27. R 4.4.3; survival 3.8.3; jsonlite 2.0.0.
# Bootstrap: 1000 patient draws, seed 20261027, L'Ecuyer-CMRG stream advance 2.
# This helper has no autorun and writes no files. Original source files are read
# only. The caller supplies frozen original point estimates and patient frames.
#
# Required frozen_cr columns: landmark, n, gbc_cif, other_cif,
#   gbc_rmtl_months, other_rmtl_months (CIFs on the probability scale).
# Required frozen_life columns: landmark, n, observed_RMST_months,
#   expected_RMST_months, gap_months.
#
# Original algorithms reused verbatim by AST extraction:
# scripts/05_lifetable_rmst_gap.R: read_life_table, match_patients,
# expected_rmst and observed_rmst. AJ below is the R translation of
# ../gallbladder_dynamic_competing_risk/scripts/run_v2_stage1.py: AJSpec.

phase3_unified <- function(root, cr_patients, life_patients, frozen_cr,
                           frozen_life, B = 1000L, mode = "formal",
                           seed = 20261027L, stream_advance = 2L) {
  fail <- function(ok, text) {
    if (!isTRUE(ok)) stop(text, call. = FALSE)
    invisible(TRUE)
  }
  say <- function(...) {
    cat(format(Sys.time(), "%H:%M:%S"), ..., "\n", file = stderr())
    flush(stderr())
  }
  mode <- match.arg(mode, c("formal", "smoke"))
  B <- as.integer(B)
  fail(length(B) == 1L && is.finite(B) && B > 0L, "Invalid bootstrap count.")
  if (mode == "formal") fail(B == 1000L, "Formal B must be 1000.")
  fail(as.character(getRversion()) == "4.4.3", "Use frozen R 4.4.3.")
  fail(requireNamespace("survival", quietly = TRUE) &&
    as.character(utils::packageVersion("survival")) == "3.8.3",
    "Use frozen survival 3.8.3.")
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  source_path <- file.path(gbc_code_root(), "scripts/current_kernels/lifetable_core.R")
  parsed <- parse(file = source_path, keep.source = FALSE)
  fail(is.call(parsed[[1L]]) &&
    identical(parsed[[1L]][[1L]], as.name("<-")) &&
    identical(parsed[[1L]][[2L]], as.name("gbc_lifetable")),
    "Frozen life-table module assignment changed.")
  container <- parsed[[1L]][[3L]]
  fail(is.call(container) && identical(container[[1L]], as.name("local")),
    "Frozen life-table module container changed.")
  body <- container[[2L]]
  fail(is.call(body) && identical(body[[1L]], as.name("{")),
    "Frozen life-table module body changed.")
  reuse <- c("CFG", "files", "frozen", "database_name", "reasons", "assert",
    "key", "match_status", "read_life_table", "match_patients", "expected_rmst",
    "observed_rmst")
  env <- new.env(parent = baseenv())
  extracted <- character()
  for (node in as.list(body)[-1L]) {
    if (is.call(node) && identical(node[[1L]], as.name("<-")) &&
        is.symbol(node[[2L]])) {
      name <- as.character(node[[2L]])
      if (name %in% reuse) {
        fail(!(name %in% extracted), "Duplicate frozen function definition.")
        eval(node, envir = env)
        extracted <- c(extracted, name)
      }
    }
  }
  fail(setequal(extracted, reuse), "Missing frozen matching/RMST definition.")
  env$S <- new.env(parent = emptyenv())
  env$S$root <- root
  env$S$mode <- mode
  env$S$B <- B
  env$say <- say
  fail(identical(env$CFG$landmarks, 0:5) &&
    env$CFG$year_days == 365.25 && env$CFG$month_days == 30.4375 &&
    env$CFG$tau_days == 1095.75,
    "Frozen landmark/time units changed.")
  year <- env$CFG$year_days
  month <- env$CFG$month_days
  tau <- env$CFG$tau_days
  landmarks <- env$CFG$landmarks
  identity_tolerance <- 1e-8
  metrics <- c("gbc_cif", "other_cif", "gbc_rmtl_months",
    "other_rmtl_months", "observed_RMST_months", "expected_RMST_months",
    "gap_months")
  common_required <- c("patient_id", "record_id", "year_dx", "age_dx", "sex",
    "survival_days_analysis", "event_os")
  validate <- function(d, expected_n, competing = FALSE) {
    required <- c(common_required, if (competing) "event_competing")
    fail(is.data.frame(d) && nrow(d) == expected_n &&
      all(required %in% names(d)), "Original count/required fields differ.")
    fail(!anyNA(d[required]) && !anyDuplicated(d$patient_id) &&
      !anyDuplicated(d$record_id), "Duplicate IDs or missing required data.")
    fail(all(d$year_dx %in% 2004:2015) && all(d$age_dx >= 18) &&
      all(d$sex %in% c("Female", "Male")) &&
      all(is.finite(d$survival_days_analysis)) &&
      all(d$survival_days_analysis > 0) && all(d$event_os %in% 0:1),
      "Original diagnosis period, follow-up, age, sex or event invalid.")
    if (competing) {
      fail(all(d$event_competing %in% 0:2) &&
        all(d$event_os == as.integer(d$event_competing > 0)),
        "Competing/all-cause event classification does not reconcile.")
    } else {
      fail(all(d$age_dx < 90), "Original life-table age eligibility differs.")
    }
    d <- d[order(d$patient_id, method = "radix"), , drop = FALSE]
    rownames(d) <- NULL
    d
  }
  cr <- validate(cr_patients, 3918L, competing = TRUE)
  life <- validate(life_patients, 3796L)
  counts <- function(d) vapply(landmarks, function(s)
    sum(d$survival_days_analysis > s * year), integer(1))
  fail(identical(counts(cr), c(3918L, 2496L, 1786L, 1423L, 1192L, 1047L)),
    "STOP: original competing-risk landmark counts differ.")
  fail(identical(counts(life), c(3796L, 2469L, 1775L, 1420L, 1191L, 1048L)),
    "STOP: original life-table landmark counts differ.")

  # Identity-based intersection; no arithmetic shortcut or new eligibility rule.
  take <- cr$record_id %in% life$record_id
  patients <- cr[take, , drop = FALSE]
  counterpart <- life[match(patients$record_id, life$record_id), , drop = FALSE]
  for (name in common_required) {
    fail(identical(as.character(patients[[name]]),
      as.character(counterpart[[name]])),
      paste("STOP: conflicting shared intersection field:", name))
  }
  fail(nrow(patients) > 0L && all(patients$age_dx < 90),
    "Actual patient intersection is empty or violates life-table age rule.")
  lt <- env$read_life_table()
  fail(nrow(lt) == 10800L && !anyDuplicated(lt$key),
    "Official all-races life-table key QC failed.")

  prepare_aj <- function(time, event, indices) {
    fail(length(time) == length(event) && length(time) == length(indices) &&
      all(time > 0) && all(event %in% 0:2), "Invalid AJ observations.")
    truncated <- pmin(time, tau)
    event <- as.integer(event)
    event[time > tau] <- 0L
    unique_time <- sort(unique(truncated))
    list(indices = indices, time = truncated, event = event,
      unique_time = unique_time, inverse = match(truncated, unique_time))
  }
  evaluate_aj <- function(spec, weights) {
    w <- weights[spec$indices]
    if (!length(w) || sum(w) == 0) return(rep(NA_real_, 4L))
    grouped <- rowsum(cbind(n = w, d1 = w * (spec$event == 1L),
      d2 = w * (spec$event == 2L)), spec$inverse, reorder = TRUE)
    risk <- rev(cumsum(rev(grouped[, "n"])))
    hazard <- matrix(0, nrow(grouped), 2L)
    positive <- risk > 0
    hazard[positive, ] <- grouped[positive, c("d1", "d2"), drop = FALSE] /
      risk[positive]
    survival_after <- cumprod(pmin(1, pmax(0, 1 - rowSums(hazard))))
    survival_before <- c(1, utils::head(survival_after, -1L))
    increments <- hazard * survival_before
    cif <- apply(increments, 2L, cumsum)
    if (!is.matrix(cif)) cif <- matrix(cif, ncol = 2L)
    supported <- any(spec$unique_time >= tau & grouped[, "n"] > 0) ||
      utils::tail(survival_after, 1L) <= 1e-12
    if (!supported) return(rep(NA_real_, 4L))
    endpoint <- cif[nrow(cif), ]
    jump_integral <- colSums(increments * (tau - spec$unique_time))
    # Independently integrate the right-continuous CIF step function, rather
    # than constructing RMTL by subtracting an observed RMST from 36 months.
    step_integral <- colSums(rbind(c(0, 0), cif) *
      diff(c(0, spec$unique_time, tau)))
    fail(all(abs(jump_integral - step_integral) <= 1e-8),
      "RMTL jump and step-function integrals disagree.")
    fail(all(endpoint >= -1e-12 & endpoint <= 1 + 1e-12) &&
      sum(endpoint) <= 1 + 1e-10 && all(jump_integral >= -1e-8) &&
      sum(jump_integral) <= tau + 1e-8,
      "AJ probability or time-loss bound failed.")
    c(endpoint, jump_integral / month)
  }
  prepare <- function(d, matching) {
    lapply(landmarks, function(s) {
      indices <- which(d$survival_days_analysis > s * year)
      z <- d[indices, , drop = FALSE]
      out <- list(indices = indices,
        time = z$survival_days_analysis - s * year,
        event_os = z$event_os, n = length(indices))
      if ("event_competing" %in% names(z)) out$aj <- prepare_aj(out$time,
        z$event_competing, indices)
      if (matching) {
        match <- env$match_patients(z, s, 0L, lt)
        fail(isTRUE(match$qc$match_rate == 1) && all(match$mask),
          "STOP: matching failure; intersection subset must not silently change.")
        out$expected <- env$expected_rmst(match$p)
        out$matching_qc <- match$qc
      }
      out
    })
  }
  cr_specs <- prepare(cr, FALSE)
  life_specs <- prepare(life, TRUE)
  specs <- prepare(patients, TRUE)

  original_cr <- do.call(rbind, lapply(seq_along(landmarks), function(i) {
    value <- evaluate_aj(cr_specs[[i]]$aj, rep(1, nrow(cr)))
    data.frame(landmark = landmarks[i], n = cr_specs[[i]]$n,
      gbc_cif = value[1L], other_cif = value[2L],
      gbc_rmtl_months = value[3L], other_rmtl_months = value[4L])
  }))
  original_life <- do.call(rbind, lapply(seq_along(landmarks), function(i) {
    spec <- life_specs[[i]]
    observed <- env$observed_rmst(spec$time, spec$event_os)
    expected <- mean(spec$expected)
    data.frame(landmark = landmarks[i], n = spec$n,
      observed_RMST_months = observed, expected_RMST_months = expected,
      gap_months = expected - observed)
  }))
  reconcile <- function(own, frozen, fields, label) {
    fail(is.data.frame(frozen) && nrow(frozen) == 6L &&
      all(c("landmark", "n", fields) %in% names(frozen)),
      paste("Missing frozen original", label, "point estimates."))
    frozen <- frozen[order(frozen$landmark), , drop = FALSE]
    fail(identical(as.integer(frozen$landmark), landmarks) &&
      identical(as.integer(frozen$n), as.integer(own$n)),
      paste("STOP: frozen", label, "landmark/sample layout differs."))
    errors <- abs(as.matrix(own[fields]) - as.matrix(frozen[fields]))
    fail(all(is.finite(errors)) && max(errors) <= 1e-8,
      paste("STOP: original", label, "point estimates do not reproduce."))
    list(frozen = frozen, max_abs_error = max(errors))
  }
  reconciled_cr <- reconcile(original_cr, frozen_cr, metrics[1:4], "CR")
  reconciled_life <- reconcile(original_life, frozen_life, metrics[5:7], "life")
  say("PHASE3 unified original point reconciliation PASS; actual intersection n=",
    nrow(patients), "; LM", paste(counts(patients), collapse = "/"))

  evaluate <- function(weights, point = FALSE) {
    result <- matrix(NA_real_, 6L, length(metrics), dimnames = list(NULL, metrics))
    identity_error <- rep(NA_real_, 6L)
    errors <- rep("", 6L)
    for (i in seq_along(specs)) {
      spec <- specs[[i]]
      local_weights <- weights[spec$indices]
      if (sum(local_weights) == 0) {
        errors[i] <- "NO_LANDMARK_PATIENTS"
        next
      }
      attempt <- tryCatch({
        aj <- evaluate_aj(spec$aj, weights)
        fail(all(is.finite(aj)), "NO_36_MONTH_AJ_TAIL_SUPPORT")
        # Row replication is the original patient bootstrap, and retains
        # multiplicities. KM is estimated independently by frozen survfit code.
        draw <- rep.int(seq_along(spec$indices), local_weights)
        observed <- env$observed_rmst(spec$time[draw], spec$event_os[draw])
        expected <- stats::weighted.mean(spec$expected, local_weights)
        vals <- c(aj, observed, expected, expected - observed)
        identity <- observed + aj[3L] + aj[4L] - tau / month
        fail(abs(identity) <= identity_tolerance,
          "INDEPENDENT_KM_AJ_TIME_DECOMPOSITION_FAILED")
        fail(all(is.finite(vals)), "NONFINITE_UNIFIED_ESTIMATE")
        list(values = vals, identity = identity)
      }, error = function(e) e)
      if (inherits(attempt, "error")) {
        errors[i] <- conditionMessage(attempt)
        if (point) stop(paste("Unified point failed at L", landmarks[i], ": ",
          errors[i], sep = ""), call. = FALSE)
      } else {
        result[i, ] <- attempt$values
        identity_error[i] <- attempt$identity
      }
    }
    list(values = result, identity_error = identity_error, errors = errors)
  }
  point <- evaluate(rep(1L, nrow(patients)), point = TRUE)
  values <- array(NA_real_, dim = c(6L, length(metrics), B),
    dimnames = list(NULL, metrics, NULL))
  errors <- matrix("", nrow = B, ncol = 6L)
  identity_max <- max(abs(point$identity_error))

  # Preserve caller RNG state; use one source-patient draw for every landmark,
  # every cause, independent observed KM, and the matched expected RMST.
  old_kind <- RNGkind()
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv)
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (had_seed) assign(".Random.seed", old_seed, envir = .GlobalEnv) else
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
        rm(".Random.seed", envir = .GlobalEnv)
  }, add = TRUE)
  RNGkind("L'Ecuyer-CMRG")
  set.seed(seed)
  stream <- get(".Random.seed", envir = .GlobalEnv)
  for (i in seq_len(stream_advance)) stream <- parallel::nextRNGStream(stream)
  assign(".Random.seed", stream, envir = .GlobalEnv)
  for (b in seq_len(B)) {
    draw <- sample.int(nrow(patients), nrow(patients), replace = TRUE)
    weights <- tabulate(draw, nbins = nrow(patients))
    fail(sum(weights) == nrow(patients), "Bootstrap multiplicity lost.")
    attempt <- evaluate(weights)
    values[, , b] <- attempt$values
    errors[b, ] <- attempt$errors
    valid_identity <- is.finite(attempt$identity_error)
    if (any(valid_identity)) identity_max <- max(identity_max,
      max(abs(attempt$identity_error[valid_identity])))
    if (b == 1L || b %% 100L == 0L || b == B)
      say("PHASE3 unified patient bootstrap", b, "/", B)
  }

  summary <- data.frame(landmark = landmarks, n = counts(patients),
    original_cr_n = counts(cr), original_life_n = counts(life),
    cr_not_life_n = counts(cr) - counts(patients),
    life_not_cr_n = counts(life) - counts(patients),
    gbc_events_36mo = vapply(specs, function(s)
      sum(s$aj$event == 1L), integer(1)),
    other_events_36mo = vapply(specs, function(s)
      sum(s$aj$event == 2L), integer(1)),
    at_36mo = vapply(specs, function(s) sum(s$time >= tau), integer(1)),
    identity_error_months = point$identity_error,
    bootstrap_attempts = B)
  for (k in seq_along(metrics)) {
    name <- metrics[k]
    summary[[name]] <- point$values[, k]
    summary[[paste0(name, "_lower95")]] <- NA_real_
    summary[[paste0(name, "_upper95")]] <- NA_real_
    summary[[paste0(name, "_bootstrap_valid")]] <-
      vapply(seq_along(landmarks), function(i)
        sum(is.finite(values[i, k, ])), integer(1))
    summary[[paste0(name, "_bootstrap_valid_fraction")]] <-
      summary[[paste0(name, "_bootstrap_valid")]] / B
    for (i in seq_along(landmarks)) {
      v <- values[i, k, ]
      # Do not silently condition inference on successful draws: the stricter
      # frozen CR rule (all attempted draws valid) is applied to all 7 metrics.
      if (mode == "formal" && all(is.finite(v))) {
        interval <- stats::quantile(v, c(.025, .975), names = FALSE, type = 7)
        summary[i, c(paste0(name, "_lower95"),
          paste0(name, "_upper95"))] <- interval
      }
    }
    original <- if (k <= 4L) reconciled_cr$frozen[[name]] else
      reconciled_life$frozen[[name]]
    summary[[paste0("original_", name)]] <- original
    difference <- point$values[, k] - original
    suffix <- if (k <= 2L) "_pp" else "_months"
    summary[[paste0("difference_", sub("_months$", "", name), suffix)]] <-
      difference * if (k <= 2L) 100 else 1
  }
  summary$bootstrap_valid_fraction <- vapply(seq_along(landmarks), function(i)
    mean(apply(is.finite(values[i, , , drop = FALSE]), 3L, all)), numeric(1))
  summary$status <- if (mode == "smoke") "SMOKE_CI_SUPPRESSED" else
    ifelse(summary$bootstrap_valid_fraction == 1, "PASS",
      "WARN_CI_UNAVAILABLE_INCOMPLETE_VALID_DRAWS")
  failures <- do.call(rbind, lapply(seq_along(landmarks), function(i) {
    table <- table(errors[nzchar(errors[, i]), i])
    if (!length(table)) return(NULL)
    data.frame(landmark = landmarks[i], reason = names(table), n = as.integer(table))
  }))
  if (is.null(failures)) failures <- data.frame(landmark = integer(),
    reason = character(), n = integer())
  max_differences <- setNames(vapply(seq_along(metrics), function(k) {
    original <- if (k <= 4L) reconciled_cr$frozen[[metrics[k]]] else
      reconciled_life$frozen[[metrics[k]]]
    max(abs(point$values[, k] - original)) * if (k <= 2L) 100 else 1
  }, numeric(1)), paste0(metrics, ifelse(seq_along(metrics) <= 2L,
    "_max_abs_difference_pp", "_max_abs_difference_months")))
  list(summary = summary, failures = failures,
    original_cr_reproduced = original_cr, original_life_reproduced = original_life,
    matching_qc = do.call(rbind, lapply(specs, `[[`, "matching_qc")),
    qc = list(original_cr_n = nrow(cr), original_life_n = nrow(life),
      actual_intersection_n = nrow(patients),
      original_cr_landmark_n = counts(cr), original_life_landmark_n = counts(life),
      intersection_landmark_n = counts(patients),
      original_cr_point_max_abs_error = reconciled_cr$max_abs_error,
      original_life_point_max_abs_error = reconciled_life$max_abs_error,
      max_abs_identity_error_months = identity_max,
      identity_tolerance_months = identity_tolerance,
      max_abs_differences = max_differences,
      event_partition_checked = TRUE, shared_fields_identical = TRUE,
      same_patient_draw_across_landmarks = TRUE,
      same_subset_for_all_seven_metrics = TRUE,
      observed_KM_independent_of_AJ = TRUE,
      life_table_uncertainty_resampled = FALSE,
      new_or_changed_eligibility_rules = FALSE),
    configuration = list(B = B, mode = mode, seed = seed,
      RNGkind = "L'Ecuyer-CMRG", stream_advance = stream_advance,
      horizon_months = 36, year_days = year, month_days = month,
      interval_method = "Pointwise percentile 2.5/97.5, type7; all attempts valid",
      source_order = "patient_id, stable ascending",
      reused_original_definitions = reuse))
}
