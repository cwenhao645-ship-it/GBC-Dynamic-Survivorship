# Publication source copy. See docs/original_script_mapping.md and reproducibility_notes.md.
root <- Sys.getenv("GBC_FINAL_RUN_ROOT", unset = getwd())
stopifnot(as.character(getRversion()) == "4.4.3")
cols <- c("record_id", "year_dx", "descriptive_source_flag", "vital_raw",
          "event_os", "event_competing", "survival_days_numeric",
          "survival_days_analysis", "zero_day_survival_flag")
d <- as.data.frame(arrow::read_parquet(file.path(root,"data/analysis_patient_level_v2.parquet"),
                                     col_select=tidyselect::all_of(cols)))
stopifnot(nrow(d)==7007L, !anyDuplicated(d$record_id), !anyNA(d),
          all(d$year_dx>=2004 & d$year_dx<=2023),
          all(d$vital_raw %in% c("Alive","Dead")),
          all(d$event_os==as.integer(d$vital_raw=="Dead")),
          all((d$event_competing==0)==(d$vital_raw=="Alive")),
          all(d$survival_days_analysis>0),
          all(d$survival_days_analysis[d$zero_day_survival_flag]==0.5),
          all(d$survival_days_numeric[d$zero_day_survival_flag]==0),
          all(d$survival_days_analysis[!d$zero_day_survival_flag]==
              d$survival_days_numeric[!d$zero_day_survival_flag]),
          sum(d$descriptive_source_flag)==3918L,
          all(d$descriptive_source_flag==(d$year_dx>=2004 & d$year_dx<=2015)))
summarize_followup <- function(z,label) {
  fit <- survival::survfit(survival::Surv(survival_days_analysis/365.25,
                                        vital_raw=="Alive")~1,
                           data=z, conf.type="log-log", conf.int=0.95)
  med <- summary(fit)$table[c("median","0.95LCL","0.95UCL")]
  stopifnot(all(is.finite(med)),med[2]<=med[1],med[1]<=med[3])
  data.frame(Population=label,n=nrow(z),Reverse_KM_median_years=unname(med[1]),
             Lower95=unname(med[2]),Upper95=unname(med[3]),
             Total_person_years=sum(z$survival_days_analysis)/365.25)
}
ans <- rbind(summarize_followup(d,"2004-2023 competing-risk source cohort"),
             summarize_followup(d[d$descriptive_source_flag,],"2004-2015 dynamic survivorship cohort"))
utils::write.csv(ans,file.path(root,"results/followup_summary.csv"),row.names=FALSE)
print(ans,row.names=FALSE,digits=12)
cat("QA PASS: frozen membership; all vital-status mappings verified; zero-day rule preserved.\n")


