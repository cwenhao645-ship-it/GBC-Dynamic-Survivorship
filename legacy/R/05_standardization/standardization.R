# Publication source copy. See docs/original_script_mapping.md and reproducibility_notes.md.

gbc_standardization <- local({
  S <- new.env(parent=emptyenv())
  CFG <- list(seed=20260905L, B=1000L, stream=4L, landmarks=0:5,
    knots=c(48,65,76,87), horizons=c(3,2), causes=c("GBC","Other"))
  targets <- list(T=list(variable="T_core",high="T3/4",low="T1",label="T3/4 minus T1"),
    N=list(variable="N_model",high="N+",low="N0",label="N+ minus N0"),
    Grade=list(variable="grade_model",high="G3/4",low="G1",label="G3/4 minus G1"))
  measures <- c("risk_high","risk_low","delta_CIF","RMTL_high_months","RMTL_low_months","delta_RMTL_months")
  files <- c(patient="data/analysis_patient_level_v2.parquet",landmark="data/analysis_landmark_long_v2.parquet",
    sap="spec/SAP_TECHNICAL_ADDENDUM_v1.1.md",library="R/06_models/development.R",
    stage1="private/preparation/outputs/STAGE1_ANALYSIS_REPORT.md")
  frozen_hashes <- c(patient="b8bb4d6d7a5c00924aedd9383c3be4ba22c7b0c1060d72288be64207d88fd870",
    landmark="6d7ebcc62aa2da953ccdada3cce61ab366bcd0dfde0b24d7349bdafa5efe5da1",
    sap="9a5e363afb395fe86d12ddc94817b4d727af74dae0dc27946acb6d00c79c328d",
    library="e9e1e8ac07bd7a374e7c5476cf3882f2502d9939aaadbba40d401a24000d2dee",
    stage1="2515eea964e9453cec0f17ab30d3c57953bce9b939cc2bdaa88590c97b58021e")
  source_files <- unlist(lapply(sys.frames(),function(f)f$ofile))
  S$script <- if(length(source_files))utils::tail(source_files,1) else NA_character_
  assert <- function(ok,msg) {if(!isTRUE(ok))stop(msg,call.=FALSE);invisible(TRUE)}
  say <- function(...) {cat(format(Sys.time(),"%H:%M:%S"),...,"\n");flush.console()}
  key <- function(z)paste(z$target,z$landmark,z$cause,z$horizon_years,sep="|")
  support_key <- function(z)paste(z$target,z$landmark,sep="|")
  state <- function(coverage)if(!is.finite(coverage) || coverage<.7)"FAIL" else if(coverage<.9)"LIMITED" else "PASS"
  hashes <- function() {
    h <- vapply(files,function(p)digest::digest(file=file.path(S$root,p),algo="sha256"),character(1))
    assert(identical(unname(h),unname(frozen_hashes)),"STOP: a frozen input changed; no automatic repair.")
    invisible(h)
  }
  setup <- function() {
    roots <- c(if(!is.na(S$script))dirname(dirname(normalizePath(S$script,winslash="/"))),getwd(),Sys.getenv("GBC_FINAL_RUN_ROOT", unset = getwd()))
    usable <- vapply(roots,function(p)file.exists(file.path(p,files[["sap"]])) &&
      file.exists(file.path(p,files[["patient"]])),logical(1))
    assert(any(usable),"Cannot locate gbc_final_run.")
    S$root <- normalizePath(roots[which(usable)[1]],winslash="/",mustWork=TRUE)
    assert(as.character(getRversion())=="4.4.3","Use the locked R 4.4.3 runtime.")
    versions <- c(survival="3.8.3",Hmisc="5.2.3",jsonlite="2.0.0",digest="0.6.37",processx="3.8.6")
    for(p in names(versions))assert(requireNamespace(p,quietly=TRUE) &&
      utils::compareVersion(as.character(utils::packageVersion(p)),versions[[p]])==0,paste("Missing/mismatched package:",p))
    suppressPackageStartupMessages(library(stats))
    suppressPackageStartupMessages(library(survival))
    hashes()
    S$D <- new.env(parent=.GlobalEnv)
    wanted <- c("CFG","assert","fit_failure","make_rcs","cox_checked","baseline_information","integrate_grid")
    for(expr in parse(file.path(S$root,files[["library"]]))) {
      if(is.call(expr) && identical(expr[[1]],as.name("<-")) && is.symbol(expr[[2]]) &&
         as.character(expr[[2]]) %in% wanted)eval(expr,envir=S$D)
    }
    assert(all(wanted %in% ls(S$D)) && identical(S$D$CFG$knots,CFG$knots),"Stable function library incomplete.")
    runtime <- Sys.getenv("GBC_RUNTIME_ROOT")
    S$python <- Sys.getenv("GBC_PYTHON")
    S$node <- file.path(runtime,"node/bin/node.exe");S$modules <- file.path(runtime,"node/node_modules")
    for(p in c(S$python,S$node,S$modules))assert(file.exists(p),paste("Missing installed dependency:",p))
    S$paths <- file.path(S$root,"outputs",c("STANDARDIZATION_RESULTS.xlsx","STANDARDIZATION_REPORT.md"))
    assert(!any(file.exists(S$paths)),"Standardization outputs already exist; refusing overwrite.")
    S$B <- CFG$B
    say("FORMAL LM-SPECIFIC STANDARDIZATION STARTED:",S$B,"patient bootstrap attempts.")
  }
  read_data <- function() {
    code <- r"---(import json,sys
from pathlib import Path
import pyarrow.parquet as pq
root=Path(sys.argv[1]);flt=[('year_dx','>=',2004),('year_dx','<=',2015)]
cols=['patient_id','record_id','year_dx','age_dx','age_90plus_flag','sex','T_model','N_model','grade_model','survival_days_analysis','event_competing','M_harmonized']
p=pq.read_table(root/'data/analysis_patient_level_v2.parquet',columns=cols,filters=flt).to_pandas().sort_values('patient_id',kind='stable')
lc=['patient_id','record_id','year_dx','landmark_year','time_from_landmark','time_to_analysis_end','event_within_window','analysis_role']
l=pq.read_table(root/'data/analysis_landmark_long_v2.parquet',columns=lc,filters=flt+[('analysis_role','==','DESCRIPTIVE')]).to_pandas()
print(json.dumps(dict(patient=json.loads(p.to_json(orient='records')),landmark=json.loads(l.to_json(orient='records'))),separators=(',',':')))
)---"
    r <- processx::run(S$python,c("-c",code,S$root),stdout="|",stderr="|",windows_hide_window=TRUE,error_on_status=TRUE)
    obj <- jsonlite::fromJSON(r$stdout);d<-obj$patient;l<-obj$landmark
    assert(nrow(d)==3918L && !anyNA(d) && !anyDuplicated(d$patient_id) && !anyDuplicated(d$record_id),"Frozen source n/ID/missingness mismatch.")
    assert(all(d$year_dx %in% 2004:2015) && all(d$M_harmonized=="M0"),"Source-year/M0 mismatch.")
    d$time <- d$survival_days_analysis/365.25;d$status<-as.integer(d$event_competing)
    d$T_core <- ifelse(d$T_model %in% c("Unknown","Unknown/nonstandard"),"Unknown",d$T_model)
    d$cluster <- seq_len(nrow(d))
    assert(all(is.finite(d$time)) && all(d$time>0) && all(d$status %in% 0:2),"Invalid frozen follow-up/COD.")
    assert(all(d$age_dx[as.logical(d$age_90plus_flag)]==90),"Age top coding changed.")
    for(v in list(c("sex","Female","Male"),c("T_core","T1","T2","T3/4","Unknown"),
      c("N_model","N0","N+","Unknown"),c("grade_model","G1","G2","G3/4","Unknown")))
      assert(all(d[[v[1]]] %in% v[-1]),paste("Frozen category mismatch:",v[1]))
    windows <- lapply(CFG$landmarks,function(s)landmark(d,s))
    expected_n <- c(3918L,2496L,1786L,1423L,1192L,1047L)
    expected_gbc <- c(1876L,961L,492L,265L,146L,82L)
    expected_other <- c(533L,314L,220L,208L,183L,165L)
    expected_censor <- c(86L,29L,27L,16L,14L,16L)
    S$cohort <- do.call(rbind,lapply(windows,function(z)data.frame(landmark=z$lm[1],n=nrow(z),
      GBC_events=sum(z$event==1),Other_events=sum(z$event==2),early_censored=sum(z$u<3 & z$status==0),
      at_3y=sum(z$u>=3),source_2004_2011_n=sum(z$year_dx<=2011),source_2012_2015_n=sum(z$year_dx>=2012))))
    assert(identical(S$cohort$n,expected_n) && all(S$cohort$GBC_events==expected_gbc) &&
      all(S$cohort$Other_events==expected_other) && all(S$cohort$early_censored==expected_censor),"Frozen landmark counts differ from Stage 1.")
    rebuilt <- do.call(rbind,windows);lookup<-paste(l$record_id,l$landmark_year,sep="|")
    j <- match(paste(rebuilt$record_id,rebuilt$lm,sep="|"),lookup)
    assert(nrow(l)==11862L && nrow(l)==nrow(rebuilt) && !anyDuplicated(lookup) && !anyNA(j) &&
      all(l$analysis_role=="DESCRIPTIVE") && all(l$event_within_window[j]==rebuilt$event) &&
      max(abs(l$time_from_landmark[j]/365.25-rebuilt$u))<1e-8 &&
      max(abs(l$time_to_analysis_end[j]/365.25-rebuilt$stop))<1e-8,"Stored/rebuilt DESCRIPTIVE landmark mismatch.")
    say("Source and landmark counts matched:",paste(S$cohort$n,collapse=" / "))
    d
  }
  landmark <- function(d,s) {
    z<-d[d$time>s,,drop=FALSE];z$lm<-rep(s,nrow(z));z$start<-rep(0,nrow(z));z$u<-z$time-s
    z$stop<-pmin(z$u,3);z$event<-ifelse(z$u<=3,z$status,0L);z
  }
  common_support <- function(d,target,s) {
    t<-targets[[target]];other<-c("sex",setdiff(c("T_core","N_model","grade_model"),t$variable))
    cells<-do.call(paste,c(d[other],sep="|"));categorical<-age_ok<-rep(FALSE,nrow(d))
    adequate<-overlap_cells<-0L
    for(ii in split(seq_len(nrow(d)),cells)) {
      hi<-ii[d[[t$variable]][ii]==t$high];lo<-ii[d[[t$variable]][ii]==t$low]
      if(length(unique(d$patient_id[hi]))<5L || length(unique(d$patient_id[lo]))<5L)next
      adequate<-adequate+1L;categorical[ii]<-TRUE
      lower<-max(min(d$age_dx[hi]),min(d$age_dx[lo]));upper<-min(max(d$age_dx[hi]),max(d$age_dx[lo]))
      if(lower>upper)next
      overlap_cells<-overlap_cells+1L;age_ok[ii]<-d$age_dx[ii]>=lower & d$age_dx[ii]<=upper
    }
    coverage<-if(nrow(d))mean(age_ok) else NA_real_
    summary<-data.frame(target=target,contrast=t$label,landmark=s,reference_n=nrow(d),supported_n=sum(age_ok),
      coverage=coverage,categorical_supported_n=sum(categorical),age_supported_n=sum(age_ok),status=state(coverage),
      target_high_n=sum(d[[t$variable]]==t$high),target_low_n=sum(d[[t$variable]]==t$low),
      independent_reference_n=length(unique(d$patient_id)),adequate_cells=adequate,age_overlap_cells=overlap_cells,
      source_2004_2011_n=sum(d$year_dx<=2011),source_2012_2015_n=sum(d$year_dx>=2012),
      supported_2004_2011_n=sum(age_ok & d$year_dx<=2011),supported_2012_2015_n=sum(age_ok & d$year_dx>=2012))
    list(mask=age_ok,summary=summary)
  }
  all_support <- function(d) {
    do.call(rbind,lapply(CFG$landmarks,function(s)do.call(rbind,lapply(names(targets),function(t)
      common_support(landmark(d,s),t,s)$summary))))
  }
  design <- function(d) {
    cbind(S$D$make_rcs(d$age_dx),Male=as.numeric(d$sex=="Male"),T2=as.numeric(d$T_core=="T2"),
      T34=as.numeric(d$T_core=="T3/4"),Nplus=as.numeric(d$N_model=="N+"),G2=as.numeric(d$grade_model=="G2"),
      G34=as.numeric(d$grade_model=="G3/4"),Year=(d$year_dx-2009.5)/5,
      T_unknown=as.numeric(d$T_core=="Unknown"),N_unknown=as.numeric(d$N_model=="Unknown"),
      G_unknown=as.numeric(d$grade_model=="Unknown"))
  }
  fit_cause <- function(d,k,s) {
    x<-design(d);pen<-c(rep(FALSE,10),rep(TRUE,3));zero<-pen & colSums(abs(x))==0
    keep<-which(!zero);xx<-x[,keep,drop=FALSE]
    rank<-qr(sweep(xx,2,colMeans(xx),"-"),tol=1e-9)$rank
    meta<-data.frame(landmark=s,cause=CFG$causes[k],n=nrow(d),independent_patients=length(unique(d$patient_id)),
      event_count=sum(d$event==k),nominal_regression_df=13L,active_columns=ncol(xx),actual_model_rank=rank,
      events_per_nominal_df=sum(d$event==k)/13,fit_success=FALSE,convergence=FALSE,
      ridge_theta=1,ridge_scale=FALSE,ridge_state="Unknown indicators only; known main effects and year unpenalized",
      fixed_zero_unknown=paste(colnames(x)[zero],collapse=";"),baseline_support_years=max(d$stop),
      at_3y=sum(d$u>=3),baseline_jumps=NA_integer_,information_rcond=NA_real_,iterations=NA_integer_,message="")
    attempt<-tryCatch({
      assert(nrow(d)>0 && meta$event_count>0,"No observations or cause events.")
      assert(rank==ncol(xx),"Rank-deficient active model; no term deletion permitted.")
      assert(max(d$stop)>=3,"No three-year baseline follow-up support.")
      frame<-data.frame(start=d$start,stop=d$stop,death=as.integer(d$event==k))
      frame$X<-I(xx[,!pen[keep],drop=FALSE]);rhs<-"Surv(start,stop,death) ~ X"
      if(any(pen[keep])) {frame$U<-I(xx[,pen[keep],drop=FALSE]);rhs<-paste(rhs,"+ ridge(U,theta=1,scale=FALSE)")}
      f<-S$D$cox_checked(stats::as.formula(rhs,env=environment()),frame)
      assert(length(stats::coef(f))==ncol(xx) && max(abs(unname(f$x)-unname(xx)))<1e-10,"Cox design/column order changed.")
      assert(!any(f$iter>=60),"Iteration limit reached.")
      condition<-rcond(f$var);assert(is.finite(condition) && condition>=1e-12,"Singular/ill-conditioned fitted information.")
      beta<-setNames(as.numeric(stats::coef(f)),colnames(xx))
      baseline<-S$D$baseline_information(d,xx,beta,k)$baseline[[as.character(s)]]
      assert(nrow(baseline)>0 && all(is.finite(baseline$hazard)),"No finite cause baseline.")
      fullbeta<-setNames(numeric(13),colnames(x));fullbeta[keep]<-beta
      meta$fit_success<-TRUE;meta$convergence<-TRUE;meta$baseline_jumps<-nrow(baseline)
      meta$information_rcond<-condition;meta$iterations<-max(f$iter)
      meta$message<-paste(f$captured_warnings,collapse="; ")
      list(beta=fullbeta,baseline=baseline,support=max(d$stop))
    },error=function(e) {meta$message<<-conditionMessage(e);NULL})
    list(model=attempt,meta=meta)
  }
  predict_pair <- function(pair,reference,horizon) {
    assert(length(pair)==2 && all(vapply(pair,function(f)!is.null(f),logical(1))),"Both cause models required.")
    assert(nrow(reference)>0 && all(vapply(pair,function(f)f$support>=horizon,logical(1))),"Unsupported prediction reference/horizon.")
    x<-design(reference);times<-sort(unique(c(pair[[1]]$baseline$time,pair[[2]]$baseline$time)))
    times<-times[times<=horizon]
    a<-lapply(pair,function(f) {
      assert(identical(colnames(x),names(f$beta)),"Prediction design mismatch.")
      h<-f$baseline$hazard[match(times,f$baseline$time)];h[is.na(h)]<-0
      outer(exp(drop(x%*%f$beta)),h)
    })
    p<-S$D$integrate_grid(times,a[[1]],a[[2]],0,horizon)
    p[,c("RMTL_GBC","RMTL_Other")]<-p[,c("RMTL_GBC","RMTL_Other"),drop=FALSE]*12
    assert(all(p[,c("RMTL_GBC","RMTL_Other"),drop=FALSE]>=0) &&
      all(rowSums(p[,c("RMTL_GBC","RMTL_Other"),drop=FALSE])<=12*horizon+1e-9),"RMTL units/integral bounds failed.")
    p
  }
  set_target <- function(d,target,level) {
    v<-targets[[target]]$variable;z<-d;z[[v]]<-rep(level,nrow(z))
    assert(identical(z[setdiff(names(z),v)],d[setdiff(names(d),v)]),"Target reassignment modified other variables.")
    z
  }
  evaluate <- function(d,original_support=NULL,progress=FALSE) {
    result<-fits<-supports<-list();idx<-0L
    for(s in CFG$landmarks) {
      z<-landmark(d,s);ss<-lapply(names(targets),function(t)common_support(z,t,s));names(ss)<-names(targets)
      ff<-lapply(1:2,function(k)fit_cause(z,k,s));pair<-lapply(ff,`[[`,"model")
      fits[[length(fits)+1L]]<-do.call(rbind,lapply(ff,`[[`,"meta"))
      for(t in names(targets)) {
        su<-ss[[t]]$summary;supports[[length(supports)+1L]]<-su
        permitted<-su$status!="FAIL"
        if(!is.null(original_support))permitted<-permitted && original_support$status[match(support_key(su),support_key(original_support))]!="FAIL"
        reason<-if(!permitted)"NOT ESTIMATED / SUPPORT FAIL" else if(any(vapply(pair,is.null,logical(1))))"NOT ESTIMATED / MODEL FIT FAILURE" else "OK"
        ref<-z[ss[[t]]$mask,,drop=FALSE]
        for(h in CFG$horizons) {
          values<-matrix(NA_real_,2,length(measures),dimnames=list(CFG$causes,measures))
          this_reason<-reason
          if(reason=="OK") {
            pred<-tryCatch({
              high<-predict_pair(pair,set_target(ref,t,targets[[t]]$high),h)
              low<-predict_pair(pair,set_target(ref,t,targets[[t]]$low),h)
              list(high=colMeans(high),low=colMeans(low))
            },error=function(e) {this_reason<<-paste("NOT ESTIMATED / PREDICTION FAILURE:",conditionMessage(e));NULL})
            if(!is.null(pred))for(k in 1:2) {
              c<-CFG$causes[k];r<-paste0("RMTL_",c)
              values[k,]<-c(pred$high[c],pred$low[c],pred$high[c]-pred$low[c],
                pred$high[r],pred$low[r],pred$high[r]-pred$low[r])
            }
          }
          for(k in 1:2) {
            idx<-idx+1L
            result[[idx]]<-cbind(data.frame(target=t,contrast=targets[[t]]$label,cause=CFG$causes[k],landmark=s,
              horizon_years=h,support_status=su$status,reference_n=su$reference_n,supported_n=su$supported_n,
              coverage=su$coverage,result_status=this_reason),as.data.frame(as.list(values[k,])))
          }
        }
      }
      if(progress)say("Point analysis L",s,": two cause fits",paste(vapply(ff,function(f)f$meta$fit_success,logical(1)),collapse="/"))
    }
    list(results=do.call(rbind,result),fits=do.call(rbind,fits),support=do.call(rbind,supports))
  }
  read_crude <- function() {
    lines<-readLines(file.path(S$root,files[["stage1"]]),warn=FALSE,encoding="UTF-8")
    rows<-lapply(lines[grepl("| RISK_DIFFERENCE |",lines,fixed=TRUE)],function(line) {
      fields<-trimws(strsplit(line,"|",fixed=TRUE)[[1]]);fields<-fields[nzchar(fields)]
      data.frame(contrast=fields[3],landmark=as.integer(fields[1]),crude_GBC_delta_CIF=as.numeric(fields[4])/100,
        crude_GBC_lower95=as.numeric(fields[5])/100,crude_GBC_upper95=as.numeric(fields[6])/100)
    })
    out<-do.call(rbind,rows)
    assert(nrow(out)==18 && !anyNA(out) && !anyDuplicated(paste(out$contrast,out$landmark)),"Stage 1 crude table schema mismatch.")
    out
  }
  bootstrap <- function(d,point) {
    RNGkind("L'Ecuyer-CMRG");set.seed(CFG$seed)
    stream<-get(".Random.seed",envir=.GlobalEnv)
    for(i in seq_len(CFG$stream))stream<-parallel::nextRNGStream(stream)
    assign(".Random.seed",stream,envir=.GlobalEnv);S$initial_stream<-stream
    nr<-nrow(point$results);ns<-nrow(point$support);nf<-nrow(point$fits)
    values<-array(NA_real_,c(nr,length(measures),S$B),dimnames=list(key(point$results),measures,NULL))
    fit_ok<-matrix(FALSE,nf,S$B);ranks<-events<-matrix(NA_real_,nf,S$B)
    fixed_zero<-matrix(FALSE,nf,S$B);support_status<-matrix("FAIL",ns,S$B);coverage<-matrix(NA_real_,ns,S$B)
    errors<-character(S$B);fit_messages<-list()
    for(b in seq_len(S$B)) {
      draw<-sample.int(nrow(d),nrow(d),replace=TRUE);db<-d[draw,,drop=FALSE];db$cluster<-seq_len(nrow(db))
      assert(nrow(db)==nrow(d) && !anyDuplicated(db$cluster),"Bootstrap patient copies collapsed.")
      ev<-tryCatch(evaluate(db,point$support),error=function(e)e)
      if(inherits(ev,"error"))errors[b]<-conditionMessage(ev) else {
        assert(identical(key(ev$results),key(point$results)) && identical(support_key(ev$support),support_key(point$support)),"Bootstrap layout changed.")
        values[,,b]<-as.matrix(ev$results[measures]);fit_ok[,b]<-ev$fits$fit_success
        ranks[,b]<-ev$fits$actual_model_rank;events[,b]<-ev$fits$event_count
        fixed_zero[,b]<-nzchar(ev$fits$fixed_zero_unknown)
        support_status[,b]<-ev$support$status;coverage[,b]<-ev$support$coverage
        bad<-ev$fits[!ev$fits$fit_success,,drop=FALSE]
        if(nrow(bad))for(j in seq_len(nrow(bad))) {
          label<-paste0("L",bad$landmark[j]," / ",bad$cause[j],": ",bad$message[j])
          if(is.null(fit_messages[[label]]))fit_messages[[label]]<-0L
          fit_messages[[label]]<-fit_messages[[label]]+1L
        }
      }
      if(b==1L || b%%10L==0L || b==S$B)say("Patient bootstrap",b,"/",S$B)
    }
    list(values=values,fit_ok=fit_ok,ranks=ranks,events=events,fixed_zero=fixed_zero,
      support_status=support_status,coverage=coverage,errors=errors,fit_messages=fit_messages)
  }
  interval <- function(x) {
    ok<-is.finite(x);if(mean(ok)<.95)return(c(NA_real_,NA_real_))
    as.numeric(stats::quantile(x[ok],c(.025,.975),type=7,names=FALSE))
  }
  summarize <- function(point,boot,crude) {
    fit<-point$fits;fit$bootstrap_attempts<-S$B;fit$bootstrap_success_fraction<-rowMeans(boot$fit_ok)
    fit$bootstrap_failure_fraction<-1-fit$bootstrap_success_fraction
    fit$bootstrap_fixed_zero_unknown_fraction<-rowMeans(boot$fixed_zero)
    safe_min<-function(x)if(any(is.finite(x)))min(x[is.finite(x)]) else NA_real_
    safe_max<-function(x)if(any(is.finite(x)))max(x[is.finite(x)]) else NA_real_
    fit$bootstrap_rank_min<-apply(boot$ranks,1,safe_min);fit$bootstrap_rank_max<-apply(boot$ranks,1,safe_max)
    fit$bootstrap_events_min<-apply(boot$events,1,safe_min);fit$bootstrap_events_max<-apply(boot$events,1,safe_max)
    fit$stable<-fit$fit_success & fit$bootstrap_success_fraction>=.95
    su<-point$support;su$bootstrap_attempts<-S$B
    for(st in c("PASS","LIMITED","FAIL"))su[[paste0("bootstrap_",st,"_fraction")]]<-rowMeans(boot$support_status==st)
    su$bootstrap_coverage_mean<-apply(boot$coverage,1,function(v)if(any(is.finite(v)))mean(v[is.finite(v)]) else NA_real_)
    z<-point$results;z$bootstrap_attempts<-S$B
    joint<-vapply(CFG$landmarks,function(s)mean(apply(boot$fit_ok[fit$landmark==s,,drop=FALSE],2,all)),numeric(1))
    z$model_pair_stability<-joint[match(z$landmark,CFG$landmarks)]
    for(m in measures) {
      z[[paste0(m,"_lower95")]]<-NA_real_;z[[paste0(m,"_upper95")]]<-NA_real_
      z[[paste0(m,"_valid_fraction")]]<-rowMeans(is.finite(boot$values[,m,]))
    }
    for(i in seq_len(nrow(z))) {
      if(z$support_status[i]=="FAIL") {z[i,measures]<-NA_real_;next}
      stable<-all(fit$stable[fit$landmark==z$landmark[i]]) && z$model_pair_stability[i]>=.95
      if(!stable) {z[i,measures]<-NA_real_;z$result_status[i]<-"NOT ESTIMATED / MODEL STABILITY <95%";next}
      for(m in measures)if(is.finite(z[[m]][i]))z[i,c(paste0(m,"_lower95"),paste0(m,"_upper95"))]<-interval(boot$values[i,m,])
      if(z$result_status[i]=="OK" && min(z$delta_CIF_valid_fraction[i],z$delta_RMTL_months_valid_fraction[i])<.95)
        z$result_status[i]<-"POINT ESTIMATE ONLY / BOOTSTRAP CI <95% VALID"
    }
    z$lower95<-z$delta_CIF_lower95;z$upper95<-z$delta_CIF_upper95
    z$RMTL_lower95<-z$delta_RMTL_months_lower95;z$RMTL_upper95<-z$delta_RMTL_months_upper95
    z$bootstrap_valid_fraction<-pmin(z$delta_CIF_valid_fraction,z$delta_RMTL_months_valid_fraction)
    z$bootstrap_failure_fraction<-1-z$bootstrap_valid_fraction
    z$interpretation_allowed<-ifelse(z$support_status=="FAIL","FAIL_NOT_ESTIMATED",
      ifelse(!is.finite(z$delta_CIF),"MODEL_NOT_REPORTABLE",ifelse(z$support_status=="PASS","PASS_SUPPORTED","LIMITED_EXPLORATORY")))
    for(m in c("delta_CIF","delta_RMTL_months")) {
      label<-paste0(m,"_change_from_L0")
      z[[label]]<-z[[paste0(label,"_lower95")]]<-z[[paste0(label,"_upper95")]]<-NA_real_
      z[[paste0(label,"_valid_fraction")]]<-NA_real_
      for(i in seq_len(nrow(z))) {
        j<-which(z$target==z$target[i] & z$cause==z$cause[i] & z$horizon_years==z$horizon_years[i] & z$landmark==0)
        if(length(j)!=1 || !is.finite(z[[m]][i]) || !is.finite(z[[m]][j]))next
        v<-boot$values[i,m,]-boot$values[j,m,]
        z[[label]][i]<-z[[m]][i]-z[[m]][j];z[[paste0(label,"_valid_fraction")]][i]<-mean(is.finite(v))
        z[i,c(paste0(label,"_lower95"),paste0(label,"_upper95"))]<-interval(v)
      }
    }
    main<-z[z$horizon_years==3,,drop=FALSE];sens<-z[z$horizon_years==2,,drop=FALSE]
    trajectory<-su[,c("target","contrast","landmark","status","reference_n","supported_n","coverage")]
    names(trajectory)[names(trajectory)=="status"]<-"support_status"
    for(cause in CFG$causes) {
      a<-main[main$cause==cause,,drop=FALSE];j<-match(support_key(trajectory),support_key(a))
      for(m in c("delta_CIF","delta_RMTL_months","lower95","upper95","RMTL_lower95","RMTL_upper95",
        "delta_CIF_change_from_L0","delta_CIF_change_from_L0_lower95","delta_CIF_change_from_L0_upper95",
        "delta_RMTL_months_change_from_L0","delta_RMTL_months_change_from_L0_lower95","delta_RMTL_months_change_from_L0_upper95",
        "bootstrap_valid_fraction","result_status"))trajectory[[paste0(m,"_",cause)]]<-a[[m]][j]
      trajectory[[paste0("interpretation_",cause)]]<-a$interpretation_allowed[j]
    }
    trajectory$delta_RMTL_GBC<-trajectory$delta_RMTL_months_GBC
    trajectory$delta_RMTL_Other<-trajectory$delta_RMTL_months_Other
    trajectory$interpretation_allowed<-trajectory$interpretation_GBC
    j<-match(paste(trajectory$contrast,trajectory$landmark),paste(crude$contrast,crude$landmark))
    for(m in c("crude_GBC_delta_CIF","crude_GBC_lower95","crude_GBC_upper95"))trajectory[[m]]<-crude[[m]][j]
    plot<-do.call(rbind,lapply(c("delta_CIF","delta_RMTL_months"),function(m) {
      a<-z[,c("target","contrast","cause","landmark","horizon_years","support_status","coverage","reference_n","supported_n",
        "result_status","interpretation_allowed","bootstrap_valid_fraction")]
      a$metric<-m;a$estimate<-z[[m]];a$lower95<-z[[paste0(m,"_lower95")]];a$upper95<-z[[paste0(m,"_upper95")]]
      a$unit<-if(m=="delta_CIF")"probability difference" else "months";a$estimate_type<-"STANDARDIZED";a
    }))
    list(sheets=list(support=su,model_fit=fit,standardized_contrasts=main,sensitivity_2y=sens,
      trajectory_summary=trajectory,plot_ready=plot),all=z)
  }
  report_lines <- function(shaped,boot) {
    a<-shaped$sheets$standardized_contrasts;b<-shaped$sheets$sensitivity_2y
    su<-shaped$sheets$support;fit<-shaped$sheets$model_fit;tr<-shaped$sheets$trajectory_summary
    number<-function(x,digits=2)ifelse(is.finite(x),formatC(x,format="f",digits=digits),"NA")
    ci<-function(x,l,u,mult=1)paste0(number(mult*x)," [",number(mult*l),", ",number(mult*u),"]")
    table<-function(d) {
      d[]<-lapply(d,function(x)gsub("|","/",as.character(x),fixed=TRUE))
      c(paste0("| ",paste(names(d),collapse=" | ")," |"),
        paste0("| ",paste(rep("---",ncol(d)),collapse=" | ")," |"),
        apply(d,1,function(x)paste0("| ",paste(x,collapse=" | ")," |")),"")
    }
    lines<-c("# LM-specific measured-covariate-standardized conditional prognostic contrasts", "",
      paste("Completed:",format(Sys.time(),"%Y-%m-%d %H:%M:%S %Z")),"",
      "## Source and methods", "",
      "Frozen V2 main competing-risk cohort, diagnosis 2004-2015: n = 3918. No cohort definitions were changed.",
      "Each landmark uses actual survivors with follow-up strictly greater than the landmark. Future three years is primary; two years uses the same fitted models.",
      "Each landmark has two independently refitted cause-specific Cox models: 13 nominal regression df per cause. Age RCS knots 48/65/76/87 and basis scaling are frozen; diagnosis year = (year_dx - 2009.5)/5. Ridge theta=1, scale=FALSE applies only to Unknown T/N/Grade. Only identically zero penalized indicators may be fixed at zero; known effects are not penalized or removed.",
      "HIGH minus LOW is used throughout. Joint exponential-jump competing-risk integration gives CIF; the integral of that same right-continuous CIF gives cause-specific RMTL, reported in months. Positive values mean higher risk or greater cause-specific restricted time lost in HIGH, not a causal effect.", "",
      table(S$cohort[,c("landmark","n","GBC_events","Other_events","early_censored","at_3y")]),
      "## Common support", "",
      "Exact sex x other two pathology cells require >=5 independent source patients in both target levels, followed by the intersection of observed HIGH/LOW age ranges. Unknown remains an observed category. Reference means retain all bootstrap patient copies; unique identities are counted only for the support threshold.",
      "PASS >=90%: supported-reference standardization. LIMITED 70-<90%: exploratory overlap-restricted standardization only. FAIL <70%: NOT ESTIMATED / SUPPORT FAIL. No rescue or extrapolation is used.", "",
      table(data.frame(contrast=su$contrast,LM=su$landmark,reference_n=su$reference_n,supported_n=su$supported_n,
        coverage_percent=number(100*su$coverage),status=su$status)),
      "## Primary three-year contrasts", "",
      "CIF differences below are percentage points; Excel stores probability differences. RMTL differences are months within the future 36 months. Brackets are pointwise 95% percentile intervals; NA is unavailable, never zero. Valid rates include failed attempts in the denominator.", "",
      table(data.frame(contrast=a$contrast,LM=a$landmark,cause=a$cause,support=a$support_status,
        Delta_CIF_pp_95CI=ci(a$delta_CIF,a$lower95,a$upper95,100),
        Delta_RMTL_months_95CI=ci(a$delta_RMTL_months,a$RMTL_lower95,a$RMTL_upper95),
        valid_percent=number(100*a$bootstrap_valid_fraction),status=a$result_status)),
      "Grade L0/L1 are the only prespecified PASS cells. All T/N estimates and Grade L2-L5 estimates remain exploratory when reportable; FAIL cells are suppressed.", "",
      "## Descriptive attenuation assessment", "",
      "The endpoints below are fixed by the prespecified support audit, not chosen for a favorable result: T L0 to L4; N L0 to L2; Grade L0 to L5. Grade L0 to L1 is also assessed because both references have PASS support. Negative change means the signed HIGH-minus-LOW contrast decreased; it does not necessarily mean its absolute magnitude approached zero.",
      "Changes use paired bootstrap draws. References differ across landmarks and contrasts. These are descriptive between-reference differences, not a fixed-population time effect or a global trend test. No multiplicity-adjusted confirmatory inference is made.", "")
    planned<-data.frame(target=c("T","N","Grade","Grade"),end=c(4L,2L,5L,1L))
    evidence<-list()
    for(i in seq_len(nrow(planned))) {
      t<-planned$target[i];end<-planned$end[i]
      x<-a[a$target==t & a$cause=="GBC" & a$landmark==end,,drop=FALSE]
      x0<-a[a$target==t & a$cause=="GBC" & a$landmark==0,,drop=FALSE]
      c0<-tr$crude_GBC_delta_CIF[tr$target==t & tr$landmark==0]
      c1<-tr$crude_GBC_delta_CIF[tr$target==t & tr$landmark==end]
      dc<-x$delta_CIF_change_from_L0;dr<-x$delta_RMTL_months_change_from_L0
      available<-all(is.finite(c(x0$delta_CIF,x$delta_CIF,x0$delta_RMTL_months,x$delta_RMTL_months)))
      decline<-available && x0$delta_CIF>0 && x$delta_CIF>=0 && dc<0 &&
        x0$delta_RMTL_months>0 && x$delta_RMTL_months>=0 && dr<0
      precise<-decline && all(is.finite(c(x$delta_CIF_change_from_L0_upper95,x$delta_RMTL_months_change_from_L0_upper95))) &&
        x$delta_CIF_change_from_L0_upper95<0 && x$delta_RMTL_months_change_from_L0_upper95<0
      assessment<-if(!available)"Not assessable: support/model/estimation gate" else if(precise)
        "Concordant signed decline; both paired intervals below zero" else if(decline)
        "Concordant point decline; paired uncertainty does not establish both declines" else
        "No concordant nonnegative CIF/RMTL attenuation pattern"
      evidence[[i]]<-data.frame(contrast=targets[[t]]$label,comparison=paste0("L0 to L",end),
        support=paste(x0$support_status,x$support_status,sep=" / "),
        crude_CIF_change_pp=number(100*(c1-c0)),
        standardized_CIF_change_pp_95CI=ci(dc,x$delta_CIF_change_from_L0_lower95,x$delta_CIF_change_from_L0_upper95,100),
        standardized_RMTL_change_months_95CI=ci(dr,x$delta_RMTL_months_change_from_L0_lower95,x$delta_RMTL_months_change_from_L0_upper95),
        assessment=assessment,available=available,decline=decline,precise=precise)
    }
    ev<-do.call(rbind,evidence)
    lines<-c(lines,table(ev[,setdiff(names(ev),c("available","decline","precise"))]),
      "The crude GBC CIF contrasts and intervals were imported from the frozen Stage 1 report without rerunning it. Stage 1 uses its original full known-arm comparisons and seed 20260904; this module uses overlap-restricted references and seed 20260905. Differences between crude and standardized patterns can be compatible with survivor case-mix redistribution, but cannot isolate that mechanism because reference restriction also changes the estimand.", "",
      "## Two-year sensitivity and competing mortality", "",
      "Direction agreement below compares finite, reportable point estimates only. It does not establish equivalence, robustness of magnitude, or statistical significance. Full two-year intervals and support labels are in sensitivity_2y.", "")
    consistency<-list()
    for(t in names(targets))for(cause in CFG$causes)for(m in c("delta_CIF","delta_RMTL_months")) {
      x<-a[a$target==t & a$cause==cause,,drop=FALSE];y<-b[b$target==t & b$cause==cause,,drop=FALSE]
      y<-y[match(x$landmark,y$landmark),,drop=FALSE];ok<-is.finite(x[[m]]) & is.finite(y[[m]])
      consistency[[length(consistency)+1L]]<-data.frame(contrast=targets[[t]]$label,cause=cause,metric=m,
        comparable_LMs=sum(ok),same_direction_LMs=sum(sign(x[[m]][ok])==sign(y[[m]][ok])))
    }
    lines<-c(lines,table(do.call(rbind,consistency)))
    for(t in names(targets)) {
      g<-a[a$target==t & a$cause=="GBC",,drop=FALSE];o<-a[a$target==t & a$cause=="Other",,drop=FALSE]
      o<-o[match(g$landmark,o$landmark),,drop=FALSE];ok<-is.finite(g$delta_CIF)&is.finite(o$delta_CIF)
      opposite<-g$landmark[ok & g$delta_CIF*o$delta_CIF<0]
      lines<-c(lines,paste0(targets[[t]]$label,": opposite-sign GBC versus Other three-year CIF point contrasts at ",
        if(length(opposite))paste0("L",paste(opposite,collapse=", L")) else "no assessable landmark with opposite signs",
        " (",sum(ok)," comparable landmarks)."),"")
    }
    lines<-c(lines,"These opposing signs, when present, describe the balance of competing mortality probabilities; they do not imply protective biological effects or identify a mechanism.", "",
      "## Bootstrap and model stability", "",
      paste0(S$B," patient-level attempts; no replacement of failures. L'Ecuyer-CMRG seed ",CFG$seed,
        ", independent stream advance ",CFG$stream,". One source draw is shared across all landmarks, targets, causes and horizons."),
      "Every draw rebuilds survivor sets, both models, support masks and reference means. Each metric requires >=95% valid attempts for its percentile interval; otherwise CI=NA. A contrast also requires >=95% successful fitting for each cause and their joint pair. No model simplification is attempted.", "",
      table(data.frame(LM=fit$landmark,cause=fit$cause,events=fit$event_count,rank=fit$actual_model_rank,
        point_fit=fit$fit_success,bootstrap_fit_percent=number(100*fit$bootstrap_success_fraction),stable=fit$stable)),
      paste("Whole-draw errors:",sum(nzchar(boot$errors)),"of",S$B,"attempts."),
      "Support PASS/LIMITED/FAIL bootstrap fractions and model failure details are retained as aggregates in the workbook. No patient-level or bootstrap-draw files are exported.", "")
    if(length(boot$fit_messages)) {
      counts<-sort(unlist(boot$fit_messages),decreasing=TRUE);idx<-seq_len(min(5L,length(counts)))
      lines<-c(lines,"Most frequent model-fit failure messages:","",table(data.frame(message=names(counts)[idx],attempts=unname(counts[idx]))))
    }
    grade_pass<-ev$precise[planned$target=="Grade" & planned$end==1]
    label<-if(isTRUE(grade_pass))"PARTIAL" else if(any(ev$decline) || !all(ev$available))"LIMITED" else "NOT SUPPORTED"
    lines<-c(lines,"## Interpretation and conservative conclusion", "",
      "FIXED-REFERENCE STANDARDIZATION = NO-GO; NOT RUN. Prior common-intersection coverages were T 51.7%, N 59.2%, Grade 67.4%. No alternate reference or lowered threshold was used.",
      "Reportable wording is LM-specific survivor-conditioned measured-covariate-standardized conditional prognostic contrasts. Where the supported estimates and uncertainty justify it, one may write: measured-covariate-standardized conditional prognostic contrast diminished across supported landmark populations. Every such statement must retain PASS/LIMITED and changing-reference qualifications.",
      "Do not call these causal effects, treatment effects, biological memory decay, tumor effect disappearance or recurrence effects. No claim of a pure time effect in the same population is supported. A signed negative change alone is not proof of attenuation toward zero.",
      "Conservative descriptive rubric: PARTIAL requires nonnegative GBC CIF and RMTL contrasts declining from Grade L0 to L1 (both PASS), with both paired-change upper 95% limits below zero. LIMITED means only exploratory/uncertain concordant point declines or incomplete assessability. NOT SUPPORTED means all planned comparisons are assessable but none shows concordant nonnegative CIF/RMTL point attenuation; it is not proof of no association. STRONG is unavailable for the overall claim because T/N have no PASS reference and fixed-reference analysis is NO-GO. This rubric is not a confirmatory hypothesis test.", "",
      paste0("STANDARDIZED ATTENUATION SUPPORT = ",label), "",
      "Execution note: separate SMOKE, post-run inspection and plot generation were omitted at the user's latest request. Internal frozen-input, cohort, support and numerical gates remain part of the analysis; completion is not external validation.")
    lines
  }
  write_workbook <- function(sheets,path) {
    js<-r"---(import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
const req=createRequire(path.join(process.argv[1],'standardization_loader.cjs'));
const {Workbook,SpreadsheetFile}=await import(pathToFileURL(req.resolve('@oai/artifact-tool')).href);
const chunks=[];for await(const chunk of process.stdin)chunks.push(chunk);
const p=JSON.parse(Buffer.concat(chunks).toString('utf8'));
const wb=Workbook.create();
for(const [name,rows] of Object.entries(p.sheets)) {
 const fields=Object.keys(rows[0]);const sh=wb.worksheets.add(name);sh.showGridLines=false;
 sh.getRange('A2').values=[[name.replaceAll('_',' ').toUpperCase()]];
 sh.getRange('A2').format.font={name:'Arial',size:14,bold:true,color:'#23415B'};
 sh.getRange('A3').values=[['FORMAL: 1000 PATIENT BOOTSTRAP ATTEMPTS / LM-SPECIFIC REFERENCES / HIGH MINUS LOW']];
 sh.getRange('A3').format.font={name:'Arial',size:10,bold:true,color:'#23415B'};
 sh.getRange('A4').values=[['CIF/risk = probability; RMTL = months; 3y primary / 2y sensitivity. Blanks unavailable, never zero. LIMITED exploratory; FAIL not estimated.']];
 sh.getRange('A4').format.font={name:'Arial',size:9,color:'#555555'};
 sh.getRangeByIndexes(4,0,1,fields.length).values=[fields];
 sh.getRangeByIndexes(5,0,rows.length,fields.length).values=rows.map(r=>fields.map(k=>r[k]??null));
 const all=sh.getRangeByIndexes(4,0,rows.length+1,fields.length);
 all.format.font={name:'Arial',size:10,color:'#243347'};all.format.rowHeight=20;all.format.verticalAlignment='center';
 const head=sh.getRangeByIndexes(4,0,1,fields.length);
 head.format.fill='#304F70';head.format.font={name:'Arial',size:10,bold:true,color:'#FFFFFF'};
 head.format.wrapText=true;head.format.rowHeight=48;head.format.horizontalAlignment='center';
 for(let j=0;j<fields.length;j++) {
  const key=fields[j],vals=rows.map(r=>r[key]).filter(v=>v!==null&&v!==undefined);
  const numeric=vals.length>0&&vals.every(v=>typeof v==='number');let width=key.length>24?27:20;
  if(['target','cause','landmark','horizon_years'].includes(key))width=12;
  if(/contrast|status|interpretation/.test(key))width=36;
  if(/message|ridge_state/.test(key))width=75;
  sh.getRangeByIndexes(4,j,rows.length+1,1).format.columnWidth=width;
  const col=sh.getRangeByIndexes(5,j,rows.length,1);col.format.horizontalAlignment=numeric?'right':'left';
  if(numeric) {
   const integer=/^(landmark|horizon_years|n|independent_patients|nominal_regression_df|active_columns|actual_model_rank|event_count|at_3y|baseline_jumps|iterations|adequate_cells|age_overlap_cells|bootstrap_attempts)$/.test(key)||/_n$/.test(key)||/^bootstrap_(rank|events)_(min|max)$/.test(key);
   col.setNumberFormat(integer?'0':/RMTL/.test(key)&&!/fraction/.test(key)?'0.00':'0.0000');
  }
 }
 sh.freezePanes.freezeRows(5);
}
wb.recalculate();
const out=await SpreadsheetFile.exportXlsx(wb);
await fs.writeFile(process.argv[2],out.data,{flag:'wx'});
console.log('STANDARDIZATION WORKBOOK EXPORTED: '+Object.keys(p.sheets).join(', '));
)---"
    payload<-jsonlite::toJSON(list(sheets=sheets),auto_unbox=TRUE,dataframe="rows",na="null",digits=16)
    child<-processx::process$new(S$node,c("--input-type=module","-e",js,S$modules,path),
      stdin="|",stdout="|",stderr="2>&1",windows_hide_window=TRUE,encoding="UTF-8",cleanup=TRUE)
    on.exit({if(child$is_alive())child$kill()},add=TRUE)
    output<-character();started<-Sys.time()
    drain<-function() {
      output<<-c(output,child$read_output())
      assert(as.numeric(difftime(Sys.time(),started,units="secs"))<600,"Workbook export exceeded 10 minutes.")
    }
    bytes<-charToRaw(enc2utf8(as.character(payload)))
    for(first in seq.int(1L,length(bytes),by=65536L)) {
      pending<-bytes[first:min(first+65535L,length(bytes))]
      while(length(pending)) {
        assert(child$is_alive(),paste("Workbook child exited while reading input:",paste(output,collapse="")))
        pending<-child$write_input(pending);drain()
        if(length(pending))child$poll_io(10L)
      }
    }
    close(child$get_input_connection())
    while(child$is_alive()) {child$poll_io(500L);drain()}
    drain();code<-child$get_exit_status()
    assert(identical(code,0L),paste("Workbook export failed; status:",code,";",paste(output,collapse="")))
    say(trimws(paste(output,collapse="")))
    invisible(path)
  }
  run <- function() {
    old_kind<-RNGkind();had_seed<-exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE)
    if(had_seed)old_seed<-get(".Random.seed",envir=.GlobalEnv)
    on.exit({
      do.call(RNGkind,as.list(old_kind))
      if(had_seed)assign(".Random.seed",old_seed,envir=.GlobalEnv) else if(exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE))
        rm(".Random.seed",envir=.GlobalEnv)
    },add=TRUE)
    setup();d<-read_data();crude<-read_crude();su<-all_support(d)
    expected<-list(T=c(rep("LIMITED",5),"FAIL"),N=c(rep("LIMITED",3),rep("FAIL",3)),
      Grade=c("PASS","PASS",rep("LIMITED",4)))
    for(t in names(targets))assert(identical(su$status[su$target==t],expected[[t]]),
      paste("STOP: original support status differs from frozen audit for",t,"; rules must not be relaxed."))
    say("Original support audit matched all 18 prespecified cells; fixed reference NOT RUN.")
    point<-evaluate(d,progress=TRUE)
    assert(identical(point$support$status,su$status),"Point support audit changed.")
    boot<-bootstrap(d,point);shaped<-summarize(point,boot,crude)
    report<-report_lines(shaped,boot)
    hashes()
    assert(!any(file.exists(S$paths)),"Output appeared during analysis; refusing overwrite.")
    write_workbook(shaped$sheets,S$paths[1])
    writeLines(enc2utf8(report),S$paths[2],useBytes=TRUE)
    S$results<-shaped$sheets
    say("FORMAL STANDARDIZATION COMPLETE. Outputs:",paste(S$paths,collapse=" ; "))
    invisible(S$results)
  }
  environment()
})

if(identical(Sys.getenv("GBC_STANDARDIZATION_STARTUP"),"1")) {
  .First <- function() {
    Sys.unsetenv(c("GBC_STANDARDIZATION_STARTUP","R_PROFILE_USER"))
    gbc_standardization$run()
  }
} else if(isTRUE(getOption("gbc.standardization.autorun", FALSE))) {
  gbc_standardization$run()
}


