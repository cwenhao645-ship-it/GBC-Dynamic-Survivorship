# Public runtime configuration; sourcing is read-only and never starts analysis.
gbc_code_root <- function() {
  configured <- Sys.getenv('GBC_CODE_ROOT', '')
  if (nzchar(configured)) return(normalizePath(configured, winslash = '/', mustWork = TRUE))
  files <- unlist(lapply(sys.frames(), function(f) f$ofile))
  arg <- grep('^--file=', commandArgs(FALSE), value = TRUE)
  if (length(arg)) files <- c(files, sub('^--file=', '', arg[1]))
  candidates <- unique(c(getwd(), dirname(files), dirname(dirname(files)), dirname(dirname(dirname(files)))))
  candidates <- candidates[!is.na(candidates) & nzchar(candidates)]
  for (p in candidates) if (file.exists(file.path(p, 'scripts/current_kernels/cause_specific.R')))
    return(normalizePath(p, winslash = '/', mustWork = TRUE))
  stop('Set GBC_CODE_ROOT to the public checkout root.', call. = FALSE)
}
gbc_runtime <- function(require_data = TRUE) {
  code <- gbc_code_root()
  data <- Sys.getenv('GBC_FINAL_RUN_ROOT', '')
  preparation <- Sys.getenv('GBC_PREPARATION_ROOT', '')
  output <- Sys.getenv('GBC_OUTPUT_ROOT', '')
  python <- Sys.getenv('GBC_PYTHON', Sys.which('python'))
  if (require_data && (!nzchar(data) || !nzchar(preparation)))
    stop('Set GBC_FINAL_RUN_ROOT and GBC_PREPARATION_ROOT to your authorized private input roots.', call. = FALSE)
  if (require_data && (!nzchar(output) || !nzchar(python)))
    stop('Set GBC_OUTPUT_ROOT outside this repository and GBC_PYTHON if python is not on PATH.', call. = FALSE)
  if (nzchar(output)) {
    if (!dir.exists(output))
      stop('Create an empty private GBC_OUTPUT_ROOT outside the checkout before running.', call. = FALSE)
    resolved <- normalizePath(output, winslash = '/', mustWork = TRUE)
    protected <- c(code, data, preparation)
    protected <- protected[nzchar(protected)]
    protected <- vapply(protected, normalizePath, '', winslash = '/', mustWork = TRUE)
    inside <- vapply(protected, function(p) identical(tolower(resolved),tolower(p)) ||
      startsWith(tolower(resolved),paste0(tolower(p),'/')), logical(1))
    if (any(inside))
      stop('GBC_OUTPUT_ROOT must be outside the public checkout and frozen input roots.', call. = FALSE)
    output <- resolved
  }
  list(code = code, data = data, preparation = preparation, output = output, python = python)
}
gbc_export_aggregate <- function(value, path) {
  if (file.exists(path)) stop('Output destination already exists; choose a new private output root.', call. = FALSE)
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  saveRDS(value, file.path(path, 'aggregate_results.rds'))
  jsonlite::write_json(value, file.path(path, 'aggregate_results.json'), dataframe = 'rows',
    auto_unbox = TRUE, na = 'null', digits = NA, pretty = TRUE)
  invisible(path)
}
gbc_new_output_path <- function(path) {
  cfg <- gbc_runtime(require_data = FALSE)
  if (!nzchar(cfg$output)) stop('Set an existing private GBC_OUTPUT_ROOT before exporting.', call. = FALSE)
  parent <- normalizePath(dirname(path), winslash = '/', mustWork = TRUE)
  if (!dir.exists(parent)) stop('Create the private output parent directory before exporting.', call. = FALSE)
  resolved <- file.path(parent, basename(path))
  if (!(identical(tolower(parent),tolower(cfg$output)) ||
      startsWith(tolower(parent),paste0(tolower(cfg$output),'/'))))
    stop('Display output must be inside the configured protected output root.', call. = FALSE)
  if (file.exists(resolved)) stop('Display output already exists; choose a new output file.', call. = FALSE)
  resolved
}
