#!/usr/bin/env Rscript
# Data-free parsing, with optional private-original source correspondence.
# Never source an analysis, open patient data, create output or fit a model.
args <- commandArgs(trailingOnly = TRUE)
files <- list.files(".", pattern = "[.][Rr]$", recursive = TRUE, full.names = TRUE)
invisible(lapply(files, function(path) parse(file = path, keep.source = FALSE)))
cat("PASS: R source parse; files=",length(files),"; no analysis executed\n",sep="")
if ("--path-guards" %in% args) {
  # Source configuration definitions only, not an analysis entry point.
  e <- new.env(parent = .GlobalEnv)
  sys.source("scripts/current_kernels/public_config.R", envir = e)
  keys <- c("GBC_CODE_ROOT","GBC_FINAL_RUN_ROOT","GBC_PREPARATION_ROOT","GBC_OUTPUT_ROOT","GBC_PYTHON")
  previous <- Sys.getenv(keys,unset=NA_character_)
  restore <- function() for (i in seq_along(keys)) {
    if (is.na(previous[i])) Sys.unsetenv(keys[i]) else do.call(Sys.setenv,setNames(list(previous[i]),keys[i]))
  }
  local({
    on.exit(restore())
    Sys.setenv(GBC_CODE_ROOT=normalizePath("."),GBC_FINAL_RUN_ROOT=normalizePath("."),
      GBC_PREPARATION_ROOT=normalizePath("."),GBC_OUTPUT_ROOT=normalizePath("."),GBC_PYTHON="configured-test-interpreter")
    blocked <- try(e$gbc_runtime(),silent=TRUE)
    stopifnot(inherits(blocked,"try-error"))
    Sys.setenv(GBC_OUTPUT_ROOT=normalizePath(tempdir()))
    stopifnot(identical(e$gbc_runtime()$output,normalizePath(tempdir(),winslash="/")))
    blocked <- try(e$gbc_export_aggregate(NULL,normalizePath(".")),silent=TRUE)
    stopifnot(inherits(blocked,"try-error"))
    allowed <- file.path(normalizePath(tempdir(),winslash="/"),"guard_check_no_file_created.pdf")
    stopifnot(identical(e$gbc_new_output_path(allowed),allowed),!file.exists(allowed))
    blocked <- try(e$gbc_new_output_path(file.path(normalizePath("."),"not_created.pdf")),silent=TRUE)
    stopifnot(inherits(blocked,"try-error"))
    blocked <- try(e$gbc_new_output_path(normalizePath(tempdir())),silent=TRUE)
    stopifnot(inherits(blocked,"try-error"))
    f <- new.env(parent=.GlobalEnv)
    sys.source("R/10_figures/current_figure3.R",envir=f)
    stopifnot(identical(f$figure3_output_path(allowed),allowed),!file.exists(allowed))
    cat("PASS: protected-output, Figure3 and no-overwrite guards; no files written\n")
  })
}
definitions <- function(nodes) {
  out <- list()
  for (node in nodes) if (is.call(node) && identical(node[[1]],as.name("<-")) && is.symbol(node[[2]]))
    out[[as.character(node[[2]])]] <- node
  out
}
if ("--compare-original" %in% args) {
  original <- Sys.getenv("GBC_FINAL_RUN_ROOT", "")
  if (!nzchar(original)) stop("Set GBC_FINAL_RUN_ROOT to private original source/input tree")
  parse_source <- function(path) parse(file=path,keep.source=FALSE)
  a <- definitions(parse_source(file.path(original,"scripts/run_development.R")))
  b <- definitions(parse_source("scripts/current_kernels/cause_specific.R"))
  wanted <- c("assert","fit_failure","cox_checked","baseline_information","integrate_grid")
  stopifnot(all(vapply(wanted,function(k)identical(a[[k]],b[[k]]),logical(1))))
  cat("PASS: five original Cox/CIF definitions AST-identical\n")
  stopifnot(identical(parse_source(file.path(original,"phase3_l0_ph_check/L0_model_core.R")),
    parse_source("phase3_l0_ph_check/L0_model_core.R")))
  cat("PASS: complete L0 model core AST-identical\n")
  container_definitions <- function(path) {
    nodes <- parse_source(path)
    definitions(as.list(nodes[[1]][[3]][[2]])[-1L])
  }
  a <- container_definitions(file.path(original,"scripts/05_lifetable_rmst_gap.R"))
  b <- container_definitions("scripts/current_kernels/lifetable_core.R")
  wanted <- c("CFG","files","frozen","database_name","reasons","assert","key",
    "match_status","read_life_table","match_patients","expected_rmst","observed_rmst")
  stopifnot(all(vapply(wanted,function(k)identical(a[[k]],b[[k]]),logical(1))))
  cat("PASS: twelve original life-table definitions AST-identical\n")
}
