# Phase 2: exclude Summary Stage Distant only, retaining Unknown.
# This helper reads one JSON object from stdin and writes one aggregate JSON
# object to stdout. Patients and bootstrap draws remain in memory. No files are
# created here. Invoke Rscript --vanilla to prevent workspace saving.
#
# Original algorithms are preserved in scripts/current_kernels/lifetable_core.R.
# This helper retains the original Phase 2 evaluate/bootstrap body. The original
# measures/result_key/interval definitions omitted from that minimal kernel are
# retained verbatim below. Source inspection or parsing does not run this helper.
# Definitions needed for matching, integration and percentile intervals are
# extracted unchanged from the original R AST. The wrapper evaluates PRIMARY
# only, retaining the original patient draw shared across the six landmarks.

local({
  fail <- function(ok, text) {
    if (!isTRUE(ok)) stop(text, call. = FALSE)
    invisible(TRUE)
  }
  fail(as.character(getRversion()) == "4.4.3", "Use frozen R 4.4.3.")
  versions <- c(survival = "3.8.3", jsonlite = "2.0.0")
  for (package in names(versions)) {
    fail(requireNamespace(package, quietly = TRUE) &&
      utils::compareVersion(as.character(utils::packageVersion(package)),
        versions[[package]]) == 0,
      paste("Missing or mismatched package:", package))
  }

  input_connection <- file("stdin", open = "rt")
  payload <- jsonlite::fromJSON(paste(readLines(input_connection, warn = FALSE),
    collapse = "\n"), simplifyDataFrame = TRUE)
  close(input_connection)
  fail(is.list(payload) && is.character(payload$root) &&
    length(payload$root) == 1L, "Missing project root.")
  root <- normalizePath(payload$root, winslash = "/", mustWork = TRUE)
  fail(is.character(payload$code_root) && length(payload$code_root) == 1L,
    "Missing public code root.")
  code_root <- normalizePath(payload$code_root, winslash = "/", mustWork = TRUE)
  original_script <- file.path(code_root, "scripts/current_kernels/lifetable_core.R")
  fail(file.exists(original_script), "Original life-table source is missing.")

  parsed <- parse(file = original_script, keep.source = FALSE)
  fail(length(parsed) >= 1L && is.call(parsed[[1L]]) &&
    identical(parsed[[1L]][[1L]], as.name("<-")) &&
    identical(parsed[[1L]][[2L]], as.name("gbc_lifetable")),
    "Original life-table module assignment changed.")
  local_call <- parsed[[1L]][[3L]]
  fail(is.call(local_call) && identical(local_call[[1L]], as.name("local")),
    "Original life-table module container changed.")
  body <- local_call[[2L]]
  fail(is.call(body) && identical(body[[1L]], as.name("{")),
    "Original life-table body changed.")

  # Do not source the file: its setup/run/hash/export functions are never called.
  reuse <- c("CFG", "files", "frozen", "database_name", "reasons",
    "assert", "key", "match_status", "read_life_table",
    "match_patients", "expected_rmst", "observed_rmst")
  env <- new.env(parent = baseenv())
  extracted <- character()
  for (node in as.list(body)[-1L]) {
    if (is.call(node) && identical(node[[1L]], as.name("<-")) &&
      is.symbol(node[[2L]])) {
      name <- as.character(node[[2L]])
      if (name %in% reuse) {
        fail(!(name %in% extracted), "Duplicate original definition.")
        eval(node, envir = env)
        extracted <- c(extracted, name)
      }
    }
  }
  fail(setequal(extracted, reuse), "Required original definitions are missing.")
  # Exact original definitions absent from the isolated matching/RMST kernel.
  eval(quote(measures<-c("observed_RMST_months","expected_RMST_months","gap_months")), env)
  eval(quote(result_key<-function(z)paste(z$analysis_type,z$landmark,sep="|")), env)
  eval(quote(interval<-function(v) {
    valid<-is.finite(v)
    if(S$mode=="smoke"||mean(valid)<.95)return(c(NA_real_,NA_real_))
    as.numeric(stats::quantile(v[valid],c(.025,.975),names=FALSE,type=7))
  }), env)
  env$S <- new.env(parent = emptyenv())
  env$S$root <- root
  env$S$mode <- "formal"
  env$S$B <- 1000L
  env$say <- function(...) {
    cat(format(Sys.time(), "%H:%M:%S"), ..., "\n", file = stderr())
    flush(stderr())
  }
  fail(identical(env$CFG$landmarks, 0:5) && env$CFG$seed == 20260905L &&
    env$CFG$stream == 5L && env$CFG$B == 1000L &&
    env$CFG$year_days == 365.25 && env$CFG$month_days == 30.4375 &&
    env$CFG$tau_days == 1095.75, "Frozen life-table configuration differs.")

  required <- c("patient_id", "record_id", "year_dx", "age_dx", "sex",
    "survival_days_analysis", "event_os", "summary_stage_harmonized")
  validate_patients <- function(d, expected_n) {
    fail(is.data.frame(d) && nrow(d) == expected_n &&
      all(required %in% names(d)), "Patient count or required columns differ.")
    fail(!anyNA(d[required]) && !anyDuplicated(d$patient_id) &&
      !anyDuplicated(d$record_id), "Patient identifiers or required values invalid.")
    fail(all(is.finite(d$survival_days_analysis)) &&
      all(d$survival_days_analysis > 0) && all(d$event_os %in% 0:1) &&
      all(d$year_dx %in% 2004:2015) && all(d$age_dx >= 18 & d$age_dx < 90) &&
      all(d$sex %in% c("Female", "Male")),
      "All-cause life-table eligibility or follow-up values invalid.")
    d
  }
  original <- validate_patients(payload$original_patients, 3796L)
  patients <- validate_patients(payload$patients, 3592L)
  fail(sum(original$summary_stage_harmonized == "Distant") == 204L,
    "Original life-table Distant count is not 204.")
  retained <- original[original$summary_stage_harmonized != "Distant", , drop = FALSE]
  fail(nrow(retained) == 3592L &&
    all(patients$summary_stage_harmonized != "Distant"),
    "Sensitivity life-table exclusion rule differs.")
  for (name in required) {
    fail(identical(as.character(patients[[name]]),
      as.character(retained[[name]])),
      "Sensitivity patients, source ordering or unchanged fields differ.")
  }
  counts <- vapply(env$CFG$landmarks, function(s)
    sum(original$survival_days_analysis > s * env$CFG$year_days), integer(1))
  fail(identical(counts, c(3796L, 2469L, 1775L, 1420L, 1191L, 1048L)),
    "Original life-table L0-L5 counts differ; no eligibility changes allowed.")

  lt <- env$read_life_table()
  fail(nrow(lt) == 10800L && !anyDuplicated(lt$key),
    "All-races life-table key QC failed.")

  # This is the original evaluate() PRIMARY branch, with the same risk set,
  # matching, exact annual integration and observed all-cause KM calculation.
  evaluate_primary <- function(d, point = FALSE) {
    results <- qcs <- vector("list", 6L)
    for (i in seq_along(env$CFG$landmarks)) {
      s <- env$CFG$landmarks[i]
      z <- d[d$survival_days_analysis > s * env$CFG$year_days, , drop = FALSE]
      m <- env$match_patients(z, s, 0L, lt)
      qcs[[i]] <- m$qc
      # Every eligible patient is supported by the existing life table. Any
      # mismatch stops rather than silently changing this sensitivity subset.
      fail(m$qc$match_rate == 1, "STOP: life-table matching is not complete.")
      vals <- setNames(rep(NA_real_, 3L), env$measures)
      reason <- "OK"
      vals <- tryCatch({
        matched <- z[m$mask, , drop = FALSE]
        expected <- env$expected_rmst(m$p[m$mask, , drop = FALSE])
        fail(length(expected) == nrow(matched), "Observed/expected subset mismatch.")
        observed <- env$observed_rmst(
          matched$survival_days_analysis - s * env$CFG$year_days,
          matched$event_os)
        setNames(c(observed, mean(expected), mean(expected) - observed), env$measures)
      }, error = function(e) {
        reason <<- paste("NOT ESTIMATED:", conditionMessage(e))
        setNames(rep(NA_real_, 3L), env$measures)
      })
      if (point) fail(all(is.finite(vals)), "Point RMST could not be estimated.")
      results[[i]] <- cbind(data.frame(landmark = s,
        analysis_type = "PRIMARY", n = m$qc$matched_n,
        match_rate = m$qc$match_rate, match_status = m$qc$status,
        status = reason,
        allcause_events_3y = sum(z$event_os[m$mask] == 1 &
          z$survival_days_analysis[m$mask] - s * env$CFG$year_days <= env$CFG$tau_days),
        at_3y = sum(z$survival_days_analysis[m$mask] -
          s * env$CFG$year_days >= env$CFG$tau_days)),
        as.data.frame(as.list(vals)))
    }
    list(results = do.call(rbind, results), qc = do.call(rbind, qcs))
  }
  original_point <- evaluate_primary(original, point = TRUE)
  reference <- payload$frozen_original_points
  fail(is.data.frame(reference) && nrow(reference) == 6L &&
    all(c("landmark", env$measures) %in% names(reference)) &&
    identical(as.integer(reference$landmark), 0:5),
    "Six frozen original PRIMARY point estimates are required before bootstrap.")
  differences <- abs(as.matrix(original_point$results[env$measures]) -
    as.matrix(reference[env$measures]))
  fail(all(is.finite(differences)) && max(differences) <= 1e-8,
    "STOP: original life-table point estimates do not reconcile with frozen results.")
  point <- evaluate_primary(patients, point = TRUE)
  env$say("PHASE2 LIFE-TABLE original point reconciliation PASS; sensitivity n=3592.")

  # Same initialization and sample.int draw as original bootstrap(), with
  # exactly 1000 attempts; failed attempts are never replaced or redrawn.
  RNGkind("L'Ecuyer-CMRG")
  set.seed(env$CFG$seed)
  stream <- get(".Random.seed", envir = .GlobalEnv)
  for (i in seq_len(env$CFG$stream)) stream <- parallel::nextRNGStream(stream)
  assign(".Random.seed", stream, envir = .GlobalEnv)
  values <- array(NA_real_, c(6L, 3L, env$S$B),
    dimnames = list(env$result_key(point$results), env$measures, NULL))
  errors <- character(env$S$B)
  for (b in seq_len(env$S$B)) {
    draw <- sample.int(nrow(patients), nrow(patients), replace = TRUE)
    z <- patients[draw, , drop = FALSE]
    fail(nrow(z) == nrow(patients), "Bootstrap multiplicity lost.")
    ev <- tryCatch(evaluate_primary(z), error = function(e) e)
    if (inherits(ev, "error")) {
      errors[b] <- conditionMessage(ev)
    } else {
      fail(identical(env$result_key(ev$results), env$result_key(point$results)),
        "Bootstrap landmark layout changed.")
      values[, , b] <- as.matrix(ev$results[env$measures])
    }
    if (b == 1L || b %% 100L == 0L || b == env$S$B)
      env$say("PHASE2 LIFE-TABLE patient bootstrap", b, "/", env$S$B)
  }
  summary <- point$results
  prefixes <- c("observed", "expected", "gap")
  for (k in seq_along(env$measures)) {
    summary[[paste0(prefixes[k], "_lower95")]] <- NA_real_
    summary[[paste0(prefixes[k], "_upper95")]] <- NA_real_
    summary[[paste0(prefixes[k], "_valid_fraction")]] <-
      rowMeans(is.finite(values[, k, ]))
    for (i in seq_len(nrow(summary))) {
      ci <- env$interval(values[i, k, ])
      summary[i, c(paste0(prefixes[k], "_lower95"),
        paste0(prefixes[k], "_upper95"))] <- ci
    }
  }
  summary$bootstrap_attempts <- env$S$B
  summary$bootstrap_valid_fraction <- summary$gap_valid_fraction
  summary$bootstrap_failure_fraction <- 1 - summary$bootstrap_valid_fraction
  for (i in seq_len(nrow(summary))) {
    summary$status[i] <- if (summary$bootstrap_valid_fraction[i] < .95)
      paste(summary$match_status[i], "/ CI UNAVAILABLE: <95% VALID") else
      summary$match_status[i]
  }
  result <- list(
    point = point$results,
    summary = summary,
    original_point = original_point$results,
    matching_qc = point$qc,
    qc = list(original_n = nrow(original), original_distant_n = 204L,
      sensitivity_n = nrow(patients), original_landmark_n = unname(counts),
      sensitivity_landmark_n = unname(point$results$n),
      original_point_max_abs_difference = max(differences),
      life_table_export_rows = 54000L, life_table_unique_allraces_keys = nrow(lt),
      unknown_equals_other_unspecified = TRUE,
      whole_draw_failures = sum(nzchar(errors)),
      same_patient_draw_across_landmarks = TRUE,
      same_matched_subset_for_observed_and_expected = TRUE,
      life_table_sampling_uncertainty_included = FALSE),
    seed = env$CFG$seed, B = env$S$B, RNGkind = RNGkind(),
    stream_advance = env$CFG$stream,
    interval_method = "pointwise percentile 2.5/97.5; type=7; >=95% valid attempts",
    versions = list(R = as.character(getRversion()),
      survival = as.character(utils::packageVersion("survival")),
      jsonlite = as.character(utils::packageVersion("jsonlite"))),
    reused_definitions = reuse,
    scope = "PRIMARY calendar keys only; exclude Summary Distant; retain Unknown")
  cat(jsonlite::toJSON(result, auto_unbox = TRUE, dataframe = "rows", na = "null",
    null = "null", digits = 16), "\n", sep = "")
})
