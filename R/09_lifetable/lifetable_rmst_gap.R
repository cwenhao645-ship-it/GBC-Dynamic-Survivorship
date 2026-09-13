# Publication source copy. See docs/original_script_mapping.md and reproducibility_notes.md.

gbc_lifetable <- local({
  S<-new.env(parent=emptyenv())
  CFG<-list(seed=20260905L,stream=5L,B=1000L,year_days=365.25,month_days=30.4375,
    tau_days=1095.75,landmarks=0:5,verification_date="2026-09-09")
  files<-c(txt="data_external/US_Annual_ExpectedSurvival_1970_2023.txt",
    dic="data_external/US_Annual_ExpectedSurvival_1970_2023.dic",
    precursor="private/preparation/data_clean/01_gallbladder_harmonized_all_2004_2023.parquet",
    main="data/analysis_patient_level_v2.parquet",sap="spec/SAP_TECHNICAL_ADDENDUM_v1.1.md")
  frozen<-c(txt="e7236cabb05fd77810b047a7295339b46f885aed0eeb2e3f8244b2eb02ce02e5",
    dic="a431d992dfa9b14cbf331a292db587a193bd6372d5e609c92e1fb6e5df377433",
    precursor="9bb26be6114084b7a3c41ceea5d09bf444121c9442ba42eda1a4f399b7eec237",
    main="b8bb4d6d7a5c00924aedd9383c3be4ba22c7b0c1060d72288be64207d88fd870",
    sap="9a5e363afb395fe86d12ddc94817b4d727af74dae0dc27946acb6d00c79c328d")
  database_name<-paste0("Expected Survival - U.S. 1970-2023 by individual year ",
    "(White, Black, Other (AI/API), Ages 0-99, All races for Other Unspec 1991+ and Unknown)")
  sheet_names<-c("life_table_metadata","matching_qc","rmst_gap","landmark_changes","yearshift_sensitivity","plot_ready")
  measures<-c("observed_RMST_months","expected_RMST_months","gap_months")
  reasons<-c("missing_age","missing_sex","missing_year_key","missing_age_key","duplicate_key","invalid_probability","other")
  source_files<-unlist(lapply(sys.frames(),function(f)f$ofile))
  S$script<-if(length(source_files))utils::tail(source_files,1) else NA_character_
  assert<-function(ok,message) {if(!isTRUE(ok))stop(message,call.=FALSE);invisible(TRUE)}
  say<-function(...) {cat(format(Sys.time(),"%H:%M:%S"),...,"\n");flush.console()}
  key<-function(age,year,sex)paste(age,year,sex,sep="|")
  result_key<-function(z)paste(z$analysis_type,z$landmark,sep="|")
  match_status<-function(rate)if(!is.finite(rate)||rate<.9)"MODULE NO-GO" else if(rate<.95)"EXPLORATORY" else "REPORTABLE"
  hashes<-function() {
    h<-vapply(files,function(p)digest::digest(file=file.path(S$root,p),algo="sha256"),character(1))
    assert(identical(unname(h),unname(frozen)),"STOP: frozen TXT/DIC/precursor/main/SAP hash mismatch.")
    invisible(h)
  }
  setup<-function(mode) {
    S$mode<-match.arg(mode,c("formal","smoke"));S$B<-if(S$mode=="smoke")3L else CFG$B
    roots<-c(if(!is.na(S$script))dirname(dirname(normalizePath(S$script,winslash="/"))),
      Sys.getenv("GBC_FINAL_RUN_ROOT"),getwd(),dirname(getwd()))
    usable<-vapply(roots,function(p)nzchar(p)&&file.exists(file.path(p,files[["sap"]])),logical(1))
    assert(any(usable),"Cannot locate project; Source this script by its full path or set GBC_FINAL_RUN_ROOT.")
    S$root<-normalizePath(roots[which(usable)[1]],winslash="/",mustWork=TRUE)
    assert(as.character(getRversion())=="4.4.3","Use the frozen R 4.4.3 runtime.")
    versions<-c(survival="3.8.3",jsonlite="2.0.0",digest="0.6.37",processx="3.8.6")
    for(p in names(versions))assert(requireNamespace(p,quietly=TRUE)&&
      utils::compareVersion(as.character(utils::packageVersion(p)),versions[[p]])==0,paste("Missing/mismatched package:",p))
    hashes()
    runtime<-Sys.getenv("GBC_RUNTIME_ROOT")
    S$node<-file.path(runtime,"node/bin/node.exe");S$modules<-file.path(runtime,"node/node_modules")
    S$python<-Sys.getenv("GBC_PYTHON")
    S$verify_python<-file.path(runtime,"python/python.exe")
    for(p in c(S$node,S$modules,S$python,S$verify_python))assert(file.exists(p),paste("Missing installed dependency:",p))
    S$paths<-file.path(S$root,"outputs",c("LIFETABLE_RESULTS.xlsx","LIFETABLE_REPORT.md"))
    if(S$mode=="formal")assert(!any(file.exists(S$paths)),"Formal outputs already exist; refusing overwrite.")
    say(toupper(S$mode),"LIFE-TABLE RMST GAP:",S$B,"bootstrap attempts.")
  }
  read_life_table<-function() {
    dic<-readLines(file.path(S$root,files[["dic"]]),warn=FALSE,encoding="UTF-8")
    assert(any(dic==paste0("Database name=",database_name))&&any(dic=="Field delimiter=tab")&&
      any(dic=="Var5Name=Expected rate")&&any(dic=="Var5DisplayType=Unformatted"),"STOP: official dictionary schema changed.")
    d<-utils::read.delim(file.path(S$root,files[["txt"]]),header=TRUE,sep="\t",quote="\"",
      check.names=FALSE,stringsAsFactors=FALSE,colClasses=c("integer","integer","character","character","numeric"))
    fields<-c("Age","Year","Race recode (White, Black, Other)","Sex","Expected rate")
    races<-c("White","Black","Other (American Indian/AK Native, Asian/Pacific Islander)","Other unspecified (1991+)","Unknown")
    assert(identical(dim(d),c(54000L,5L))&&identical(names(d),fields)&&!anyNA(d)&&
      setequal(unique(d[[fields[3]]]),races),"STOP: official life-table shape/fields/categories/missing values failed.")
    assert(all(d[["Expected rate"]]>0 & d[["Expected rate"]]<=1e6),"STOP: invalid expected annual survivors per million.")
    take<-function(race) {
      z<-d[d[[fields[3]]]==race,c("Age","Year","Sex","Expected rate")]
      z<-z[order(z$Age,z$Year,z$Sex),];rownames(z)<-NULL;z
    }
    z<-take("Unknown");other<-take("Other unspecified (1991+)")
    assert(nrow(z)==10800L&&identical(z,other),"STOP: Unknown vs Other unspecified differs; cannot infer all-races table.")
    assert(identical(sort(unique(z$Age)),0:99)&&identical(sort(unique(z$Year)),1970:2023)&&
      setequal(unique(z$Sex),c("Male","Female")),"STOP: all-races age/year/sex coverage failed.")
    z$p<-z[["Expected rate"]]/1e6;z$q<-1-z$p;z$key<-key(z$Age,z$Year,z$Sex)
    assert(!anyDuplicated(z$key)&&all(z$p>0&z$p<=1)&&all(z$q>=0&z$q<1),"STOP: duplicate keys or invalid p/q.")
    S$metadata<-data.frame(source="NCI SEER official SEER*Stat Case Listing export",database_name=database_name,
      official_url="https://seer.cancer.gov/expsurvival/",official_update="February 2026",
      semantics_url="https://seer.cancer.gov/seerstat/faq.html",
      filename=basename(files[["txt"]]),dictionary_filename=basename(files[["dic"]]),
      sha256=frozen[["txt"]],dictionary_sha256=frozen[["dic"]],
      download_date="Not supplied; user provided export; filesystem date is not a download date",
      verification_date=CFG$verification_date,run_date=as.character(Sys.Date()),rows=54000L,rows_used=nrow(z),
      column_names=paste(fields,collapse="; "),age_min=min(z$Age),age_max=max(z$Age),unique_ages=length(unique(z$Age)),
      year_min=min(z$Year),year_max=max(z$Year),unique_years=length(unique(z$Year)),sex_levels="Female; Male",unique_sex=2L,
      probability_field="Expected rate",probability_definition="Annual survivors conditional on alive at interval start; p=Expected rate/1000000; q=1-p",
      expected_rate_scale="per 1,000,000 annual conditional survivors",key_definition="Age x Year x Sex",key_unique=TRUE,
      unknown_vs_other_unspecified_identical=TRUE,analysis_race_mode="ALL_RACES_COMBINED_FROM_UNKNOWN_ROWS",
      missing_values=sum(is.na(z)),invalid_p_values=sum(!is.finite(z$p)|z$p<=0|z$p>1),
      precursor_sha256=frozen[["precursor"]],sap_sha256=frozen[["sap"]],
      seed=CFG$seed,rng_stream_advance=CFG$stream,bootstrap_attempts=S$B,mode=S$mode)
    say("Life table QC PASS: 54000 exported rows; 10800 unique all-races keys; Unknown equals Other unspecified.")
    z
  }
  read_source<-function() {
    code<-r"---(import json,sys
from pathlib import Path
import pyarrow.parquet as pq
root=Path(sys.argv[1])
cols=['patient_id','record_id','gallbladder_site_flag','malignant_flag','year_dx','age_dx','strict_8140_flag','histology_confirmed','international_primary_flag','strict_resection_flag','M_harmonized','survival_days_numeric','event_os','unknown_cod_flag','age_90plus_flag','survival_days_analysis','sex']
d=pq.read_table(root/'private/preparation/data_clean/01_gallbladder_harmonized_all_2004_2023.parquet',columns=cols).to_pandas()
eligible=(d.gallbladder_site_flag & d.malignant_flag & d.year_dx.between(2004,2023) & d.age_dx.ge(18) & d.strict_8140_flag & d.histology_confirmed & d.international_primary_flag & d.strict_resection_flag & d.M_harmonized.eq('M0') & d.survival_days_numeric.ge(0) & d.event_os.isin([0,1]))
a=d.loc[eligible]
assert len(a)==7100 and a.patient_id.is_unique and int(a.unknown_cod_flag.sum())==93
main=pq.read_table(root/'data/analysis_patient_level_v2.parquet',columns=['record_id']).to_pandas()
assert len(main)==7007 and set(a.loc[~a.unknown_cod_flag,'record_id'])==set(main.record_id)
s=a.loc[a.year_dx.between(2004,2015) & ~a.age_90plus_flag].sort_values('patient_id',kind='stable')
assert len(s)==3796 and (s.age_dx<90).all()
out=s[['patient_id','record_id','year_dx','age_dx','sex','survival_days_analysis','event_os','unknown_cod_flag']]
print(json.dumps(dict(precursor_n=len(a),unresolved_n=int(a.unknown_cod_flag.sum()),patient=json.loads(out.to_json(orient='records'))),separators=(',',':')))
)---"
    r<-processx::run(S$python,c("-c",code,S$root),stdout="|",stderr="|",windows_hide_window=TRUE,error_on_status=TRUE)
    obj<-jsonlite::fromJSON(r$stdout);d<-obj$patient
    assert(nrow(d)==3796L&&!anyDuplicated(d$patient_id)&&!anyNA(d[c("survival_days_analysis","event_os")])&&
      all(d$survival_days_analysis>0)&&all(d$event_os %in% 0:1),"STOP: source identifiers or all-cause follow-up invalid.")
    counts<-vapply(CFG$landmarks,function(s)sum(d$survival_days_analysis>s*CFG$year_days),integer(1))
    assert(identical(counts,c(3796L,2469L,1775L,1420L,1191L,1048L)),"STOP: frozen L0-L5 counts differ; do not change eligibility.")
    S$source_n<-nrow(d);S$source_unresolved_n<-sum(d$unknown_cod_flag);S$cohort_n<-counts
    say("Source QC PASS: 7100 precursor / 93 unresolved retained; 3796 source; L0-L5",paste(counts,collapse="/"))
    d
  }
  match_patients<-function(d,s,shift,lt) {
    n<-nrow(d);prob<-matrix(NA_real_,n,3);why<-rep("",n);capped<-rep(FALSE,n)
    duplicates<-unique(lt$key[duplicated(lt$key)|duplicated(lt$key,fromLast=TRUE)])
    for(j in 0:2) {
      age<-floor(d$age_dx+s+j);year<-d$year_dx+s+j+shift
      capped<-capped|(!is.na(age)&age>99);age<-pmin(age,99)
      k<-key(age,year,d$sex);idx<-match(k,lt$key);p<-lt$p[idx];why_j<-rep("",n)
      tag<-function(test,label) {test[is.na(test)]<-FALSE;why_j[test&why_j==""]<<-label}
      tag(!is.finite(age),"missing_age");tag(is.na(d$sex)|!(d$sex %in% c("Male","Female")),"missing_sex")
      tag(!is.finite(year)|!(year %in% lt$Year),"missing_year_key")
      tag(is.finite(age)&!(age %in% lt$Age),"missing_age_key")
      tag(k %in% duplicates,"duplicate_key");tag(is.na(idx),"other")
      tag(!is.finite(p)|p<=0|p>1,"invalid_probability")
      why[why==""&why_j!=""]<-why_j[why==""&why_j!=""]
      prob[,j+1L]<-p
    }
    mask<-why=="";rate<-if(n)mean(mask) else NA_real_
    qc<-data.frame(landmark=s,analysis_type=if(shift==0)"PRIMARY" else "YEAR_PLUS_1",eligible_n=n,
      matched_n=sum(mask),unmatched_n=sum(!mask),match_rate=rate,status=match_status(rate),age99_capped_n=sum(capped))
    for(r in reasons)qc[[r]]<-sum(why==r)
    assert(sum(qc[reasons])==qc$unmatched_n,"Unmatched reasons do not reconcile.")
    list(mask=mask,p=prob,qc=qc,reason=why)
  }
  expected_rmst<-function(p) {
    assert(is.matrix(p)&&ncol(p)==3&&!anyNA(p)&&all(p>0&p<=1),"Invalid three-segment survival probabilities.")
    surv<-rep(1,nrow(p));area<-rep(0,nrow(p))
    for(j in 1:3) {
      lambda<--log(p[,j]);factor<-rep(1,nrow(p));pos<-lambda>0
      factor[pos]<--expm1(-lambda[pos])/lambda[pos]
      area<-area+surv*factor;surv<-surv*p[,j]
    }
    result<-12*area
    assert(all(is.finite(result))&&all(result>0&result<=36+1e-10),"Expected RMST outside its allowed range.")
    result
  }
  observed_rmst<-function(time,event) {
    assert(length(time)>0&&length(time)==length(event)&&all(is.finite(time))&&all(time>0)&&all(event %in% 0:1),"Invalid matched all-cause observations.")
    x<-data.frame(time=pmin(time,CFG$tau_days),death=as.integer(event==1&time<=CFG$tau_days))
    fit<-survival::survfit(survival::Surv(time,death)~1,data=x,se.fit=FALSE,conf.int=FALSE)
    assert(max(time)>=CFG$tau_days||utils::tail(fit$surv,1)==0,"KM has no three-year tail support; no extrapolation.")
    at<-fit$time<=CFG$tau_days
    area<-sum(diff(c(0,fit$time[at],CFG$tau_days))*c(1,fit$surv[at]))
    value<-area/CFG$month_days
    assert(is.finite(value)&&value>=0&&value<=36+1e-10,"Observed RMST integration failed.")
    value
  }
  evaluate<-function(d,lt,point=FALSE) {
    results<-qcs<-list();i<-0L
    for(shift in 0:1)for(s in CFG$landmarks) {
      z<-d[d$survival_days_analysis>s*CFG$year_days,,drop=FALSE]
      m<-match_patients(z,s,shift,lt);qcs[[length(qcs)+1L]]<-m$qc
      if(point&&shift==0)assert(m$qc$status!="MODULE NO-GO",paste("STOP: primary matching below 90% at L",s))
      vals<-setNames(rep(NA_real_,3),measures);reason<-if(m$qc$status=="MODULE NO-GO")"NOT ESTIMATED / MATCHING <90%" else "OK"
      if(reason=="OK") {
        vals<-tryCatch({
          matched<-z[m$mask,,drop=FALSE]
          expected<-expected_rmst(m$p[m$mask,,drop=FALSE])
          assert(length(expected)==nrow(matched),"Observed/expected subset mismatch.")
          observed<-observed_rmst(matched$survival_days_analysis-s*CFG$year_days,matched$event_os)
          setNames(c(observed,mean(expected),mean(expected)-observed),measures)
        },error=function(e) {reason<<-paste("NOT ESTIMATED:",conditionMessage(e));setNames(rep(NA_real_,3),measures)})
      }
      i<-i+1L
      results[[i]]<-cbind(data.frame(landmark=s,analysis_type=m$qc$analysis_type,n=m$qc$matched_n,
        match_rate=m$qc$match_rate,match_status=m$qc$status,status=reason,
        allcause_events_3y=sum(z$event_os[m$mask]==1 & z$survival_days_analysis[m$mask]-s*CFG$year_days<=CFG$tau_days),
        at_3y=sum(z$survival_days_analysis[m$mask]-s*CFG$year_days>=CFG$tau_days)),as.data.frame(as.list(vals)))
    }
    list(results=do.call(rbind,results),qc=do.call(rbind,qcs))
  }
  bootstrap<-function(d,lt,point) {
    RNGkind("L'Ecuyer-CMRG");set.seed(CFG$seed)
    stream<-get(".Random.seed",envir=.GlobalEnv)
    for(i in seq_len(CFG$stream))stream<-parallel::nextRNGStream(stream)
    assign(".Random.seed",stream,envir=.GlobalEnv)
    values<-array(NA_real_,c(12,3,S$B),dimnames=list(result_key(point$results),measures,NULL))
    errors<-character(S$B)
    for(b in seq_len(S$B)) {
      draw<-sample.int(nrow(d),nrow(d),replace=TRUE);z<-d[draw,,drop=FALSE]
      assert(nrow(z)==nrow(d),"Bootstrap multiplicity lost.")
      ev<-tryCatch(evaluate(z,lt),error=function(e)e)
      if(inherits(ev,"error"))errors[b]<-conditionMessage(ev) else {
        assert(identical(result_key(ev$results),result_key(point$results)),"Bootstrap landmark/analysis layout changed.")
        values[,,b]<-as.matrix(ev$results[measures])
      }
      if(b==1L||b%%50L==0L||b==S$B)say(toupper(S$mode),"patient bootstrap",b,"/",S$B)
    }
    list(values=values,errors=errors)
  }
  interval<-function(v) {
    valid<-is.finite(v)
    if(S$mode=="smoke"||mean(valid)<.95)return(c(NA_real_,NA_real_))
    as.numeric(stats::quantile(v[valid],c(.025,.975),names=FALSE,type=7))
  }
  summarize<-function(point,boot) {
    z<-point$results;z$bootstrap_attempts<-S$B
    prefixes<-c("observed","expected","gap")
    for(k in seq_along(measures)) {
      z[[paste0(prefixes[k],"_lower95")]]<-z[[paste0(prefixes[k],"_upper95")]]<-NA_real_
      z[[paste0(prefixes[k],"_valid_fraction")]]<-rowMeans(is.finite(boot$values[,k,]))
      for(i in seq_len(nrow(z)))if(is.finite(z[[measures[k]]][i]))z[i,c(paste0(prefixes[k],"_lower95"),paste0(prefixes[k],"_upper95"))]<-interval(boot$values[i,k,])
    }
    z$bootstrap_valid_fraction<-z$gap_valid_fraction;z$bootstrap_failure_fraction<-1-z$bootstrap_valid_fraction
    for(i in seq_len(nrow(z)))if(z$status[i]=="OK")z$status[i]<-if(S$mode=="smoke")"SMOKE ONLY / NOT FOR ARTICLE" else
      if(z$bootstrap_valid_fraction[i]<.95)paste(z$match_status[i],"/ CI UNAVAILABLE: <95% VALID") else z$match_status[i]
    main<-z[z$analysis_type=="PRIMARY",,drop=FALSE];sens<-z[z$analysis_type=="YEAR_PLUS_1",,drop=FALSE]
    pairs<-rbind(cbind(end=1:5,start=0L),cbind(end=2:5,start=1:4))
    changes<-do.call(rbind,lapply(seq_len(nrow(pairs)),function(i) {
      a<-which(z$analysis_type=="PRIMARY"&z$landmark==pairs[i,"end"])
      b<-which(z$analysis_type=="PRIMARY"&z$landmark==pairs[i,"start"])
      v<-boot$values[a,"gap_months",]-boot$values[b,"gap_months",];ci<-interval(v)
      data.frame(comparison=paste0("L",pairs[i,"end"],"-L",pairs[i,"start"]),
        gap_difference_months=z$gap_months[a]-z$gap_months[b],lower95=ci[1],upper95=ci[2],
        bootstrap_valid_fraction=mean(is.finite(v)),start_match_status=z$match_status[b],end_match_status=z$match_status[a],
        interpretation="DESCRIPTIVE SURVIVOR-CONDITIONED CHANGE",mode=S$mode)
    }))
    yearshift<-do.call(rbind,lapply(CFG$landmarks,function(s) {
      a<-which(z$analysis_type=="PRIMARY"&z$landmark==s);b<-which(z$analysis_type=="YEAR_PLUS_1"&z$landmark==s)
      delta<-z$gap_months[b]-z$gap_months[a];v<-boot$values[b,"gap_months",]-boot$values[a,"gap_months",];ci<-interval(v)
      data.frame(landmark=s,primary_gap=z$gap_months[a],yearplus1_gap=z$gap_months[b],difference_months=delta,
        absolute_difference_months=abs(delta),lower95=ci[1],upper95=ci[2],primary_match_rate=z$match_rate[a],
        sensitivity_match_rate=z$match_rate[b],primary_matched_n=z$n[a],sensitivity_matched_n=z$n[b],
        primary_match_status=z$match_status[a],sensitivity_match_status=z$match_status[b],
        bootstrap_valid_fraction=mean(is.finite(v)),status=z$status[b])
    }))
    plot<-do.call(rbind,lapply(seq_along(measures),function(k)data.frame(landmark=z$landmark,
      metric=c("OBSERVED_RMST","EXPECTED_RMST","RMST_GAP")[k],estimate=z[[measures[k]]],
      lower95=z[[paste0(prefixes[k],"_lower95")]],upper95=z[[paste0(prefixes[k],"_upper95")]],
      analysis_type=z$analysis_type,match_status=z$match_status,status=z$status,n=z$n,match_rate=z$match_rate,
      bootstrap_valid_fraction=z[[paste0(prefixes[k],"_valid_fraction")]],unit="months")))
    out<-list(life_table_metadata=S$metadata,matching_qc=point$qc,rmst_gap=main,
      landmark_changes=changes,yearshift_sensitivity=yearshift,plot_ready=plot)
    assert(identical(names(out),sheet_names),"Unexpected workbook sheets.")
    list(sheets=out,all=z)
  }
  report_lines<-function(shaped,boot) {
    z<-shaped$sheets$rmst_gap;changes<-shaped$sheets$landmark_changes
    shift<-shaped$sheets$yearshift_sensitivity;qc<-shaped$sheets$matching_qc
    fmt<-function(x)ifelse(is.finite(x),formatC(x,format="f",digits=2),"NA")
    ci<-function(x,l,u)paste0(fmt(x)," [",fmt(l),", ",fmt(u),"]")
    table<-function(d) {
      d[]<-lapply(d,function(v)gsub("|","/",as.character(v),fixed=TRUE))
      c(paste0("| ",paste(names(d),collapse=" | ")," |"),paste0("| ",paste(rep("---",ncol(d)),collapse=" | ")," |"),
        apply(d,1,function(v)paste0("| ",paste(v,collapse=" | ")," |")),"")
    }
    lines<-c("# General-population three-year restricted-survival gap", "",
      paste("Mode:",toupper(S$mode),"; bootstrap attempts:",S$B,"; generated:",format(Sys.time(),"%Y-%m-%d %H:%M:%S %Z")),"",
      "## Official reference and source", "",
      paste0("Database: ",database_name,". Official update: February 2026. [SEER documentation](https://seer.cancer.gov/expsurvival/)."),
      "The supplied SEER*Stat TXT and DIC matched their locked SHA-256 hashes. The export has 54,000 rows. Unknown and Other unspecified (1991+) have exactly identical Expected rate values over 10,800 unique Age x Year x Sex keys. Only Unknown rows are retained as ALL_RACES_COMBINED. Patient race is not used for matching.",
      "Expected rate is annual conditional survivors per million: p=Expected rate/1,000,000 and q=1-p, not a mortality rate. [Official export semantics](https://seer.cancer.gov/seerstat/faq.html). Full hashes, fields and provenance are in life_table_metadata; the user did not supply the original export/download date.",
      paste0("The frozen all-cause precursor contains 7,100 patients, retaining all 93 COD-unresolved cases. The 2004-2015, age<90 source contains ",S$source_n,
        " patients, including ",S$source_unresolved_n," COD-unresolved cases. Full-source L0-L5 counts: ",paste(S$cohort_n,collapse=" / "),"."),"",
      "## Matching", "",
      "Eligibility is survival_days_analysis > landmark x 365.25. Each annual segment j=0,1,2 uses floor(age_dx+s+j), year_dx+s+j, sex and the all-races table. Attained ages above 99 use age 99; no adjacent-year/age substitution, missing-key interpolation or last-year copying is allowed.",
      "REPORTABLE means >=95% matched; EXPLORATORY means 90-<95%. Any primary landmark below 90% stops the module. Matching categories are not statistical significance labels.","",
      table(qc[,c("analysis_type","landmark","eligible_n","matched_n","unmatched_n","match_rate","age99_capped_n","status")]),
      "Unmatched reasons are mutually exclusive, assigned in annual-segment order, then missing age, missing/unsupported sex, absent year, absent age, duplicate key, other absent combination, or invalid probability. The workbook retains all reason counts.","",
      "## Primary RMST and gap", "",
      "Units are months in the future three-year window. Expected RMST integrates each patient's three piecewise-exponential annual segments and then averages over matched patients. Observed RMST integrates the right-continuous all-cause Kaplan-Meier curve over the SAME matched individuals, including all valid deaths regardless of COD resolution. Early loss to follow-up remains right-censoring. No positive KM tail is extrapolated beyond observed support.",
      "Gap = expected minus observed RMST. Negative gaps are retained. Brackets are pointwise 95% patient-bootstrap percentile intervals; NA means unavailable, not zero.","",
      table(data.frame(LM=z$landmark,n=z$n,match_rate=z$match_rate,
        observed_months_95CI=ci(z$observed_RMST_months,z$observed_lower95,z$observed_upper95),
        expected_months_95CI=ci(z$expected_RMST_months,z$expected_lower95,z$expected_upper95),
        gap_months_95CI=ci(z$gap_months,z$gap_lower95,z$gap_upper95),valid_fraction=z$bootstrap_valid_fraction,status=z$status)),
      "## Descriptive landmark changes", "",
      table(changes[,c("comparison","gap_difference_months","lower95","upper95","bootstrap_valid_fraction")]))
    if(S$mode=="smoke")lines<-c(lines,"SMOKE ONLY: small computational fixture; all intervals suppressed and no scientific conclusions generated.","") else {
      complete<-all(is.finite(z$gap_months));delta<-if(complete)diff(z$gap_months) else NA_real_
      lines<-c(lines,if(!complete)"The gap trajectory is not fully assessable because some estimates are unavailable." else
        if(all(delta<=0))"The gap decreased or remained unchanged at every adjacent landmark in the point estimates." else
        if(utils::tail(z$gap_months,1)<z$gap_months[1])"The L5 gap was smaller than the L0 gap in the point estimates, but the adjacent trajectory was not uniformly decreasing." else
        "The point estimates did not show a smaller gap at L5 than at L0.","")
      decrease<-changes$comparison[is.finite(changes$upper95)&changes$upper95<0]
      lines<-c(lines,paste("Paired pointwise 95% intervals entirely below zero:",if(length(decrease))paste(decrease,collapse=", ") else "none","."),"")
      compatible<-z$landmark[is.finite(z$gap_lower95)&is.finite(z$gap_upper95)&z$gap_lower95<=0&z$gap_upper95>=0]
      if(length(compatible))lines<-c(lines,paste0("At ",paste0("L",compatible,collapse=", "),
        ", restricted survival was statistically compatible with the matched general-population expectation within this 3-year window. This is not an equivalence test or evidence of cure."),"")
      if(complete&&all(z$gap_months>0))lines<-c(lines,
        if(all(is.finite(z$gap_lower95))&&all(z$gap_lower95>0))"A residual restricted-survival deficit persisted at every landmark, with each pointwise 95% interval above zero." else
          "A residual restricted-survival deficit persisted in the point estimates; uncertainty must be interpreted separately at each landmark.","")
      negative<-z$landmark[is.finite(z$gap_months)&z$gap_months<0]
      if(length(negative))lines<-c(lines,paste0("Negative gap estimates were retained at ",paste0("L",negative,collapse=", "),
        ". Healthy-survivor selection and reference case-mix differences are possible explanations, not established mechanisms."),"")
    }
    lines<-c(lines,"## Prespecified calendar-year +1 sensitivity", "",
      "Only the life-table calendar-year keys shift by +1. Patient ages, observed times and landmark origins do not change. A missing future-year key remains unsupported; 2023 is not copied forward. Both observed and expected are recalculated on each variant's matched subset.","",
      table(shift[,c("landmark","primary_gap","yearplus1_gap","difference_months","absolute_difference_months",
        "primary_match_rate","sensitivity_match_rate","status")]))
    if(S$mode=="formal") {
      ok<-is.finite(shift$primary_gap)&is.finite(shift$yearplus1_gap)
      direction<-all(ok)&&all(sign(shift$primary_gap)==sign(shift$yearplus1_gap))
      lines<-c(lines,if(direction)"The direction of the gap estimates was robust to the prespecified one-year calendar-key shift sensitivity; this does not establish equivalence of magnitudes." else
        "Direction agreement was incomplete or could not be fully assessed under the +1 calendar-key sensitivity.","")
    }
    c(lines,"## Uncertainty and interpretation limits", "",
      paste0(S$B," source-patient bootstrap attempts use seed ",CFG$seed," and L'Ecuyer-CMRG stream advance ",CFG$stream,
        ". The same draw is shared across all six landmarks and both calendar-key variants; multiplicity is retained. Each draw rematches and recalculates observed and expected RMST. Failed attempts are not redrawn. Percentile intervals require >=95% valid attempts; otherwise CI=NA. Whole-draw failures: ",sum(nzchar(boot$errors)),"."),
      "The life table is a fixed reference, so its own sampling uncertainty is excluded. The interval for expected RMST reflects patient case-mix resampling only. Landmark differences are paired but descriptive, with different survivor populations. There is no global trend test, selected crossover point, or fractional-year normalization-time estimate.",
      "This is a survivor-conditioned general-population restricted-survival gap. It is not cancer-caused life loss, causal excess mortality, cure, restored normal lifespan or excess mortality attributable solely to GBC. It cannot be added to cause-specific RMTL. Narrower gaps across landmarks do not demonstrate same-population recovery or causal normalization.",
      "Limitations: all-races rather than race-matched expected survival; year-grid approximation; unknown diagnosis month and birthday; exclusion of diagnosis age 90+; life table treated as fixed; SEER case-mix; independent-censoring assumption for KM; and survivor selection. This module does not itself re-estimate cancer-specific burden.")
  }
  stream_process<-function(executable,args,payload) {
    child<-processx::process$new(executable,args,stdin="|",stdout="|",stderr="|",
      windows_hide_window=TRUE,encoding="UTF-8",cleanup=TRUE)
    on.exit({if(child$is_alive())child$kill()},add=TRUE)
    output<-errors<-character();started<-Sys.time()
    drain<-function() {
      output<<-c(output,child$read_output());errors<<-c(errors,child$read_error())
      assert(as.numeric(difftime(Sys.time(),started,units="secs"))<600,"Aggregate export/verification process timed out.")
    }
    bytes<-charToRaw(enc2utf8(as.character(payload)))
    for(first in seq.int(1L,length(bytes),by=65536L)) {
      pending<-bytes[first:min(first+65535L,length(bytes))]
      while(length(pending)) {
        assert(child$is_alive(),paste("Aggregate process exited early:",paste(errors,collapse="")))
        pending<-child$write_input(pending);drain()
        if(length(pending))child$poll_io(10L)
      }
    }
    close(child$get_input_connection())
    while(child$is_alive()) {child$poll_io(100L);drain()}
    drain();assert(identical(child$get_exit_status(),0L),paste("Aggregate process failed:",paste(errors,collapse="")))
    paste(output,collapse="")
  }
  export_workbook<-function(sheets,path=NULL) {
    js<-r"---(import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
const req=createRequire(path.join(process.argv[1],'lifetable_loader.cjs'));
const {Workbook,SpreadsheetFile}=await import(pathToFileURL(req.resolve('@oai/artifact-tool')).href);
const chunks=[];for await(const c of process.stdin)chunks.push(c);
const p=JSON.parse(Buffer.concat(chunks).toString('utf8'));const wb=Workbook.create();
for(const [name,rows] of Object.entries(p.sheets)) {
 const fields=Object.keys(rows[0]);const sh=wb.worksheets.add(name);sh.showGridLines=false;
 sh.getRange('A2').values=[[name.replaceAll('_',' ').toUpperCase()]];
 sh.getRange('A2').format.font={name:'Arial',size:14,bold:true,color:'#263F55'};
 sh.getRange('A3').values=[[p.mode==='smoke'?'SMOKE ONLY - NOT FOR ARTICLE - 3 BOOTSTRAP ATTEMPTS':'Three-year survivor-conditioned RMST gap. 1000 patient bootstrap attempts.']];
 sh.getRange('A3').format.font={name:'Arial',size:10,bold:true,color:p.mode==='smoke'?'#9C302A':'#263F55'};
 sh.getRange('A4').values=[['Time measures: months. Gap = expected minus observed. Negative values retained. Blank intervals are unavailable, never zero.']];
 sh.getRange('A4').format.font={name:'Arial',size:10,italic:true,color:'#555555'};
 sh.getRangeByIndexes(4,0,1,fields.length).values=[fields];
 sh.getRangeByIndexes(5,0,rows.length,fields.length).values=rows.map(r=>fields.map(k=>r[k]??null));
 const all=sh.getRangeByIndexes(4,0,rows.length+1,fields.length);
 all.format.font={name:'Arial',size:10,color:'#243347'};all.format.rowHeight=21;all.format.verticalAlignment='center';
 const head=sh.getRangeByIndexes(4,0,1,fields.length);head.format.fill='#304F70';
 head.format.font={name:'Arial',size:10,bold:true,color:'#FFFFFF'};
 head.format.wrapText=true;head.format.rowHeight=48;head.format.horizontalAlignment='center';
 for(let j=0;j<fields.length;j++) {
  const k=fields[j],vals=rows.map(r=>r[k]).filter(v=>v!==null&&v!==undefined);
  const numeric=vals.length>0&&vals.every(v=>typeof v==='number');let width=k.length>22?27:20;
  if(['landmark','n','mode'].includes(k))width=12;
  if(/status|interpretation/.test(k))width=36;
  if(name==='life_table_metadata'&&!numeric)width=52;
  const col=sh.getRangeByIndexes(5,j,rows.length,1);
  sh.getRangeByIndexes(4,j,rows.length+1,1).format.columnWidth=width;
  col.format.horizontalAlignment=numeric?'right':'left';
  if(name==='life_table_metadata'){col.format.wrapText=true;col.format.verticalAlignment='top';col.format.rowHeight=105;}
  if(numeric) {
   const count=/^(landmark|n|eligible_n|matched_n|unmatched_n|age99_capped_n|missing_age|missing_sex|missing_year_key|missing_age_key|duplicate_key|invalid_probability|other|rows|rows_used|age_min|age_max|year_min|year_max|unique_ages|unique_years|unique_sex|missing_values|invalid_p_values|seed|rng_stream_advance|bootstrap_attempts|allcause_events_3y|at_3y)$/.test(k)||/_matched_n$/.test(k);
   col.setNumberFormat(count?'#,##0':/rate|fraction/.test(k)?'0.0%':'0.00');
  }
 }
 if(rows.length>15)sh.freezePanes.freezeRows(5);
}
wb.recalculate();
const inspected=await wb.inspect({kind:'sheet',include:'id,name',maxChars:2500});
if(!inspected.ndjson)throw Error('Workbook sheet inspection unavailable');
const out=await SpreadsheetFile.exportXlsx(wb);
if(p.path) {await fs.writeFile(p.path,out.data,{flag:'wx'});process.stdout.write('WORKBOOK EXPORTED');}
else process.stdout.write(Buffer.from(out.data).toString('base64'));
)---"
    payload<-jsonlite::toJSON(list(mode=S$mode,sheets=sheets,path=path),auto_unbox=TRUE,dataframe="rows",na="null",null="null",digits=16)
    result<-stream_process(S$node,c("--input-type=module","-e",js,S$modules),payload)
    if(is.null(path)) {
      code<-r"---(import sys,json,base64,io,zipfile,math
import openpyxl
p=json.load(sys.stdin);raw=base64.b64decode(p['xlsx'])
with zipfile.ZipFile(io.BytesIO(raw)) as f:
 assert not any(n.startswith(('xl/media/','xl/drawings/','xl/charts/')) for n in f.namelist())
w=openpyxl.load_workbook(io.BytesIO(raw),read_only=True,data_only=True)
assert w.sheetnames==list(p['sheets'])
cells=0
for name,expected in p['sheets'].items():
 rows=list(w[name].iter_rows(min_row=5,values_only=True));keys=list(expected[0]);assert list(rows[0])==keys
 assert len(rows)-1==len(expected)
 for row,record in zip(rows[1:],expected):
  for actual,k in zip(row,keys):
   wanted=record[k]
   if isinstance(wanted,(int,float)) and not isinstance(wanted,bool): assert isinstance(actual,(int,float)) and math.isclose(actual,wanted,rel_tol=1e-12,abs_tol=1e-10),(name,k)
   else: assert actual==wanted,(name,k,actual,wanted)
   cells+=1
w.close();print(json.dumps(dict(excel_six_sheets='PASS',cells_checked=cells,images_or_charts=0,files_written=0)))
)---"
      check<-stream_process(S$verify_python,c("-c",code),jsonlite::toJSON(list(xlsx=trimws(result),sheets=sheets),
        auto_unbox=TRUE,dataframe="rows",na="null",digits=16))
      say(trimws(check))
    } else say(trimws(result),path)
    invisible(TRUE)
  }
  smoke_checks<-function(lt,d) {
    near<-function(x,y,msg)assert(max(abs(x-y))<1e-8,msg)
    fails<-function(expr)inherits(tryCatch({force(expr);NULL},error=function(e)e),"error")
    near(expected_rmst(matrix(1,1,3)),36,"Zero-hazard expected integral failed.")
    near(expected_rmst(matrix(.8,1,3)),12*(1-.8^3)/(-log(.8)),"Constant hazard expected integral failed.")
    p<-matrix(c(.9,.8,.7),1,3)
    numerical<-sum(vapply(0:2,function(j)stats::integrate(function(t)
      (if(j==0)1 else prod(p[1,seq_len(j)]))*exp(log(p[1,j+1])*(t-j)),j,j+1,rel.tol=1e-12)$value,numeric(1)))*12
    near(expected_rmst(p),numerical,"Expected exact vs numerical integration failed.")
    near(expected_rmst(matrix(1-1e-12,1,3)),36, "Near-zero hazard precision failed.")
    assert(fails(expected_rmst(matrix(0,1,3))),"Zero survival probability was not rejected.")
    near(observed_rmst(c(100,200,400,1200),c(1,0,1,0)),(100+300*.75+(CFG$tau_days-400)*.375)/CFG$month_days,"KM event/censor integral failed.")
    near(observed_rmst(c(100,100,1200),c(1,0,0)),(100+(CFG$tau_days-100)*2/3)/CFG$month_days,"KM tied death/censor failed.")
    near(observed_rmst(c(CFG$tau_days,1200),c(1,0)),36,"KM right boundary failed.")
    near(observed_rmst(c(100,200),c(1,1)),150/CFG$month_days,"Extinct KM tail failed.")
    assert(fails(observed_rmst(c(100,200),c(0,0))),"Unsupported positive KM tail was extrapolated.")
    assert(expected_rmst(matrix(.8,1,3))-observed_rmst(c(1200,1300),c(0,0))<0,"Negative gap was clipped.")
    z<-d[seq_len(6),,drop=FALSE];z$age_dx<-rep(60,6);z$year_dx<-rep(2010L,6);z$sex<-rep("Female",6)
    original<-z;m0<-match_patients(z,2,0,lt);m1<-match_patients(z,2,1,lt)
    assert(identical(z,original)&&all(m0$mask)&&all(m1$mask),"Calendar sensitivity modified patient data.")
    for(j in 0:2) {
      near(m0$p[,j+1],rep(lt$p[match(key(62+j,2012+j,"Female"),lt$key)],6),"Primary annual keys incorrect.")
      near(m1$p[,j+1],rep(lt$p[match(key(62+j,2013+j,"Female"),lt$key)],6),"+1 annual keys incorrect.")
    }
    z$year_dx[1]<-2021L
    assert(match_patients(z,0,0,lt)$mask[1]&&!match_patients(z,0,1,lt)$mask[1],"2024 unsupported rule failed.")
    z$year_dx[1]<-2010L;z$age_dx[1]<-100
    capped<-match_patients(z,0,0,lt);assert(capped$mask[1]&&capped$qc$age99_capped_n==1,"Age99 cap failed.")
    near(capped$p[1,],lt$p[match(key(rep(99,3),2010:2012,rep("Female",3)),lt$key)],"Age99 lookup wrong.")
    z<-original;z$age_dx[1]<-NA;z$sex[2]<-NA
    m<-match_patients(z,0,0,lt);assert(identical(which(m$mask),3:6),"Matched subset membership failed.")
    z$survival_days_analysis<-c(50,60,1200,1300,1400,1500);z$event_os<-rep(0L,6)
    direct<-evaluate(z,lt)$results;row<-direct[direct$landmark==0&direct$analysis_type=="PRIMARY",]
    assert(is.na(row$gap_months)&&row$match_status=="MODULE NO-GO","Low matching gate did not suppress output.")
    z<-original[rep(1:6,each=4),,drop=FALSE];z$survival_days_analysis<-rep(1500,nrow(z));z$event_os<-rep(0L,nrow(z))
    z$age_dx[1]<-NA;z$survival_days_analysis[1]<-10;z$event_os[1]<-1L
    ev<-evaluate(z,lt);row<-ev$results[ev$results$landmark==0&ev$results$analysis_type=="PRIMARY",]
    mm<-match_patients(z,0,0,lt)
    near(row$observed_RMST_months,36,"Unmatched death leaked into observed subset.")
    near(row$expected_RMST_months,mean(expected_rmst(mm$p[mm$mask,,drop=FALSE])),"Expected subset differs from observed.")
    assert(row$n==23&&sum(mm$mask)==23,"Repeated patient copies were deduplicated.")
    assert(match_status(.95)=="REPORTABLE"&&match_status(.90)=="EXPLORATORY"&&match_status(.899)=="MODULE NO-GO","Matching boundary failed.")
    say("EXPECTED RMST / OBSERVED KM / MATCHED SUBSET / GAP SIGN / YEAR+1 / MULTIPLICITY SMOKE = PASS")
    invisible(TRUE)
  }
  finish<-function(point,boot) {
    shaped<-summarize(point,boot);report<-report_lines(shaped,boot)
    hashes()
    if(S$mode=="formal") {
      assert(!any(file.exists(S$paths)),"Outputs already exist; refusing overwrite.")
      export_workbook(shaped$sheets,S$paths[1]);writeLines(enc2utf8(report),S$paths[2],useBytes=TRUE)
      say("FORMAL LIFE-TABLE COMPLETE:",paste(S$paths,collapse=" ; "))
    } else {
      export_workbook(shaped$sheets)
      say("SMOKE PASS: 3 patient bootstrap attempts; no formal results or files written.")
    }
    S$results<-shaped$sheets
    invisible(shaped$sheets)
  }
  resume<-function(saved=NULL) {
    if(is.null(saved)) {
      assert(exists("completed",envir=S,inherits=FALSE),"No completed in-memory bootstrap retained.")
      saved<-list(point=S$completed$point,boot=S$completed$boot,state=S)
    }
    assert(is.list(saved)&&all(c("point","boot","state") %in% names(saved))&&is.environment(saved$state),"Invalid recovery object.")
    assert(identical(saved$state$mode,"formal")&&saved$state$B==CFG$B&&
      identical(dim(saved$boot$values),c(12L,3L,CFG$B)),"Recovery requires the completed 1000-draw formal result.")
    assert(identical(dimnames(saved$boot$values)[[1]],result_key(saved$point$results))&&
      identical(dimnames(saved$boot$values)[[2]],measures),"Recovery result layout differs from the frozen module.")
    S<<-saved$state
    say("RESUMING SUMMARY AND EXPORT ONLY: existing 1000 draws; no new bootstrap.")
    finish(saved$point,saved$boot)
  }
  run<-function(mode="formal") {
    old_kind<-RNGkind();had_seed<-exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE)
    if(had_seed)old_seed<-get(".Random.seed",envir=.GlobalEnv)
    on.exit({do.call(RNGkind,as.list(old_kind));if(had_seed)assign(".Random.seed",old_seed,envir=.GlobalEnv) else
      if(exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE))rm(".Random.seed",envir=.GlobalEnv)},add=TRUE)
    setup(mode);lt<-read_life_table();d<-read_source()
    audit<-do.call(rbind,lapply(0:1,function(shift)do.call(rbind,lapply(CFG$landmarks,function(s)
      match_patients(d[d$survival_days_analysis>s*CFG$year_days,,drop=FALSE],s,shift,lt)$qc))))
    print(audit[,c("analysis_type","landmark","eligible_n","matched_n","match_rate","status")],row.names=FALSE)
    assert(all(audit$match_rate[audit$analysis_type=="PRIMARY"]>=.9),"STOP: full-source primary life-table matching <90%.")
    S$full_matching_qc<-audit
    if(S$mode=="smoke") {
      smoke_checks(lt,d)
      keep<-unique(round(seq(1,nrow(d),length.out=180)))
      d<-d[keep,,drop=FALSE]
      S$metadata$smoke_source_n<-nrow(d)
    }
    point<-evaluate(d,lt,point=TRUE)
    if(S$mode=="smoke")assert(all(is.finite(as.matrix(point$results[measures]))),"SMOKE point computation failed.")
    boot<-bootstrap(d,lt,point)
    S$completed<-list(point=point,boot=boot)
    if(S$mode=="smoke")assert(all(is.finite(boot$values))&&!any(nzchar(boot$errors)),"SMOKE bootstrap computation failed.")
    if(S$mode=="smoke")local({
      previous<-S$mode;on.exit({S$mode<-previous});S$mode<-"formal"
      fixture<-boot;fixture$values[1,,1]<-NA_real_
      checked<-summarize(point,fixture)
      assert(grepl("CI UNAVAILABLE",checked$all$status[1],fixed=TRUE)&&
        is.na(checked$all$gap_lower95[1])&&checked$all$status[2]=="REPORTABLE"&&
        is.finite(checked$all$gap_lower95[2]),"Formal scalar validity/CI branch regression failed.")
      assert(length(report_lines(checked,fixture))>0,"Formal report assembly regression failed.")
      say("FORMAL SUMMARY BRANCH REGRESSION = PASS (3-draw fixture only)")
    })
    finish(point,boot)
  }
  environment()
})
if(isTRUE(getOption("gbc.lifetable.autorun", FALSE)))gbc_lifetable$run("formal")


