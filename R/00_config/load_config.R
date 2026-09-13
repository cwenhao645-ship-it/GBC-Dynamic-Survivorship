# Path configuration only. Does not source or execute an analysis module.
load_gbc_config <- function(path) {
  if (!requireNamespace("yaml", quietly = TRUE)) stop("Install yaml before loading path configuration.")
  cfg <- yaml::read_yaml(path)
  keys <- c(project_root="GBC_FINAL_RUN_ROOT", code_root="GBC_CODE_ROOT",
    preparation_root="GBC_PREPARATION_ROOT", seer_mapping="GBC_SEER_MAPPING",
    python="GBC_PYTHON", runtime_root="GBC_RUNTIME_ROOT", user_library_root="GBC_USER_LIBRARY_ROOT")
  for (key in names(keys)) {
    value <- cfg[[key]]
    if (!is.character(value) || length(value)!=1L || !nzchar(value) || grepl("[<>]",value))
      stop("Unconfigured private path: ",key)
    do.call(Sys.setenv, setNames(list(value),keys[[key]]))
  }
  optional <- c(submission_output = "GBC_SUBMISSION_OUTPUT", figure3_source = "GBC_FIGURE3_SOURCE")
  for (key in names(optional)) {
    value <- cfg[[key]]
    if (!is.null(value)) {
      if (!is.character(value) || length(value) != 1L || !nzchar(value) ||
          grepl("[<>]", value) || startsWith(value, "/path/to/"))
        stop("Unconfigured output path: ", key)
      do.call(Sys.setenv, setNames(list(value), optional[[key]]))
    }
  }
  if (as.character(getRversion())!="4.4.3") stop("The study requires R 4.4.3.")
  invisible(cfg)
}
