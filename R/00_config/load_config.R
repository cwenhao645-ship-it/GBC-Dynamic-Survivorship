# Optional YAML-to-environment adapter only; never sources analysis.
load_gbc_config <- function(path) {
  if (!requireNamespace("yaml",quietly=TRUE)) stop("yaml is required for this optional adapter.")
  cfg <- yaml::read_yaml(path)
  required <- c(project_root="GBC_FINAL_RUN_ROOT",code_root="GBC_CODE_ROOT",
    preparation_root="GBC_PREPARATION_ROOT",output_root="GBC_OUTPUT_ROOT",python="GBC_PYTHON")
  optional <- c(seer_mapping="GBC_SEER_MAPPING",submission_output="GBC_SUBMISSION_OUTPUT",
    runtime_root="GBC_RUNTIME_ROOT",user_library_root="GBC_USER_LIBRARY_ROOT")
  for (key in c(names(required),names(optional))) {
    value <- cfg[[key]]
    if (is.null(value) && key %in% names(optional)) next
    if (!is.character(value) || length(value)!=1L || !nzchar(value) ||
        grepl("[<>]",value) || startsWith(value,"/path/to/"))
      stop("Unconfigured private path: ",key,call.=FALSE)
    variable <- if (key %in% names(required)) required[[key]] else optional[[key]]
    do.call(Sys.setenv,setNames(list(value),variable))
  }
  if (as.character(getRversion())!="4.4.3") stop("The study requires R4.4.3.")
  invisible(cfg)
}
