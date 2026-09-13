# Publication source copy. See docs/original_script_mapping.md and reproducibility_notes.md.

CFG <- list(seed=20260905L, knots=c(48,65,76,87), tau=3,
  hashes=c(patient="b8bb4d6d7a5c00924aedd9383c3be4ba22c7b0c1060d72288be64207d88fd870",
           landmark="6d7ebcc62aa2da953ccdada3cce61ab366bcd0dfde0b24d7349bdafa5efe5da1",
           sap="9a5e363afb395fe86d12ddc94817b4d727af74dae0dc27946acb6d00c79c328d"),
  versions=c(survival="3.8.3",Hmisc="5.2.3",riskRegression="2023.12.21",
             prodlim="2025.4.28",jsonlite="2.0.0",digest="0.6.37"))
STATE <- new.env(parent=emptyenv())
STATE$stage <- "START"; STATE$completed <- character(); STATE$counts <- list()
STATE$hashes <- list(); STATE$checkpoint <- "NONE"; STATE$mode <- "NOT PARSED"
STATE$started <- Sys.time(); STATE$trace <- character(); STATE$cache <- list()

assert <- function(ok, message) {
  if (length(ok)!=1L || is.na(ok) || !ok) stop(message,call.=FALSE)
  invisible(TRUE)
}
fit_failure <- function(message) {
  stop(structure(list(message=message,call=NULL),class=c("fit_failure","error","condition")))
}
numerical_try <- function(expr) tryCatch(list(ok=TRUE,value=force(expr),message=""),
  fit_failure=function(e) list(ok=FALSE,value=NULL,message=conditionMessage(e)))
stamp <- function() format(Sys.time(),"%Y-%m-%d %H:%M:%S %z")
log_line <- function(text) {
  line <- paste(stamp(),"|",STATE$mode,"|",STATE$stage,"|",text)
  cat(line,"\n"); flush.console()
  if (!is.null(STATE$log)) {
    con <- file(STATE$log,open="at",encoding="UTF-8")
    writeLines(line,con,useBytes=TRUE); flush(con); close(con)
  }
}
stage <- function(name, expr) {
  STATE$stage <- name; start <- Sys.time(); STATE$stage_started<-start; log_line("BEGIN")
  value <- force(expr)
  log_line(sprintf("END PASS elapsed_seconds=%.2f",as.numeric(difftime(Sys.time(),start,units="secs"))))
  STATE$completed <- unique(c(STATE$completed,name)); value
}
write_error <- function(e) {
  if (is.null(STATE$root)) STATE$root <- getwd()
  dir.create(file.path(STATE$root,"logs"),showWarnings=FALSE,recursive=TRUE)
  dest <- file.path(STATE$root,"logs","ERROR_REPORT.txt")
  last <- if (!is.null(STATE$log) && file.exists(STATE$log)) tail(readLines(STATE$log,warn=FALSE),200) else "No live log available"
  report <- c("ANALYSIS FAILED",paste("Time:",stamp()),paste("Started:",STATE$started),
    paste("Stage:",STATE$stage),paste("Mode:",STATE$mode),paste("R:",R.version.string),
    paste("Seed:",CFG$seed),paste("Message:",conditionMessage(e)),
    "Packages:",capture.output(print(STATE$packages)),"Input SHA256:",capture.output(print(STATE$hashes)),
    paste("Completed stages:",paste(STATE$completed,collapse=", ")),
    "Bootstrap completed counts:",capture.output(print(STATE$counts)),
    paste("Last successful checkpoint:",STATE$checkpoint),"Call stack / traceback:",STATE$trace,
    "Last 200 live log lines:",last)
  writeLines(report,dest,useBytes=TRUE)
  elapsed<-if(is.null(STATE$stage_started))NA_real_ else as.numeric(difftime(Sys.time(),STATE$stage_started,units="secs"))
  log_line(paste("END FAIL elapsed_seconds=",round(elapsed,2),conditionMessage(e)))
}
checkpoint_save <- function(key,value) {
  STATE$cache[[key]] <- value
  obj <- list(fingerprint=STATE$fingerprint,cache=STATE$cache,counts=STATE$counts,
              completed=STATE$completed,saved=stamp())
  tmp <- file.path(STATE$temp,"checkpoint.new.rds")
  current <- file.path(STATE$temp,"checkpoint.rds"); previous <- file.path(STATE$temp,"checkpoint.previous.rds")
  saveRDS(obj,tmp,compress=FALSE)
  if (file.exists(previous)) unlink(previous)
  if (file.exists(current)) assert(file.rename(current,previous),"Cannot rotate checkpoint")
  assert(file.rename(tmp,current),"Cannot commit checkpoint")
  STATE$checkpoint <- current
  invisible(value)
}
checkpoint_get <- function(key, expr) {
  if (!is.null(STATE$cache[[key]])) { log_line(paste("RESUME",key)); return(STATE$cache[[key]]) }
  value <- force(expr); checkpoint_save(key,value); value
}
checkpoint_load <- function(directory,fingerprint) {
  for(f in c("checkpoint.rds","checkpoint.previous.rds")) {
    path<-file.path(directory,f)
    if(file.exists(path)) {
      cp<-tryCatch(readRDS(path),error=function(e)NULL)
      if(!is.null(cp) && identical(cp$fingerprint,fingerprint))return(list(path=path,state=cp))
    }
  }
  NULL
}
guard_development <- function(d) {
  assert(is.data.frame(d) && nrow(d)>0L,"Empty or invalid development input")
  assert(all(!is.na(d$year_dx) & d$year_dx>=2004 & d$year_dx<=2011),
         "FIREWALL: every fitting/evaluation row must be 2004-2011")
  invisible(TRUE)
}
environment_check <- function() {
  assert(as.character(getRversion())=="4.4.3","Use the locked R 4.4.3 executable")
  for (p in names(CFG$versions)) {
    assert(requireNamespace(p,quietly=TRUE),paste("Missing package:",p,"(no auto-install)"))
    assert(utils::compareVersion(as.character(utils::packageVersion(p)),CFG$versions[[p]])==0,
           paste("Locked package version mismatch:",p))
  }
  suppressPackageStartupMessages(library(survival))
  STATE$packages <- vapply(names(CFG$versions),function(p)as.character(utils::packageVersion(p)),character(1))
  localapp <- Sys.getenv("GBC_USER_LIBRARY_ROOT"); profile <- Sys.getenv("GBC_RUNTIME_ROOT")
  STATE$python <- Sys.getenv("GBC_PYTHON")
  runtime <- Sys.getenv("GBC_RUNTIME_ROOT")
  STATE$node <- file.path(runtime,"node","bin","node.exe")
  STATE$modules <- file.path(runtime,"node","node_modules")
  STATE$audit_python<-file.path(runtime,"python","python.exe")
  for (p in c(STATE$python,STATE$node,STATE$modules,STATE$audit_python)) assert(file.exists(p),paste("Missing local dependency:",p))
  probe <- system2(STATE$python,c("-c",shQuote("import pyarrow,pandas; print(pyarrow.__version__); print(pandas.__version__)")),stdout=TRUE,stderr=TRUE)
  assert(is.null(attr(probe,"status")),paste("Parquet dependency check failed:",paste(probe,collapse=" ")))
  STATE$python_versions <- probe
  audit<-system2(STATE$audit_python,c("-c",shQuote("import openpyxl; print(openpyxl.__version__)")),stdout=TRUE,stderr=TRUE)
  assert(is.null(attr(audit,"status")),"Missing independent workbook reader (openpyxl)")
  log_line(paste("Locked R/packages OK; Parquet reader",paste(probe,collapse=" / ")))
  list(R=R.version.string,packages=STATE$packages,python=probe,openpyxl=audit,node=system2(STATE$node,"--version",stdout=TRUE))
}
hash_check <- function() {
  files <- c(patient="data/analysis_patient_level_v2.parquet",landmark="data/analysis_landmark_long_v2.parquet",sap="spec/SAP_TECHNICAL_ADDENDUM_v1.1.md")
  actual <- vapply(files,function(f)digest::digest(file=file.path(STATE$root,f),algo="sha256"),character(1))
  STATE$hashes <- actual
  assert(identical(unname(actual),unname(CFG$hashes)),"SHA256 mismatch: STOP; no repair or recleaning")
  STATE$fingerprint <- digest::digest(list(root=STATE$root,code=digest::digest(file=STATE$script,algo="sha256"),
    hashes=actual,environment=STATE$environment,mode=STATE$mode,B=STATE$B,seed=CFG$seed),algo="sha256")
  STATE$temp <- file.path(Sys.getenv("TEMP"),"gbc_final_run",STATE$mode,STATE$fingerprint)
  dir.create(STATE$temp,recursive=TRUE,showWarnings=FALSE)
  resumed<-checkpoint_load(STATE$temp,STATE$fingerprint)
  if(!is.null(resumed)) {
    STATE$cache<-resumed$state$cache;STATE$counts<-resumed$state$counts;STATE$checkpoint<-resumed$path
    log_line(paste("Matched checkpoint",resumed$path))
  }
  log_line(paste("Hashes PASS; temporary outputs/checkpoints:",STATE$temp))
  actual
}
load_data <- function() {
  helper <- file.path(STATE$temp,"read_development.py")
  code <- r"---(import json,sys
from pathlib import Path
import pyarrow.parquet as pq
root=Path(sys.argv[1]); out=Path(sys.argv[2])
cols=['patient_id','record_id','year_dx','age_dx','age_90plus_flag','sex','T_model','N_model','grade_model','survival_days_analysis','event_competing','M_harmonized']
flt=[('year_dx','>=',2004),('year_dx','<=',2011)]
p=pq.read_table(root/'data/analysis_patient_level_v2.parquet',columns=cols,filters=flt).to_pandas()
lc=['patient_id','record_id','year_dx','landmark_year','time_from_landmark','time_to_analysis_end','event_within_window','analysis_role']
l=pq.read_table(root/'data/analysis_landmark_long_v2.parquet',columns=lc,filters=flt+[('analysis_role','==','PREDICTION_PREP')]).to_pandas()
assert p.year_dx.between(2004,2011).all() and l.year_dx.between(2004,2011).all()
meta={name:{'rows':pq.ParquetFile(root/'data'/name).metadata.num_rows,'columns':len(pq.read_schema(root/'data'/name))} for name in ['analysis_patient_level_v2.parquet','analysis_landmark_long_v2.parquet']}
out.write_text(json.dumps({'patient':json.loads(p.to_json(orient='records')),'landmark':json.loads(l.to_json(orient='records')),'metadata':meta}),encoding='utf-8')
)---"
  writeLines(code,helper,useBytes=TRUE)
  json <- file.path(STATE$temp,"development_input.tmp.json")
  on.exit(if(file.exists(json))unlink(json),add=TRUE)
  status <- system2(STATE$python,c(shQuote(helper),shQuote(STATE$root),shQuote(json)),stdout=TRUE,stderr=TRUE)
  assert(is.null(attr(status,"status")),paste("Development read failed",paste(status,collapse=" ")))
  obj <- jsonlite::fromJSON(json)
  d <- obj$patient; guard_development(d)
  d$time <- d$survival_days_analysis/365.25; d$status <- as.integer(d$event_competing)
  d$T_core <- ifelse(d$T_model %in% c("Unknown","Unknown/nonstandard"),"Unknown",d$T_model)
  d$cluster <- seq_len(nrow(d))
  list(patient=d,landmark=obj$landmark,metadata=obj$metadata)
}
make_landmarks <- function(d) {
  guard_development(d)
  ans <- lapply(1:3,function(s) {
    z <- d[d$time>s,,drop=FALSE]; z$lm <- s; z$sc <- s-2
    z$u <- z$time-s; z$stop <- pmin(z$u,CFG$tau); z$start <- 0
    z$event <- ifelse(z$u<=CFG$tau,z$status,0L); z
  })
  do.call(rbind,ans)
}
check_data <- function(obj) {
  d <- obj$patient; l <- obj$landmark; guard_development(l)
  assert(nrow(d)==2384 && !anyDuplicated(d$patient_id) && !anyDuplicated(d$record_id),"Frozen development source count/ID mismatch")
  assert(obj$metadata[[1]]$rows==7007 && obj$metadata[[1]]$columns==172 &&
         obj$metadata[[2]]$rows==18749 && obj$metadata[[2]]$columns==189,"Frozen Parquet metadata mismatch")
  assert(!anyNA(d) && all(is.finite(d$time)) && all(d$time>0) && all(d$status %in% 0:2),"Missing or invalid frozen data")
  assert(all(d$M_harmonized=="M0"),"Frozen explicit M0 mismatch")
  for (entry in list(c("sex","Female","Male"),c("T_core","T1","T2","T3/4","Unknown"),
                     c("N_model","N0","N+","Unknown"),c("grade_model","G1","G2","G3/4","Unknown")))
    assert(all(d[[entry[1]]] %in% entry[-1]),paste("Invalid registry state:",entry[1]))
  assert(all(d$age_dx[d$age_90plus_flag]==90),"Top-coded age must remain 90")
  lm <- make_landmarks(d)
  assert(nrow(lm)==3275 && nrow(l)==3275,"Prediction-role development row count mismatch")
  key <- function(id,s) paste(id,s,sep="|")
  j <- match(key(lm$record_id,lm$lm),key(l$record_id,l$landmark_year))
  assert(!anyNA(j) && !anyDuplicated(key(l$record_id,l$landmark_year)),"Stored landmark keys mismatch")
  assert(max(abs(l$time_from_landmark[j]/365.25-lm$u))<1e-8 &&
    max(abs(l$time_to_analysis_end[j]/365.25-lm$stop))<1e-8 &&
    all(l$event_within_window[j]==lm$event),"Stored/rebuilt window time or event mismatch")
  counts <- do.call(rbind,lapply(1:3,function(s) {
    x<-lm[lm$lm==s,]; data.frame(scope=paste0("L",s),patients=nrow(x),GBC=sum(x$event==1),
      Other=sum(x$event==2),early_censor=sum(x$status==0 & x$u<3))
  }))
  assert(identical(counts$patients,c(1468L,1014L,793L)) && all(counts$GBC==c(590,291,151)) &&
    all(counts$Other==c(200,131,116)) && all(counts$early_censor==c(16,15,12)),"Frozen landmark denominator mismatch")
  assert(sum(d$time>1 & d$status==1)==711 && sum(d$time>1 & d$status==2)==484,"A full-follow-up event mismatch")
  assert(all(vapply(1:2,function(k)length(unique(lm$record_id[lm$event==k])),integer(1))==c(662,268)),"Unique stacked event union mismatch")
  assert(all(as.numeric(quantile(d$age_dx[d$time>1],c(.05,.35,.65,.95),type=7))==CFG$knots),"Locked age knots mismatch")
  log_line("DATA PASS: development source=2384; L1/L2/L3=1468/1014/793; stacked=3275; validation NOT LOADED")
  counts
}
make_rcs <- function(age) {
  b <- Hmisc::rcspline.eval(age,knots=CFG$knots,inclx=TRUE,norm=2)
  ref <- Hmisc::rcspline.eval(70,knots=CFG$knots,inclx=TRUE,norm=2)
  b <- sweep(b,2,as.numeric(ref),"-")/10
  colnames(b) <- c("Age_linear","Age_rcs1","Age_rcs2"); b
}
design_matrix <- function(d,model,cause) {
  age <- make_rcs(d$age_dx)
  x <- cbind(age,Male=as.numeric(d$sex=="Male"),T2=as.numeric(d$T_core=="T2"),
    T34=as.numeric(d$T_core=="T3/4"),Nplus=as.numeric(d$N_model=="N+"),
    G2=as.numeric(d$grade_model=="G2"),G34=as.numeric(d$grade_model=="G3/4"),
    T_unknown=as.numeric(d$T_core=="Unknown"),N_unknown=as.numeric(d$N_model=="Unknown"),
    G_unknown=as.numeric(d$grade_model=="Unknown"))
  penalty <- c(rep(FALSE,9),rep(TRUE,3))
  if (model %in% c("C_FULL","C_REDUCED")) {
    if (cause==1L) {
      names <- if(model=="C_FULL") c("T2","T34","Nplus","G2","G34") else c("T34","Nplus")
      inter <- x[,names,drop=FALSE]*d$sc; colnames(inter) <- paste0(names,"_by_s")
    } else inter <- matrix((d$age_dx-70)/10*d$sc,ncol=1,dimnames=list(NULL,"Age10_by_s"))
    x <- cbind(x,inter); penalty <- c(penalty,rep(TRUE,ncol(inter)))
  }
  list(x=x,penalty=penalty)
}
model_data <- function(d,model) {
  guard_development(d)
  if(model=="A") {
    x<-d[d$time>1,,drop=FALSE]; x$lm<-1L; x$sc<- -1; x$start<-1; x$stop<-x$time; x$event<-x$status; x
  } else make_landmarks(d)
}
cox_checked <- function(formula,frame,tv=FALSE,origin=0) {
  warnings <- character()
  fit <- withCallingHandlers(
    coxph(formula,data=frame,ties="breslow",x=TRUE,y=TRUE,model=!tv,
          robust=FALSE,singular.ok=FALSE,
          control=coxph.control(iter.max=60,eps=1e-9),
          tt=if(tv)function(x,t,...)x*log(pmax(t-origin,.25)) else NULL),
    warning=function(w) {
      msg<-conditionMessage(w)
      if(grepl("converg|infinite|singular|overflow|NaN",msg,ignore.case=TRUE)) fit_failure(msg)
      warnings<<-c(warnings,msg); invokeRestart("muffleWarning")
    })
  if(any(!is.finite(coef(fit))) || any(!is.finite(fit$var))) fit_failure("Nonfinite Cox coefficient/information")
  fit$captured_warnings<-warnings; fit
}
baseline_information <- function(md,x,beta,cause,tv=NULL,delta=0,information=FALSE) {
  base <- list(); p<-ncol(x); info<-matrix(0,p+as.integer(!is.null(tv)),p+as.integer(!is.null(tv)))
  score<-numeric(nrow(info))
  eta <- drop(x%*%beta)
  for (s in sort(unique(md$lm))) {
    ids<-which(md$lm==s); stop<-md$stop[ids]; start<-md$start[ids]; e<-md$event[ids]==cause
    times<-sort(unique(stop[e])); if(!length(times))fit_failure("No baseline events in a required stratum")
    xx<-x[ids,,drop=FALSE]; lp<-eta[ids]; count<-tabulate(match(stop[e],times),length(times))
    haz<-numeric(length(times)); origin<-if(all(start==1))1 else 0
    z<-if(!is.null(tv)) if(tv=="age") (md$age_dx[ids]-70)/10 else as.numeric(md$T_core[ids]=="T3/4") else rep(0,length(ids))
    if(is.null(tv) && !information) {
      ord<-order(stop,decreasing=TRUE); sums<-cumsum(exp(lp[ord])); unique_stop<-!duplicated(stop[ord],fromLast=TRUE)
      lookup<-setNames(sums[unique_stop],as.character(stop[ord][unique_stop])); den<-unname(lookup[as.character(times)])
      haz<-count/den
    } else for(j in seq_along(times)) {
      risk<-which(start<times[j] & stop>=times[j]); q<-log(pmax(times[j]-origin,.25))
      xr<-xx[risk,,drop=FALSE]; if(!is.null(tv))xr<-cbind(xr,z[risk]*q)
      w<-exp(lp[risk]+delta*z[risk]*q); den<-sum(w); haz[j]<-count[j]/den
      if(information) {
        m<-colSums(xr*w)/den
        info<-info+count[j]*(crossprod(xr,xr*w)/den-tcrossprod(m))
        event_rows<-which(stop==times[j] & e)
        xe<-xx[event_rows,,drop=FALSE];if(!is.null(tv))xe<-cbind(xe,z[event_rows]*q)
        score<-score+colSums(xe)-count[j]*m
      }
    }
    if(any(!is.finite(haz)) || any(haz<0))fit_failure("Nonfinite/negative Breslow increment")
    base[[as.character(s)]]<-data.frame(time=times,hazard=haz,events=count)
  }
  list(baseline=base,information=info,score=score)
}
fit_cause <- function(d,model,cause,theta=1,tv=NULL,full=FALSE) {
  guard_development(d); md<-model_data(d,model); dm<-design_matrix(md,model,cause)
  fixed<-dm$penalty & colSums(abs(dm$x))==0
  keep<-which(!fixed); x<-dm$x[,keep,drop=FALSE]; pen<-dm$penalty[keep]
  frame<-data.frame(start=md$start,stop=md$stop,death=as.integer(md$event==cause),lm=factor(md$lm))
  frame$Age<-I(x[,1:3,drop=FALSE])
  for(n in c("Male","T2","T34","Nplus","G2","G34")) frame[[n]]<-x[,n]
  rhs<-"Age + Male + T2 + T34 + Nplus + G2 + G34"
  u<-intersect(c("T_unknown","N_unknown","G_unknown"),colnames(x))
  ii<-grep("_by_s$",colnames(x),value=TRUE)
  if(length(u)) {frame$U<-I(x[,u,drop=FALSE]);rhs<-paste(rhs,sprintf("+ ridge(U,theta=%.17g,scale=FALSE)",theta))}
  if(length(ii)) {frame$I<-I(x[,ii,drop=FALSE]);rhs<-paste(rhs,sprintf("+ ridge(I,theta=%.17g,scale=FALSE)",theta))}
  if(model!="A")rhs<-paste(rhs,"+ strata(lm)")
  if(!is.null(tv)) {
    frame$Z<-if(tv=="age")(md$age_dx-70)/10 else as.numeric(md$T_core=="T3/4")
    rhs<-paste(rhs,"+ tt(Z)")
  }
  formula<-as.formula(paste("Surv(start,stop,death) ~",rhs),env=.GlobalEnv)
  fit<-tryCatch(cox_checked(formula,frame,!is.null(tv),if(model=="A")1 else 0),
    error=function(e) {
      if(inherits(e,"fit_failure"))stop(e)
      if(grepl("singular|infinite|converg|no observations|non-missing|NA/NaN/Inf",conditionMessage(e),ignore.case=TRUE))fit_failure(conditionMessage(e))
      stop(e)
    })
  beta<-coef(fit)[seq_len(ncol(x))]; names(beta)<-colnames(x)
  assert(length(coef(fit))==ncol(x)+as.integer(!is.null(tv)),"Cox/design dimension mismatch")
  if(is.null(tv)) assert(max(abs(unname(fit$x)-unname(x)))<1e-10,"Cox/design column order mismatch")
  delta<-if(is.null(tv))0 else unname(tail(coef(fit),1))
  bi<-baseline_information(md,x,beta,cause,tv,delta,information=full)
  support<-tapply(md$stop,md$lm,max)
  if(any(support<if(model=="A")6 else 3))fit_failure("No training follow-up support at required horizon")
  edf<-NA_real_; condition<-NA_real_; score_error<-NA_real_
  if(full) {
    P<-diag(c(as.numeric(pen)*theta,if(!is.null(tv))0),nrow(bi$information))
    score_error<-max(abs(bi$score-drop(P%*%c(beta,if(!is.null(tv))delta))))
    if(!is.finite(score_error) || score_error>1e-3)fit_failure("Independent penalized score equation check failed")
    IP<-bi$information+P; condition<-kappa(IP,exact=TRUE)
    if(!is.finite(condition) || rcond(IP)<1e-12)fit_failure("Unresolved singular penalized information")
    edf<-sum(diag(solve(IP,bi$information)))
    assert(is.finite(edf) && edf<=nrow(IP)+1e-6 && edf>=0,"Effective df trace is invalid")
  }
  fullbeta<-setNames(numeric(ncol(dm$x)),colnames(dm$x)); fullbeta[keep]<-beta
  result<-list(model=model,cause=cause,beta=fullbeta,penalized=dm$penalty,theta=theta,
    baseline=bi$baseline,support=support,tv=tv,delta=delta,effective_df=edf,
    package_df=if(is.null(fit$df))length(coef(fit)) else sum(fit$df),information_condition=condition,score_error=score_error,
    fixed_zero=names(fullbeta)[fixed],formula=deparse(formula,width.cutoff=500),
    baseline_jumps=sum(vapply(bi$baseline,nrow,integer(1))),
    n=nrow(md),unique_patients=length(unique(md$cluster)),events=sum(md$event==cause),
    warnings=fit$captured_warnings)
  if(full) { result$fit<-fit; result$event_lm<-md$lm[md$event==cause][order(md$stop[md$event==cause])]; result$information<-bi$information }
  result
}
fit_pair <- function(d,model,theta=1,tv=c(NA_character_,NA_character_),full=FALSE) {
  guard_development(d)
  ans<-lapply(1:2,function(k)fit_cause(d,model,k,theta,if(is.na(tv[k]))NULL else tv[k],full))
  names(ans)<-c("GBC","Other"); ans
}
fit_model_a <- function(d,...)fit_pair(d,"A",...)
fit_model_b <- function(d,...)fit_pair(d,"B",...)
fit_model_c <- function(d,reduced=FALSE,...)fit_pair(d,if(reduced)"C_REDUCED" else "C_FULL",...)

integrate_grid <- function(times,a1,a2,lower,upper,observed_end=NULL) {
  n<-nrow(a1); S<-rep(1,n); F1<-F2<-L1<-L2<-rep(0,n); before<-lower
  for(j in which(times>lower & times<=upper)) {
    dt<-times[j]-before; L1<-L1+F1*dt; L2<-L2+F2*dt; before<-times[j]
    a<-a1[,j]+a2[,j]; share<-ifelse(a>0,-expm1(-a)/a,1)
    F1<-F1+S*share*a1[,j]; F2<-F2+S*share*a2[,j]; S<-S*exp(-a)
  }
  L1<-L1+F1*(upper-before); L2<-L2+F2*(upper-before)
  ans<-cbind(GBC=F1,Other=F2,Survival=S,RMTL_GBC=L1,RMTL_Other=L2)
  if(any(!is.finite(ans)) || any(ans< -1e-12) || max(abs(rowSums(ans[,1:3,drop=FALSE])-1))>=1e-10)
    fit_failure("Competing-risk probability closure/nonnegative check failed")
  ans
}
predict_competing_risk <- function(pair,d,s,horizon=3,with_hazard=FALSE) {
  guard_development(d); assert(all(d$time>s),"Evaluation rows must survive landmark strictly")
  model<-pair[[1]]$model; nd<-d; nd$lm<-s; nd$sc<-s-2
  origin<-if(model=="A")s else 0; end<-origin+horizon
  base<-lapply(pair,function(f)f$baseline[[as.character(if(model=="A")1 else s)]])
  if(any(vapply(pair,function(f)f$support[[as.character(if(model=="A")1 else s)]]<end,logical(1))))fit_failure("Unsupported prediction horizon")
  times<-sort(unique(c(base[[1]]$time,base[[2]]$time))); times<-times[times<=end]
  a<-lapply(1:2,function(k) {
    f<-pair[[k]]; dm<-design_matrix(nd,model,k); lp<-drop(dm$x%*%f$beta)
    h<-base[[k]]$hazard[match(times,base[[k]]$time)]; h[is.na(h)]<-0
    z<-if(is.null(f$tv))rep(0,nrow(nd)) else if(f$tv=="age")(nd$age_dx-70)/10 else as.numeric(nd$T_core=="T3/4")
    q<-log(pmax(times-if(model=="A")1 else 0,.25))
    exp(lp+outer(z*f$delta,q))*rep(h,each=nrow(nd))
  })
  ans<-integrate_grid(times,a[[1]],a[[2]],origin,end)
  if(model=="A") {
    before<-integrate_grid(times,a[[1]],a[[2]],1,s)
    after<-integrate_grid(times,a[[1]],a[[2]],1,s+horizon)
    if(any(before[,"Survival"]<=1e-6))fit_failure("A conditioning denominator <= 1e-6")
    identity<-(after[,1:2,drop=FALSE]-before[,1:2,drop=FALSE])/before[,"Survival"]
    assert(max(abs(identity-ans[,1:2,drop=FALSE]))<1e-10,"A conditional CIF identity failed")
  }
  if(with_hazard) {
    last<-origin+pmin(d$time-s,horizon)
    interval<-times>origin & times<=end
    mask<-outer(last,times,">=") & rep(interval,each=nrow(d))
    attr(ans,"observed_hazard")<-cbind(rowSums(a[[1]]*mask),rowSums(a[[2]]*mask))
    attr(ans,"horizon_hazard")<-cbind(rowSums(a[[1]][,interval,drop=FALSE]),rowSums(a[[2]][,interval,drop=FALSE]))
  }
  ans
}

km_left <- function(time,event,at) {
  jumps<-sort(unique(time[event==1])); if(!length(jumps))return(rep(1,length(at)))
  risk<-vapply(jumps,function(t)sum(time>=t),numeric(1))
  deaths<-vapply(jumps,function(t)sum(time==t & event==1),numeric(1))
  g<-cumprod(1-deaths/risk)
  index<-findInterval(at,jumps); exact<-match(at,jumps,nomatch=0L); index[exact>0]<-exact[exact>0]-1L
  c(1,g)[index+1L]
}
ipcw <- function(d,s,method="marginal") {
  guard_development(d); t<-d$time-s; e<-d$status; n<-nrow(d)
  known<-(t<=3 & e>0) | t>=3; early<-e==0 & t<3; at<-pmin(t,3)
  g<-km_left(t,as.integer(e==0),at)
  note<-"Marginal reverse KM; strict left limits; no artificial 3y censor events"
  if(method=="covariate") {
    if(sum(early)>=30) {
      frame<-data.frame(t=t,censor=as.integer(e==0),age10=d$age_dx/10,
                        male=as.integer(d$sex=="Male"),year=d$year_dx)
      fit<-cox_checked(Surv(t,censor)~age10+male+year,frame)
      h<-basehaz(fit,centered=FALSE); idx<-findInterval(at,h$time)
      exact<-match(at,h$time,nomatch=0L);idx[exact>0]<-exact[exact>0]-1L
      g<-exp(-c(0,h$hazard)[idx+1L]*exp(drop(as.matrix(frame[,c("age10","male","year")])%*%coef(fit))))
      note<-"Prespecified 3df censor Cox (>=30 early censor events)"
    } else {
      groups<-cut(d$age_dx,c(-Inf,65,80,Inf),right=FALSE)
      for(a in levels(groups)) {
        ii<-which(groups==a)
        if(length(ii))g[ii]<-if(max(t[ii])<3)NA_real_ else km_left(t[ii],as.integer(e[ii]==0),at[ii])
      }
      note<-"Censor Cox insufficient support (<30); prespecified age-stratified KM"
    }
  }
  w<-numeric(n)
  if(any(!is.finite(g[known])) || any(g[known]<=0)) {
    w[known]<-NA_real_
  } else w[known]<-1/g[known]
  gp<-km_left(t,as.integer(e==0),3); wk<-w[known]
  stats<-c(G3_left=gp,early_censor=sum(early),known=sum(known),
    weight_p95=if(all(is.finite(wk)))unname(quantile(wk,.95)) else NA_real_,
    weight_p99=if(all(is.finite(wk)))unname(quantile(wk,.99)) else NA_real_,
    weight_max=if(all(is.finite(wk)))max(wk) else NA_real_,
    ESS=if(all(is.finite(wk)))sum(wk)^2/sum(wk^2) else NA_real_)
  reliable<-all(is.finite(wk)) && gp>=.1 && max(wk)<=20 && stats["ESS"]>=sum(known)*.5
  list(w=w,known=known,stats=stats,reliable=reliable,note=note,
       truncate=all(is.finite(wk)) && (quantile(wk,.99)>10 || max(wk)>20))
}
aj <- function(time,event,horizon=3) {
  S<-1; F<-c(0,0)
  for(t in sort(unique(time[event>0 & time<=horizon]))) {
    nr<-sum(time>=t); dd<-c(sum(time==t & event==1),sum(time==t & event==2))
    F<-F+S*dd/nr; S<-S*(1-sum(dd)/nr)
  }
  c(GBC=F[1],Other=F[2],Survival=S)
}
weighted_auc <- function(p,y,w) {
  if(any(!is.finite(w)))return(NA_real_)
  ord<-order(p); p<-p[ord]; w<-w[ord]; y<-y[ord]
  groups<-cumsum(c(TRUE,diff(p)!=0)); cw<-rowsum(w*(y==0),groups,reorder=FALSE)[,1]
  kw<-rowsum(w*(y==1),groups,reorder=FALSE)[,1]
  den<-sum(kw)*sum(cw); if(den<=0)return(NA_real_)
  sum(kw*(cumsum(cw)-cw+.5*cw))/den
}
glm_checked <- function(formula,frame,w) {
  if(any(!is.finite(w)))return(NULL)
  bad<-FALSE
  f<-withCallingHandlers(glm(formula,data=frame,weights=w,family=quasibinomial(),
    control=glm.control(maxit=100,epsilon=1e-9)),warning=function(e) {
      if(grepl("converg|0 or 1|separat",conditionMessage(e),ignore.case=TRUE))bad<<-TRUE
      else stop(e)
      invokeRestart("muffleWarning")
    })
  if(bad || !f$converged || any(!is.finite(coef(f))) || f$rank<length(coef(f)))return(NULL)
  f
}
calibration <- function(p,y,w) {
  z<-qlogis(pmin(pmax(p,1e-6),1-1e-6)); fr<-data.frame(y=y,z=z)
  empty<-list(values=c(slope=NA_real_,intercept=NA_real_,offset_intercept=NA_real_,ICI=NA_real_),
              smooth=rep(NA_real_,length(p)),knots=rep(NA_real_,3),method="UNESTIMABLE")
  if(any(!is.finite(w)) || sum(w*y)<=0 || sum(w*(1-y))<=0)return(empty)
  linear<-glm_checked(y~z,fr,w); if(is.null(linear))return(empty)
  off<-glm_checked(y~1+offset(z),fr,w)
  knots<-as.numeric(quantile(z,c(.1,.5,.9),type=7))
  spline_ok<-length(unique(knots))==3L && sum(y==1 & w>0)>=30 && sum(y==0 & w>0)>=30
  if(spline_ok) {
    fr$R<-I(Hmisc::rcspline.eval(z,knots=knots,inclx=TRUE,norm=2))
    smoothfit<-glm_checked(y~R,fr,w); method<-"IPCW quasi-binomial RCS (2 df + intercept)"
  } else {smoothfit<-linear;method<-"Low-support linear calibration"}
  sm<-if(is.null(smoothfit))rep(NA_real_,length(p)) else as.numeric(predict(smoothfit,fr,type="response"))
  list(values=c(slope=unname(coef(linear)[2]),intercept=unname(coef(linear)[1]),
    offset_intercept=if(is.null(off))NA_real_ else unname(coef(off)[1]),ICI=mean(abs(sm-p))),
    smooth=sm,knots=knots,method=method)
}
metric_vector <- function(d,s,p,k,weight=NULL,do_smooth=TRUE) {
  guard_development(d); t<-d$time-s; y<-as.integer(t<=3 & if(k==3L)d$status>0 else d$status==k)
  iw<-if(is.null(weight))ipcw(d,s) else weight; w<-iw$w
  observed<-aj(t,d$status); O<-if(k==3L)sum(observed[1:2]) else observed[k]
  cal<-calibration(p,y,w)
  v<-c(AUC2=weighted_auc(p,y,w),Brier=sum(w*(y-p)^2)/length(p),cal$values,
       AJ_observed=unname(O),mean_predicted=mean(p),O_over_E=if(mean(p)>0)unname(O)/mean(p) else NA_real_,
       absolute_CITL_pp=100*(unname(O)-mean(p)),risk_min=min(p),risk_p01=unname(quantile(p,.01)),
       risk_median=median(p),risk_p99=unname(quantile(p,.99)),risk_max=max(p),
       boundary_fraction=mean(p<=1e-6 | p>=1-1e-6),iw$stats,weight_reliable=as.numeric(iw$reliable))
  list(values=v,calibration=cal,weight=iw)
}
evaluate_model <- function(pair,d,detailed=FALSE) {
  guard_development(d); vals<-numeric(); curves<-groups<-joint<-hazards<-list()
  add<-function(s,cause,metric,v) {vals[paste(s,cause,metric,sep="|")]<<-as.numeric(v)}
  for(s in 1:3) {
    nd<-d[d$time>s,,drop=FALSE]; pr<-predict_competing_risk(pair,nd,s,with_hazard=TRUE)
    iw<-ipcw(nd,s); observed<-aj(nd$time-s,nd$status)
    for(k in 1:3) {
      p<-if(k==3L)rowSums(pr[,1:2,drop=FALSE]) else pr[,k]
      ev<-metric_vector(nd,s,p,k,iw)
      for(n in names(ev$values))add(s,k,n,ev$values[n])
      if(k<=2) {
        E<-attr(pr,"observed_hazard")[,k]; O<-as.integer(nd$time-s<=3 & nd$status==k)
        unsupported<-any(E==0 & O>0)
        add(s,k,"hazard_process_O_over_E",if(unsupported || sum(E)==0)NA_real_ else sum(O)/sum(E))
        add(s,k,"hazard_zero_E_zero_O",sum(E==0 & O==0))
      }
      if(detailed) {
        ord<-order(p); take<-unique(round(seq(1,length(p),length.out=min(101,length(p)))))
        curves[[length(curves)+1L]]<-data.frame(lm=s,cause=k,predicted=p[ord][take],
          observed_smooth=ev$calibration$smooth[ord][take],method=ev$calibration$method,
          knots=paste(signif(ev$calibration$knots,7),collapse=" / "),
          interpretation=ifelse(p[ord][take]<quantile(p,.01) | p[ord][take]>quantile(p,.99),"Sparse tail","Central 1-99%"))
        cuts<-unique(as.numeric(quantile(p,seq(0,1,.2)))); bin<-if(length(cuts)>1)cut(p,unique(c(-Inf,cuts[-c(1,length(cuts))],Inf)),include.lowest=TRUE) else factor(rep("Tied",length(p)))
        for(g in levels(bin)) {
          z<-which(bin==g); oe<-aj(nd$time[z]-s,nd$status[z]); ne<-sum(nd$time[z]-s<=3 & nd$status[z]>0)
          groups[[length(groups)+1L]]<-data.frame(lm=s,cause=k,group=g,n=length(z),deaths=ne,
            predicted=mean(p[z]),observed=if(ne<10)NA_real_ else if(k==3)sum(oe[1:2]) else oe[k],
            status=if(ne<10)"SUPPORT INSUFFICIENT" else "Descriptive AJ")
        }
        for(method in c("covariate",if(iw$truncate)"cap10")) {
          weight<-if(method=="cap10") {w<-iw;w$w<-pmin(w$w,10);w} else ipcw(nd,s,method)
          alt<-metric_vector(nd,s,p,k,weight)$values
          for(n in names(alt))add(s,k,paste0(method,"_",n),alt[n])
        }
      }
    }
    bins<-lapply(1:2,function(k) {
      q<-unique(as.numeric(quantile(pr[,k],c(1/3,2/3))))
      cut(pr[,k],c(-Inf,q,Inf),include.lowest=TRUE,labels=FALSE)
    })
    for(a in 1:3)for(b in 1:3) {
      z<-which(bins[[1]]==a & bins[[2]]==b); n<-length(z)
      supported<-n>=50 && all(vapply(1:2,function(k)sum(nd$time[z]-s<=3 & nd$status[z]==k)>=10,logical(1)))
      oe<-if(n)aj(nd$time[z]-s,nd$status[z]) else rep(NA_real_,3)
      for(k in 1:3) {
        mn<-if(n)mean(pr[z,k]) else NA_real_
        add(s,k,paste0("joint_",a,b,"_difference"),if(supported)oe[k]-mn else NA_real_)
        if(detailed)joint[[length(joint)+1L]]<-data.frame(lm=s,state=c("GBC","Other","Survival")[k],
          cell=paste(a,b,sep="x"),n=n,predicted=mn,observed=if(supported)oe[k] else NA_real_,
          status=if(supported)"Limited grouped diagnostic" else "SUPPORT INSUFFICIENT")
      }
    }
    if(detailed) for(k in 1:2) {
      h<-attr(pr,"horizon_hazard")[,k]; E<-attr(pr,"observed_hazard")[,k]
      O<-as.integer(nd$time-s<=3 & nd$status==k)
      q<-unique(as.numeric(quantile(h,seq(.2,.8,.2)))); bin<-cut(h,c(-Inf,q,Inf),include.lowest=TRUE)
      for(g in levels(bin)) {
        z<-which(bin==g)
        hazards[[length(hazards)+1L]]<-data.frame(lm=s,cause=k,group=g,n=length(z),O=sum(O[z]),E=sum(E[z]),
          O_over_E=if(sum(E[z])>0 && !any(E[z]==0 & O[z]>0))sum(O[z])/sum(E[z]) else NA_real_)
      }
    }
  }
  list(values=vals,curves=bind_rows(curves),groups=bind_rows(groups),joint=bind_rows(joint),hazards=bind_rows(hazards))
}
bind_rows <- function(x) {
  x<-Filter(function(d)!is.null(d) && NROW(d)>0,x)
  if(!length(x))return(data.frame())
  fields<-unique(unlist(lapply(x,names)))
  do.call(rbind,lapply(x,function(d) {for(n in setdiff(fields,names(d)))d[[n]]<-NA;d[,fields,drop=FALSE]}))
}
patient_draws <- function(n,B,substream=0L) {
  RNGkind("L'Ecuyer-CMRG"); set.seed(CFG$seed)
  state<-get(".Random.seed",envir=.GlobalEnv)
  if(substream>0) for(i in seq_len(substream))state<-parallel::nextRNGStream(state)
  assign(".Random.seed",state,envir=.GlobalEnv)
  draws<-lapply(seq_len(B),function(b)sample.int(n,n,replace=TRUE))
  list(draws=draws,initial_state=state,final_state=get(".Random.seed",envir=.GlobalEnv),substream=substream)
}
resample_patients <- function(d,index) {
  guard_development(d); out<-d[index,,drop=FALSE]
  out$cluster<-seq_len(nrow(out)); rownames(out)<-NULL; out
}
run_bootstrap <- function(d,model,original,draws,tv=c(NA_character_,NA_character_),key=model) {
  guard_development(d); B<-length(draws); name<-paste0("bootstrap_",key)
  rows<-STATE$cache[[name]]; if(is.null(rows))rows<-vector("list",B)
  for(b in seq_len(B)) {
    if(!is.null(rows[[b]]))next
    db<-resample_patients(d,draws[[b]])
    result<-numerical_try({
      pair<-fit_pair(db,model,tv=tv)
      bb<-evaluate_model(pair,db)$values; bo<-evaluate_model(pair,d)$values
      list(apparent=bb,on_original=bo,
        coefficients=unlist(lapply(pair,function(f)c(f$beta,if(!is.null(f$tv))PH_delta=f$delta))),
        fixed_zero=paste(unlist(lapply(pair,function(f)f$fixed_zero)),collapse=";"))
    })
    rows[[b]]<-result; STATE$counts[[key]]<-b
    if(b%%25L==0L || b==B) {
      log_line(sprintf("BOOTSTRAP %s %d / %d; valid=%d",key,b,B,sum(vapply(rows[seq_len(b)],function(z)z$ok,logical(1)))))
      checkpoint_save(name,rows)
    }
  }
  rows
}
bootstrap_summary <- function(original,rows,model) {
  ok<-vapply(rows,function(r)r$ok,logical(1)); B<-length(rows)
  keys<-names(original$values); output<-lapply(keys,function(key) {
    valid<-which(ok)
    a<-vapply(rows[valid],function(r) {v<-r$value$apparent[key];if(length(v))v else NA_real_},numeric(1))
    o<-vapply(rows[valid],function(r) {v<-r$value$on_original[key];if(length(v))v else NA_real_},numeric(1))
    usable<-is.finite(a) & is.finite(o); success<-sum(usable)/B
    optimism<-if(any(usable))mean(a[usable]-o[usable]) else NA_real_
    parts<-strsplit(key,"|",fixed=TRUE)[[1]]
    corrected<-if(success>=.95)original$values[key]-optimism else NA_real_
    ci<-if(success>=.95)as.numeric(quantile(a[usable],c(.025,.975))) else c(NA_real_,NA_real_)
    data.frame(model=model,landmark=as.integer(parts[1]),cause=as.integer(parts[2]),metric=parts[3],
      apparent=unname(original$values[key]),mean_optimism=optimism,corrected=unname(corrected),
      bootstrap_apparent_low=ci[1],bootstrap_apparent_high=ci[2],valid_fraction=success,
      uncertainty="Patient refit bootstrap percentile; corrected estimate has no claimed CI")
  })
  bind_rows(output)
}
decide_c <- function(summary,rows,label) {
  numerical<-mean(vapply(rows,function(r)r$ok,logical(1)))
  sl<-vapply(1:2,function(k) {
    x<-summary$corrected[summary$cause==k & summary$metric=="slope"]
    if(length(x)!=3 || anyNA(x))NA_real_ else median(x)
  },numeric(1))
  pass<-numerical>=.95 && all(is.finite(sl)) && all(sl>=.90)
  data.frame(candidate=label,valid_fraction=numerical,median_GBC_slope=sl[1],median_Other_slope=sl[2],
    criterion_pass=pass,decision=if(pass)"RETAIN" else if(label=="C_FULL")"TRY C_REDUCED" else "UNSTABLE C",
    scope=if(STATE$mode=="smoke")"SMOKE ONLY: NOT A FORMAL QUALIFICATION" else "Development only; locked thresholds")
}
paired_differences <- function(results,boots,selected_c) {
  candidates<-c(A="A",B="B",C=selected_c); pairs<-list(c("B","A"),c("C","A"),c("C","B"))
  rows<-list()
  for(pair in pairs) {
    hi<-candidates[[pair[1]]]; lo<-candidates[[pair[2]]]
    if(is.null(hi) || is.na(hi))next
    keys<-intersect(names(results[[hi]]$values),names(results[[lo]]$values))
    keys<-keys[grepl("[|](AUC2|Brier)$",keys)]
    for(key in keys) {
      a<-boots[[hi]];b<-boots[[lo]]
      delta<-vapply(seq_along(a),function(i)if(a[[i]]$ok && b[[i]]$ok)
        a[[i]]$value$apparent[key]-b[[i]]$value$apparent[key] else NA_real_,numeric(1))
      valid<-is.finite(delta);ci<-if(mean(valid)>=.95)quantile(delta[valid],c(.025,.975)) else c(NA,NA)
      parts<-strsplit(key,"|",fixed=TRUE)[[1]]
      rows[[length(rows)+1L]]<-data.frame(model=paste(pair,collapse="-"),landmark=as.integer(parts[1]),
        cause=as.integer(parts[2]),metric=paste0("paired_delta_",parts[3]),
        apparent=unname(results[[hi]]$values[key]-results[[lo]]$values[key]),
        bootstrap_apparent_low=unname(ci[1]),bootstrap_apparent_high=unname(ci[2]),valid_fraction=mean(valid),
        uncertainty="Same patient draws/G; refit-bootstrap difference; NOT temporal validation")
    }
  }
  bind_rows(rows)
}

synthetic_tests <- function() {
  tests<-list(); record<-function(name,error,tolerance=1e-10,note="Synthetic only") {
    assert(is.finite(error) && error<=tolerance,paste("SOFTWARE TEST failed:",name,"error",error))
    tests[[length(tests)+1L]]<<-data.frame(test=name,error=error,tolerance=tolerance,status="PASS",note=note)
  }
  age<-c(30,48,60,65,70,76,87,90,95); knots<-CFG$knots
  explicit<-function(v) {
    a<-knots[3];b<-knots[4]
    basis<-cbind(v,do.call(cbind,lapply(knots[1:2],function(k)(pmax(v-k,0)^3-
      pmax(v-a,0)^3*(b-k)/(b-a)+pmax(v-b,0)^3*(a-k)/(b-a))/(b-knots[1])^2)))
    basis
  }
  record("Fixed RCS vs explicit basis",max(abs(make_rcs(age)-sweep(explicit(age),2,as.numeric(explicit(70)),"-")/10)))
  t<-c(.5,1,1,2,3,3);e<-c(1,1,0,2,1,0)
  g<-km_left(t,as.integer(e==0),pmin(t,3)); expected<-c(1,1,1,.8,.8,.8)
  record("Same-time deaths/censoring and tau left limits",max(abs(g-expected)))
  d<-data.frame(year_dx=rep(2004L,6),time=t+1,status=e)
  w<-ipcw(d,1)$w;record("Early censor zero; tau censor known",max(abs(w-c(1,1,0,1.25,1.25,1.25))))
  sf<-survfit(Surv(t,e==0)~1)
  package_g<-vapply(pmin(t,3),function(a) {i<-which(sf$time<a);if(length(i))tail(sf$surv[i],1) else 1},numeric(1))
  record("Reverse KM vs survival",max(abs(g-package_g)))
  p<-c(.8,.6,.4,.3,.2,.1);y<-as.integer(e==1 & t<=3)
  manual<-sum(outer(w*y,w*(1-y))*((outer(p,p,">")+0.5*outer(p,p,"=="))))/(sum(w*y)*sum(w*(1-y)))
  record("AUC2 weighted pairs incl competing controls",abs(weighted_auc(p,y,w)-manual))
  record("Brier uses all n not sum weights",abs(metric_vector(d,1,p,1)$values["Brier"]-sum(w*(y-p)^2)/6))
  grid<-c(.5,1,2,3);a1<-matrix(c(.2,.1,.3,.1),nrow=1);a2<-matrix(c(.1,.2,.2,.1),nrow=1)
  z<-integrate_grid(grid,a1,a2,0,3);record("Simultaneous-cause closure",abs(sum(z[1,1:3])-1))
  one<-integrate_grid(grid,a1,a2*0,0,3)
  record("Single-cause exponential survival limit",abs(one[1,"GBC"]-(1-exp(-sum(a1)))))
  before<-integrate_grid(grid,a1,a2,0,1);after<-integrate_grid(grid,a1,a2,0,3)
  conditional<-integrate_grid(grid,a1,a2,1,3)
  record("Conditional CIF identity",max(abs((after[,1:2]-before[,1:2])/before[,"Survival"]-conditional[,1:2])))
  step1<-integrate_grid(grid,a1,a2,0,.5)[1,"GBC"];step2<-integrate_grid(grid,a1,a2,0,1)[1,"GBC"]
  step3<-integrate_grid(grid,a1,a2,0,2)[1,"GBC"]
  record("Exact right-continuous RMTL",abs(z[1,"RMTL_GBC"]-(step1*.5+step2+step3)))
  RNGkind("L'Ecuyer-CMRG");set.seed(CFG$seed)
  n<-240L
  synthetic<-data.frame(year_dx=rep(2006L,n),age_dx=sample(40:90,n,TRUE),
    sex=sample(c("Female","Male"),n,TRUE),T_core=sample(c("T1","T2","T3/4","Unknown"),n,TRUE),
    N_model=sample(c("N0","N+","Unknown"),n,TRUE),grade_model=sample(c("G1","G2","G3/4","Unknown"),n,TRUE),
    time=1+rexp(n,.15),status=sample(0:2,n,TRUE,prob=c(.2,.5,.3)),cluster=seq_len(n),age_90plus_flag=FALSE)
  for(model in c("A","B","C_FULL","C_REDUCED")) {
    fit<-fit_pair(synthetic,model,full=TRUE)
    for(s in 1:3) {
      nd<-synthetic[synthetic$time>s,];pr<-predict_competing_risk(fit,nd,s)
      record(paste(model,"L",s,"closure"),max(abs(rowSums(pr[,1:3])-1)))
    }
    record(paste(model,"actual df trace bound"),as.numeric(any(vapply(fit,function(f)f$effective_df>length(f$beta)+1e-8,logical(1)))))
    ph<-ph_descriptive(fit,model)
    record(paste(model,"grouped PH diagnostic"),as.numeric(!all(c("Age","Sex","T","N","Grade","GLOBAL")%in%ph$table$term)))
  }
  known<-synthetic;known$T_core[known$T_core=="Unknown"]<-"T1"
  known$N_model[known$N_model=="Unknown"]<-"N0";known$grade_model[known$grade_model=="Unknown"]<-"G1"
  zero<-fit_pair(known,"C_FULL",full=TRUE)
  record("All-zero penalized states fixed0, not main-effect deletion",as.numeric(any(vapply(zero,function(f)
    length(f$fixed_zero)!=3L || any(f$beta[f$fixed_zero]!=0),logical(1)))))
  toy<-data.frame(t=c(1,2,2,3,4,5),e=c(1,1,1,0,1,0),x=c(0,1,0,1,0,1))
  cf<-coxph(Surv(t,e)~x,data=toy,ties="breslow",x=TRUE,y=TRUE,model=TRUE)
  md<-data.frame(start=0,stop=toy$t,event=toy$e,lm=1,age_dx=70,T_core="T1")
  bi<-baseline_information(md,matrix(toy$x,ncol=1),coef(cf),1)
  bh<-basehaz(cf,centered=FALSE); bb<-bi$baseline[[1]]
  record("Explicit Breslow vs survival basehaz",max(abs(cumsum(bb$hazard)-bh$hazard[match(bb$time,bh$time)])))
  surv<-survfit(cf,newdata=data.frame(x=0),stype=2,ctype=1)
  record("Unpenalized survival package cross-check",abs(exp(-sum(bb$hazard))-tail(surv$surv,1)))
  tvfit<-fit_cause(synthetic,"B",1,tv="age",full=TRUE)
  record("tt PH probe fit and +1 df",as.numeric(!is.finite(tvfit$delta) || tvfit$effective_df>13+1e-8),
         note="tt requires model=FALSE in survival; x/y retained, explicit event-grid baseline")
  score_data<-data.frame(u=seq(.1,6,length.out=60),status=rep(c(1L,2L,0L),20))
  risk<-seq(.8,.1,length.out=60)
  checkd<-data.frame(year_dx=2005L,time=score_data$u+1,status=score_data$status)
  Hist<-prodlim::Hist # Score 2023 response parser requires the unqualified Hist symbol.
  for(k in 1:2) {
    score<-riskRegression::Score(list(locked=risk),Hist(u,status)~1,data=score_data,
      times=3,cause=k,metrics=c("AUC","Brier"),null.model=FALSE,split.method="none",conf.int=FALSE,
      cens.model="km",se.fit=FALSE)
    ev<-metric_vector(checkd,1,risk,k)$values
    record(paste("riskRegression Score AUC2 cause",k),abs(score$AUC$score$AUC[1]-ev["AUC2"]),1e-8)
    record(paste("riskRegression Score Brier cause",k),abs(score$Brier$score$Brier[1]-ev["Brier"]),1e-8)
  }
  copied<-resample_patients(synthetic,c(1,1,3,4)); lm<-make_landmarks(copied)
  record("Repeated patient copies retain distinct clusters",abs(length(unique(lm$cluster))-4))
  future<-synthetic;future$year_dx[1]<-2012L
  denied<-tryCatch({guard_development(future);FALSE},error=function(e)grepl("FIREWALL",conditionMessage(e)))
  record("Validation firewall rejection",as.numeric(!denied))
  sumfixture<-expand.grid(cause=1:2,landmark=1:3);sumfixture$metric<-"slope";sumfixture$corrected<-1
  okfixture<-rep(list(list(ok=TRUE)),10)
  record("C gate retains only qualifying FULL",as.numeric(!decide_c(sumfixture,okfixture,"C_FULL")$criterion_pass))
  sumfixture$corrected[sumfixture$cause==1]<-.89
  record("C gate low slope forces REDUCED",as.numeric(decide_c(sumfixture,okfixture,"C_FULL")$criterion_pass))
  sumfixture$corrected<-1;okfixture[[1]]$ok<-FALSE
  record("C gate numerical failure forces fallback",as.numeric(decide_c(sumfixture,okfixture,"C_REDUCED")$criterion_pass))
  saved<-as.list(STATE);testdir<-tempfile("gbc_checkpoint_unit_");dir.create(testdir)
  tryCatch({
    STATE$temp<-testdir;STATE$fingerprint<-"SYNTHETIC";STATE$cache<-list();STATE$counts<-list()
    checkpoint_save("first",1L);checkpoint_save("second",2L)
    restored<-checkpoint_load(testdir,"SYNTHETIC")
    record("Checkpoint exact-match restoration",as.numeric(restored$state$cache$second!=2L))
    record("Checkpoint wrong fingerprint rejected",as.numeric(!is.null(checkpoint_load(testdir,"DIFFERENT"))))
    writeLines("deliberately interrupted checkpoint",file.path(testdir,"checkpoint.rds"))
    restored<-checkpoint_load(testdir,"SYNTHETIC")
    record("Checkpoint previous-generation recovery",as.numeric(restored$state$cache$first!=1L))
  },finally={
    for(n in setdiff(ls(STATE),names(saved)))rm(list=n,envir=STATE)
    for(n in names(saved))assign(n,saved[[n]],envir=STATE)
    unlink(testdir,recursive=TRUE)
  })
  out<-bind_rows(tests); log_line(paste("SYNTHETIC TEST PASS",nrow(out),"checks"));out
}

ph_descriptive <- function(pair,model) {
  tab<-list();plots<-list()
  for(k in 1:2) {
    f<-pair[[k]];diagnostic<-f$fit
    active<-names(f$beta)[!names(f$beta)%in%f$fixed_zero]
    group<-ifelse(grepl("^Age_",active) & !grepl("_by_s$",active),"Age",ifelse(active=="Male","Sex",
      ifelse(grepl("unknown",active),paste0("Sparse_",active),
      ifelse(grepl("_by_s$",active),paste0("Dynamic_",active),
      ifelse(active%in%c("T2","T34"),"T",ifelse(active=="Nplus","N","Grade"))))))
    diagnostic$assign<-split(seq_along(active),factor(group,levels=unique(group)))
    penalty<-diag(as.numeric(f$penalized[match(active,names(f$beta))])*f$theta,length(active))
    percoef<-diag(solve(f$information+penalty,f$information))
    diagnostic$df<-vapply(diagnostic$assign,function(i)sum(percoef[i]),numeric(1))
    z<-cox.zph(diagnostic,transform="km",terms=TRUE,global=TRUE)
    table<-as.data.frame(z$table);table$term<-rownames(table);rownames(table)<-NULL
    table$model<-model;table$cause<-k;table$type<-"Scaled Schoenfeld; descriptive score P only"
    table$interpretation<-"Repeated landmark rows are not independent; bootstrap probe governs materiality"
    tab[[length(tab)+1L]]<-table
    bycoef<-cox.zph(f$fit,transform="km",terms=FALSE,global=FALSE)
    names<-c(names(f$beta)[!names(f$beta)%in%f$fixed_zero])
    assert(ncol(bycoef$y)==length(names),"PH residual coefficient mapping mismatch")
    for(j in seq_along(names)) {
      plots[[length(plots)+1L]]<-list(model=model,cause=k,term=names[j],x=bycoef$x,
        time=bycoef$time,y=bycoef$y[,j],strata=if(is.null(bycoef$strata))rep("A",length(bycoef$x)) else as.character(bycoef$strata))
    }
  }
  list(table=bind_rows(tab),plots=plots)
}
run_ph <- function(d,models) {
  guard_development(d)
  desc<-lapply(names(models),function(m)ph_descriptive(models[[m]],m))
  rows<-lapply(desc,function(x)x$table); plots<-unlist(lapply(desc,function(x)x$plots),recursive=FALSE)
  if(STATE$mode=="smoke") {
    rows[[length(rows)+1L]]<-data.frame(type="PH probe bootstrap",interpretation=
      "SMOKE: tt probe qualified on synthetic data; development 500-probe bootstrap and sensitivities deferred to LOCAL FINAL; no PH materiality decision")
    return(list(table=bind_rows(rows),plots=plots,sensitivity=list(),selection=c(NA_character_,NA_character_)))
  }
  draws<-patient_draws(nrow(d),STATE$B,substream=1L)
  probes<-list()
  for(m in names(models))for(k in 1:2)for(term in c("age","T34")) {
    key<-paste("PH",m,k,term,sep="_");log_line(paste("BEGIN",key))
    original<-checkpoint_get(paste0(key,"_original"),numerical_try(fit_cause(d,m,k,tv=term,full=TRUE)))
    reps<-STATE$cache[[key]];if(is.null(reps))reps<-vector("list",STATE$B)
    for(b in seq_len(STATE$B)) {
      if(!is.null(reps[[b]]))next
      db<-resample_patients(d,draws$draws[[b]])
      reps[[b]]<-numerical_try({f<-fit_cause(db,m,k,tv=term);f$delta*log(6)})
      STATE$counts[[key]]<-b
      if(b%%25==0 || b==STATE$B) {log_line(sprintf("%s %d / %d",key,b,STATE$B));checkpoint_save(key,reps)}
    }
    valid<-vapply(reps,function(z)z$ok,logical(1))
    values<-vapply(reps[valid],function(z)z$value,numeric(1))
    ci<-if(mean(valid)>=.95 && original$ok)quantile(values,c(.025,.975)) else c(NA_real_,NA_real_)
    material<-all(is.finite(ci)) && (ci[1]>log(1.5) || ci[2]< -log(1.5))
    row<-data.frame(model=m,cause=k,term=term,type="PH diagnostic probe; not a main candidate",
      D=if(original$ok)original$value$delta*log(6) else NA_real_,CI_low=unname(ci[1]),CI_high=unname(ci[2]),
      valid_fraction=mean(valid),material=material,
      interpretation=if(material)"MATERIAL" else "MINOR / INCONCLUSIVE; not proof of PH")
    probes[[length(probes)+1L]]<-row;rows[[length(rows)+1L]]<-row
    log_line(paste("END PASS",key,row$interpretation))
  }
  pt<-bind_rows(probes);chosen<-rep(NA_character_,2)
  for(k in 1:2) {
    material<-unique(pt$term[pt$cause==k & pt$material]);priority<-if(k==1)c("T34","age") else c("age","T34")
    eligible<-priority[priority%in%material];if(length(eligible))chosen[k]<-eligible[1]
  }
  sensitivity<-list()
  if(any(!is.na(chosen)))for(m in names(models)) {
    key<-paste0("PH_ADJUSTED_",m);log_line(paste("BEGIN",key,"unified terms",paste(chosen,collapse=" / ")))
    orig<-checkpoint_get(key,numerical_try(fit_pair(d,m,tv=chosen,full=TRUE)))
    if(orig$ok) {
      point<-evaluate_model(orig$value,d)
      boot<-run_bootstrap(d,m,orig$value,draws$draws,tv=chosen,key=key)
      valid<-mean(vapply(boot,function(b)b$ok,logical(1)))
      sensitivity[[m]]<-list(models=orig$value,summary=bootstrap_summary(point,boot,key),valid_fraction=valid)
      rows[[length(rows)+1L]]<-data.frame(model=m,type="PH-adjusted sensitivity (main models unchanged)",
        term=paste(chosen,collapse=" / "),valid_fraction=valid,
        interpretation=if(valid>=.95)"Numerically eligible sensitivity; <=1 additional df per cause" else "UNSTABLE sensitivity; structural limitation")
    } else rows[[length(rows)+1L]]<-data.frame(model=m,type="PH-adjusted sensitivity",interpretation=paste("FAILED",orig$message))
  }
  list(table=bind_rows(rows),plots=plots,sensitivity=sensitivity,selection=chosen,
    rng=list(substream=draws$substream,initial_state=draws$initial_state))
}

development_sensitivities <- function(d,models) {
  rows<-list()
  for(m in names(models))for(setting in c("theta_0.5","theta_2","exclude_90plus","known_only")) {
    subset<-d
    if(setting=="exclude_90plus")subset<-d[!d$age_90plus_flag,,drop=FALSE]
    if(setting=="known_only")subset<-d[d$T_core%in%c("T1","T2","T3/4") & d$N_model%in%c("N0","N+") & d$grade_model%in%c("G1","G2","G3/4"),,drop=FALSE]
    theta<-if(setting=="theta_0.5").5 else if(setting=="theta_2")2 else 1
    f<-numerical_try(fit_pair(subset,m,theta=theta,full=TRUE))
    if(!f$ok) {
      rows[[length(rows)+1L]]<-data.frame(model=m,setting=setting,status="UNESTIMABLE",note=f$message);next
    }
    for(s in 1:3) {
      nd<-subset[subset$time>s,,drop=FALSE]
      old<-predict_competing_risk(models[[m]],nd,s);new<-predict_competing_risk(f$value,nd,s)
      for(k in 1:2)rows[[length(rows)+1L]]<-data.frame(model=m,setting=setting,landmark=s,cause=k,n=nrow(nd),
        mean_absolute_risk_change=mean(abs(old[,k]-new[,k])),max_absolute_risk_change=max(abs(old[,k]-new[,k])),
        effective_df=f$value[[k]]$effective_df,status="POINT-FIT STABILITY ONLY",note="No selection or performance qualification; subgroups change target population")
    }
  }
  bind_rows(rows)
}

coefficient_table <- function(models,boots) {
  rows<-list()
  for(m in names(models))for(k in 1:2) {
    f<-models[[m]][[k]];reps<-boots[[m]];valid<-vapply(reps,function(r)r$ok,logical(1))
    for(n in names(f$beta)) {
      key<-paste(c("GBC","Other")[k],n,sep=".")
      values<-vapply(reps[valid],function(r)unname(r$value$coefficients[key]),numeric(1))
      ci<-if(mean(valid)>=.95 && all(is.finite(values)))quantile(values,c(.025,.975)) else c(NA,NA)
      rows[[length(rows)+1L]]<-data.frame(model=m,cause=k,term=n,beta=unname(f$beta[n]),
        bootstrap_low=unname(ci[1]),bootstrap_high=unname(ci[2]),penalized=f$penalized[match(n,names(f$beta))],
        theta=if(f$penalized[match(n,names(f$beta))])f$theta else 0,
        interpretation=if(grepl("unknown",n))"Sparse registry state; penalty-dependent, not clinical effect" else
          if(grepl("Age_rcs",n))"Spline basis coefficient; not a standalone age hazard ratio" else "Log hazard coefficient on frozen scale")
    }
  }
  bind_rows(rows)
}
effective_df_table <- function(models,series="Primary") {
  bind_rows(lapply(names(models),function(m)bind_rows(lapply(1:2,function(k) {
    f<-models[[m]][[k]]
    data.frame(series=series,model=m,cause=k,nominal_coefficients=length(f$beta)+as.integer(!is.null(f$tv)),
      effective_df=f$effective_df,survival_df_crosscheck=f$package_df,baseline_jumps=f$baseline_jumps,
      stacked_rows=f$n,unique_patients=f$unique_patients,stacked_events=f$events,
      information_condition=f$information_condition,fixed_zero=paste(f$fixed_zero,collapse=";"),
      score_equation_max_abs_error=f$score_error,
      definition="trace(solve(I + P, I)); baseline nuisance jumps are separate")
  }))))
}
make_ph_images <- function(plots) {
  images<-list();if(!length(plots))return(images)
  pages<-split(seq_along(plots),ceiling(seq_along(plots)/6))
  for(i in seq_along(pages)) {
    file<-file.path(STATE$temp,sprintf("ph_diagnostics_%02d.png",i))
    png(file,width=1440,height=1000,res=120)
    tryCatch({
      par(mfrow=c(2,3),mar=c(4,4,4,1),oma=c(0,0,2,0),cex=.8)
      for(j in pages[[i]]) {
        p<-plots[[j]];ok<-is.finite(p$x)&is.finite(p$y)
        plot(p$x[ok],p$y[ok],pch=16,col=adjustcolor("#526377",alpha.f=.18),
          xlab="KM-transformed follow-up time",ylab="Scaled Schoenfeld residual",
          main=paste(p$model,c("GBC","Other")[p$cause],p$term,sep=" / "))
        levels<-unique(p$strata);cols<-c("#245682","#BA5C27","#618443")
        for(a in seq_along(levels)) {
          z<-which(ok & p$strata==levels[a]);if(length(z)>=5 && length(unique(p$x[z]))>=3)
            lines(lowess(p$x[z],p$y[z]),col=cols[(a-1)%%3+1],lwd=2)
        }
        legend("topright",legend=levels,col=rep(cols,length.out=length(levels)),lty=1,bty="n",cex=.7)
      }
      mtext(paste(STATE$banner,"| Descriptive plots by landmark; no independent-row inference"),outer=TRUE,cex=.85)
    },finally=dev.off())
    images[[length(images)+1L]]<-list(path=file,width=1080,height=750)
  }
  images
}
make_workbook <- function(sheets,path,images) {
  payload<-list(banner=STATE$banner,sheets=sheets,images=images)
  json<-file.path(STATE$temp,"workbook_payload.json")
  jsonlite::write_json(payload,json,auto_unbox=TRUE,na="null",dataframe="rows",digits=16)
  builder<-file.path(STATE$temp,"export_workbook.mjs")
  js<-r"---(import fs from 'node:fs/promises';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';
const p=JSON.parse(await fs.readFile(process.argv[2],'utf8'));
const wb=Workbook.create();
for(const [name,records] of Object.entries(p.sheets)) {
  const sheet=wb.worksheets.add(name); sheet.showGridLines=false;
  const rows=Array.isArray(records)?records:[records];
  const fields=[...new Set(rows.flatMap(r=>Object.keys(r)))];
  sheet.getRange('A2').values=[[name.replaceAll('_',' ')]];
  sheet.getRange('A2').format.font={name:'Arial',size:14,bold:true,color:'#253C56'};
  sheet.getRange('A3').values=[[p.banner]];
  sheet.getRange('A3').format.font={name:'Arial',size:10,bold:true,color:p.banner.startsWith('SMOKE')?'#A83A24':'#253C56'};
  sheet.getRangeByIndexes(4,0,1,Math.max(1,fields.length)).values=[fields.length?fields:['status']];
  if(rows.length && fields.length) {
    const values=rows.map(r=>fields.map(k=>r[k]===undefined?null:(typeof r[k]==='object' && r[k]!==null?JSON.stringify(r[k]):r[k])));
    sheet.getRangeByIndexes(5,0,rows.length,fields.length).values=values;
  }
  const all=sheet.getRangeByIndexes(4,0,Math.max(1,rows.length+1),Math.max(1,fields.length));
  all.format.font={name:'Arial',size:10,color:'#243347'};all.format.rowHeight=19;
  all.format.verticalAlignment='center';all.format.columnWidth=20;
  const header=sheet.getRangeByIndexes(4,0,1,Math.max(1,fields.length));
  header.format.fill='#304F70';header.format.font={name:'Arial',size:10,bold:true,color:'#FFFFFF'};
  header.format.rowHeight=32;header.format.wrapText=true;header.format.horizontalAlignment='center';
  for(let j=0;j<fields.length;j++) {
    const col=sheet.getRangeByIndexes(5,j,Math.max(1,rows.length),1);
    const nums=rows.map(r=>r[fields[j]]).filter(v=>v!==null && v!==undefined);
    if(nums.length && nums.every(v=>typeof v==='number')) {
      col.setNumberFormat(nums.every(Number.isInteger)?'0':'0.0000');col.format.horizontalAlignment='right';
    } else {
      col.format.horizontalAlignment='left';
      const len=Math.max(fields[j].length,...nums.map(v=>String(v).length));
      col.format.columnWidth=Math.min(85,Math.max(16,Math.ceil(len*.9)));
    }
    if(/status|decision|interpretation/.test(fields[j]))col.conditionalFormats.add('containsText',
      {text:'FAIL',format:{fill:'#FCE4DF',font:{color:'#9C2F22',bold:true}}});
  }
  if(rows.length>25)sheet.freezePanes.freezeRows(5);
  if(name==='PH')for(let i=0;i<p.images.length;i++) {
    const im=p.images[i];const data=await fs.readFile(im.path);
    sheet.images.add({dataUrl:'data:image/png;base64,'+data.toString('base64'),
      anchor:{from:{row:5+i*40,col:Math.max(fields.length+1,18)},extent:{widthPx:im.width,heightPx:im.height}}});
  }
}
wb.recalculate();
const check=await wb.inspect({kind:'region',sheetId:'counts',range:'A1:E10',maxChars:2500});
await fs.writeFile(process.argv[3]+'.audit.txt',check.ndjson??JSON.stringify(check));
const preview=await wb.render({sheetName:'counts',range:'A1:E10',scale:1.5,format:'png'});
await fs.writeFile(process.argv[3]+'.preview.png',new Uint8Array(await preview.arrayBuffer()));
const out=await SpreadsheetFile.exportXlsx(wb);await out.save(process.argv[3]);
console.log('WORKBOOK EXPORT PASS: '+Object.keys(p.sheets).join(', '));
)---"
  writeLines(js,builder,useBytes=TRUE)
  junction<-file.path(STATE$temp,"node_modules")
  if(!dir.exists(junction)) {
    ps<-sprintf("New-Item -ItemType Junction -Path '%s' -Target '%s' | Out-Null",
      gsub("'","''",junction,fixed=TRUE),gsub("'","''",STATE$modules,fixed=TRUE))
    status<-system2("powershell.exe",c("-NoProfile","-NonInteractive","-Command",shQuote(ps)),stdout=TRUE,stderr=TRUE)
    assert(is.null(attr(status,"status")),"Cannot link bundled spreadsheet runtime in TEMP")
  }
  out<-system2(STATE$node,c(shQuote(builder),shQuote(json),shQuote(path)),stdout=TRUE,stderr=TRUE)
  assert(is.null(attr(out,"status")) && file.exists(path),paste("Workbook export failed:",paste(out,collapse="\n")))
  log_line(paste(out,collapse=" "))
  checker<-file.path(STATE$temp,"verify_workbook.py")
  verify<-r"---(import json,sys,math
import openpyxl
p=json.load(open(sys.argv[1],encoding='utf-8'))
w=openpyxl.load_workbook(sys.argv[2],read_only=True,data_only=True)
assert w.sheetnames==list(p['sheets']), 'Worksheet names/order mismatch'
checked=0
for name,records in p['sheets'].items():
    if not isinstance(records,list): records=[records]
    fields=list(dict.fromkeys(k for r in records for k in r))
    it=w[name].iter_rows(min_row=3,values_only=True)
    assert next(it)[0]==p['banner'], 'Missing mode warning'
    next(it); head=next(it)
    assert list(head[:len(fields)])==fields, 'Column mismatch: '+name
    for expected in records:
        actual=next(it)
        for j,key in enumerate(fields):
            e=expected.get(key); a=actual[j] if j<len(actual) else None
            if isinstance(e,(list,dict)): e=json.dumps(e,separators=(',',':'),ensure_ascii=False)
            if e=='': e=None
            if isinstance(e,(int,float)) and not isinstance(e,bool):
                assert isinstance(a,(int,float)) and math.isclose(a,e,rel_tol=1e-11,abs_tol=1e-12),(name,key,'Numeric mismatch')
            else: assert a==e,(name,key,'Value mismatch')
            checked+=1
w.close(); print('WORKBOOK ROUNDTRIP PASS: '+str(checked)+' aggregate cells')
)---"
  writeLines(verify,checker,useBytes=TRUE)
  roundtrip<-system2(STATE$audit_python,c(shQuote(checker),shQuote(json),shQuote(path)),stdout=TRUE,stderr=TRUE)
  assert(is.null(attr(roundtrip,"status")),paste("Workbook roundtrip failed:",paste(roundtrip,collapse="\n")))
  log_line(paste(roundtrip,collapse=" "))
  invisible(path)
}
strip_fit <- function(f) {f$fit<-NULL;f$information<-NULL;f$event_lm<-NULL;f}
export_results <- function(data,counts,software,models,results,boots,summaries,decision,ph,sensitivities) {
  eligible<-decision$candidate[decision$criterion_pass]
  selected<-if(length(eligible))tail(eligible,1) else NA_character_
  coefficients<-coefficient_table(models,boots)
  stability<-bind_rows(lapply(names(boots),function(m) {
    rr<-boots[[m]];ok<-vapply(rr,function(z)z$ok,logical(1));msg<-vapply(rr,function(z)z$message,character(1))
    data.frame(model=m,attempted=length(rr),valid=sum(ok),valid_fraction=mean(ok),
      numerical_qualification=if(STATE$mode=="smoke")"SMOKE ONLY" else if(mean(ok)>=.95)"ELIGIBLE" else "PAUSE CANDIDATE",
      failed=sum(!ok),fixed_zero_replicates=sum(vapply(rr,function(z)z$ok && nzchar(z$value$fixed_zero),logical(1))),
      failure_reasons=paste(names(table(msg[nzchar(msg)])),as.integer(table(msg[nzchar(msg)])),collapse="; "))
  }))
  cal<-bind_rows(c(unname(summaries),list(paired_differences(results,boots,selected))))
  addtype<-function(df,type,model=NULL) {if(nrow(df)) {df$record_type<-type;if(!is.null(model))df$model<-model};df}
  more<-list(addtype(cal,"Internal bootstrap metrics"))
  for(m in names(results))for(field in c("curves","groups","joint","hazards"))
    more[[length(more)+1L]]<-addtype(results[[m]][[field]],field,m)
  for(m in names(ph$sensitivity))more[[length(more)+1L]]<-addtype(ph$sensitivity[[m]]$summary,"PH-adjusted sensitivity")
  spec<-bind_rows(list(
    data.frame(item=c("Data scope","Age","Penalty","Model A","Model B","C FULL","C REDUCED","Bootstrap","Inference","PH","No forbidden modules"),
      value=c("2004-2011 only; diagnosis days/365.25; strict time > landmark", "RCS 48/65/76/87; centered70; /10; norm2",
      "Unknown + interactions only; theta1 scaleFALSE; all-zero penalized columns fixed0 only",
      "L1 left entry at diagnosis year1; all follow-up; conditional [F(s+3)-F(s)]/S(s)",
      "3y post-landmark windows; 3 strata; shared effects; patient bootstrap clusters",
      "GBC 5 interactions; Other age10*s; s centered2","GBC T34*s + Nplus*s; Other unchanged",
      paste(STATE$B,"patient draws, seed",CFG$seed,"paired across candidates; no replacement of failed draws"),
      "Primary uncertainty by patient resampling; no independent-row Cox/GLM standard errors",
      "Main PH candidates retained; cox.zph descriptive; 500 probes and bounded sensitivity FINAL only",
      "No validation performance, recalibration, standardization, life-table, contemporary, ML or new predictors")),
    data.frame(item=paste0("SHA256_",names(STATE$hashes)),value=unname(STATE$hashes)),
    data.frame(item=paste0("Package_",names(STATE$packages)),value=unname(STATE$packages)),
    addtype(sensitivities,"Prespecified point-fit stability sensitivities")))
  ledger<-list(counts)
  source<-data$patient
  ledger[[length(ledger)+1L]]<-data.frame(scope=c("Development source","A all-follow-up L1","Stacked unique event union"),
    patients=c(nrow(source),sum(source$time>1),sum(source$time>1)),
    GBC=c(sum(source$status==1),sum(source$time>1 & source$status==1),length(unique(make_landmarks(source)$record_id[make_landmarks(source)$event==1]))),
    Other=c(sum(source$status==2),sum(source$time>1 & source$status==2),length(unique(make_landmarks(source)$record_id[make_landmarks(source)$event==2]))))
  for(s in 1:3) {
    z<-source[source$time>s,]
    for(v in c("sex","T_core","N_model","grade_model"))for(level in sort(unique(z[[v]]))) {
      ii<-z[[v]]==level;ledger[[length(ledger)+1L]]<-data.frame(scope=paste0("L",s),variable=v,level=level,patients=sum(ii),
        GBC=sum(ii & z$time-s<=3 & z$status==1),Other=sum(ii & z$time-s<=3 & z$status==2),
        early_censor=sum(ii & z$time-s<3 & z$status==0))
    }
  }
  sheets<-list(counts=bind_rows(ledger),software_check=software,model_spec=spec,
    coefficients=coefficients,effective_df=effective_df_table(models),bootstrap_stability=stability,
    calibration_slope=bind_rows(more),PH=ph$table,C_decision=decision)
  if(length(ph$sensitivity))sheets$effective_df<-bind_rows(c(list(sheets$effective_df),
    lapply(names(ph$sensitivity),function(m)effective_df_table(setNames(list(ph$sensitivity[[m]]$models),m),"PH sensitivity"))))
  staging<-file.path(STATE$temp,"delivery");dir.create(staging,showWarnings=FALSE)
  files<-c("DEVELOPMENT_RESULTS.xlsx","DEVELOPMENT_REPORT.md","DEVELOPMENT_MODELS.rds")
  staged<-file.path(staging,files)
  images<-make_ph_images(ph$plots)
  make_workbook(sheets,staged[1],images)
  report<-c(paste("#",STATE$banner),"",paste("Generated:",stamp()),
    "", "This is development-only internal analysis of resection-selected registry prognosis, not clinical deployment.",
    "No 2012-2017 validation outcome/prediction/performance was loaded or evaluated.",
    "Numerical probability closure is not empirical calibration. No causal treatment claims are supported.",
    "", "## Execution and audit", "",paste("Mode:",STATE$mode,"; patient bootstrap attempts:",STATE$B,"; seed:",CFG$seed),
    paste("Matched code/data/SAP/runtime fingerprint:",STATE$fingerprint),paste("Checkpoint directory:",STATE$temp),
    "Failed numerical bootstrap attempts count in the 95% denominator; no resampling until 500 successes.",
    "Three repeated landmark records are composite contributions, not independent patients. Resampled copies have new cluster IDs.",
    "Main coefficients are fitted with robust=FALSE because bootstrap is the inferential covariance; no row-wise coefficient SE is reported.",
    "", "## Frozen candidate decision", "",capture.output(print(decision,row.names=FALSE)),
    "",capture.output(print(stability,row.names=FALSE)),
    if(STATE$mode=="smoke")"SMOKE: decisions/intervals/estimates are testing artifacts only. No candidate is formally qualified; 500-replicate PH probes were NOT run." else
      "FINAL: C retained only under both the numerical-validity and corrected-slope rules. An unstable C is not a stable primary candidate.",
    "", "## Definitions", "",
    "A: diagnosis time, delayed entry=1 year, all later follow-up; conditional CIF identity checked at every prediction.",
    "B: separate L1/L2/L3 Breslow baselines, common coefficients. C: only prespecified s interactions; no additional predictor.",
    "Unknown and dynamic coefficients use ridge theta=1, scale=FALSE; no penalization of known main effects or age main effects.",
    "Risk integration uses the union of cause event times and exponential jump allocation; right-continuous step RMTL uses the same curves.",
    "Effective regression df is trace[(I+P)^(-1)I]; baseline nuisance event increments are listed separately.",
    "AUC2 controls include competing deaths. IPCW uses reverse-KM strict left limits; a censor at 3y is a known 3y state.",
    "Brier denominator is ALL eligible patients. Other-death and all-death Brier are separately evaluated, not summed.",
    "Calibration slope is IPCW quasi-binomial horizon-risk logit slope, not Cox LP. Only the link uses clipped probabilities.",
    "Optimism = bootstrap apparent minus bootstrap on original; corrected = original apparent minus mean optimism.",
    "Bootstrap-apparent percentile intervals describe refit-development sampling, not a nested-bootstrap CI for the optimism-corrected estimate or temporal validation.",
    "Metric/curve failures remain NA; sparse nine-cell calibration strata are not merged. No Firth or post hoc smoother selection.",
    "Workbook curves show an aggregate grid, not patient records. Hazard-process O/E is not CIF O/E.",
    "", "## PH and prespecified sensitivities", "",
    "Scaled Schoenfeld score P and curves (including separate Unknown components and landmark-colored smooths) are descriptive under repeated records.",
    "FINAL probes: age10*log(max(v,.25)) and T34*log(max(v,.25)), one at a time; material if 95% patient CI for delta*log(6) entirely exceeds +/-log(1.5), >=95% valid.",
    "If material: original main models unchanged; unified cause-specific prioritized term added in a sensitivity series, at most +1 df/cause, again 500 bootstrap attempts.",
    "The tt probe is the documented exception to model=TRUE because survival does not support that option for tt; x/y retained and time-dependent hazards integrated explicitly.",
    "Fixed theta0.5/2, known-only and excluding top-coded90+ fits are development-only point stability checks, not extra candidates or performance-driven selection.",
    "Unmodeled PH violations, unsupported tails, sparse states and dependent censoring remain limitations, even when a numerical gate passes.",
    "", "## Four-role implementation review", "",
    "Data engineering: input hashes, unique IDs, year firewall, role-filtered long data and stored/rebuilt windows checked; no recleaning or source overwrite.",
    "Survival statistics: delayed entry, strict landmark inclusion, all-follow-up A, tau boundaries, patient units, fixed knots/penalties and effective df explicit.",
    "Competing risk: coherent two-cause integration, A conditioning, observed-state labels, left-limit IPCW, AUC2/Brier/working calibration tested independently.",
    "Reproducibility: fixed streams and same paired draws; checkpoint fingerprint includes source code, inputs, SAP and environment; error stops nonzero, prior successes protected.",
    "", "## Software checks", "",capture.output(print(software,row.names=FALSE)),
    "", "## Provenance", "",capture.output(print(STATE$hashes)),capture.output(print(STATE$packages)),
    "", "This run does not implement or release validation, updating, standardization, life-table or contemporary modules.")
  writeLines(report,staged[2],useBytes=TRUE)
  object<-list(banner=STATE$banner,mode=STATE$mode,seed=CFG$seed,bootstrap_attempts=STATE$B,
    input_hashes=STATE$hashes,fingerprint=STATE$fingerprint,packages=STATE$packages,knots=CFG$knots,
    integration="Exponential jump allocation; strict conditional A; right-continuous step",
    models=lapply(models,function(pair)lapply(pair,strip_fit)),C_decision=decision,
    selected_C=selected,PH_selection=ph$selection,
    PH_sensitivity=lapply(ph$sensitivity,function(v)list(models=lapply(v$models,strip_fit),
      valid_fraction=v$valid_fraction,summary=v$summary)),
    development_summaries=summaries,stability=stability,software_check=software,
    validation_performance_accessed=FALSE,formal_run=STATE$mode=="final",
    formal_candidate_qualification=if(STATE$mode=="final")stability[,c("model","numerical_qualification")] else "NONE - SMOKE ONLY")
  saveRDS(object,staged[3],compress="xz")
  assert(identical(readRDS(staged[3])$input_hashes,STATE$hashes),"Models RDS roundtrip mismatch")
  assert(all(file.info(staged)$size>0),"Missing/empty staged deliverables")
  if(STATE$mode=="smoke") {
    log_line(paste("SMOKE TEST / NOT FOR ARTICLE outputs remain in",staging));return(staged)
  }
  target<-file.path(STATE$root,"outputs",files)
  assert(!any(file.exists(target)),"Existing formal results protected; FINAL refuses overwrite")
  created<-character()
  tryCatch({
    for(i in seq_along(staged)) {
      assert(!file.exists(target[i]),"Concurrent formal output detected")
      assert(file.copy(staged[i],target[i],overwrite=FALSE),paste("Publish failed:",files[i]))
      created<-c(created,target[i])
      assert(digest::digest(file=staged[i],algo="sha256")==digest::digest(file=target[i],algo="sha256"),"Published output hash mismatch")
    }
  },error=function(e) {if(length(created))unlink(created);stop(e)})
  target
}

main <- function(args=commandArgs(trailingOnly=TRUE)) {
  files<-commandArgs(FALSE); script<-sub("^--file=","",files[grepl("^--file=",files)])
  assert(length(script)==1,"Launch with Rscript run_development.R --mode smoke|final")
  STATE$script<-normalizePath(script,winslash="/",mustWork=TRUE)
  STATE$root<-normalizePath(file.path(dirname(STATE$script),".."),winslash="/",mustWork=TRUE)
  setwd(STATE$root)
  self_test<-identical(args,"--self-test")
  if(self_test) {STATE$mode<-"synthetic";STATE$B<-0L} else {
    assert(length(args)==2 && args[1]=="--mode" && args[2]%in%c("smoke","final"),"Usage: --mode smoke|final (no arbitrary bootstrap count)")
    STATE$mode<-args[2];STATE$B<-if(STATE$mode=="smoke")10L else 500L
  }
  STATE$banner<-if(STATE$mode=="smoke")"SMOKE TEST / NOT FOR ARTICLE" else "DEVELOPMENT INTERNAL ANALYSIS / 2004-2011"
  dir.create("logs",showWarnings=FALSE);dir.create("outputs",showWarnings=FALSE)
  STATE$log<-file.path(STATE$root,"logs","development_live.log")
  project_key<-gsub("[^A-Za-z0-9]","_",tolower(STATE$root))
  lock<-file.path(Sys.getenv("TEMP"),paste0("gbc_development_",project_key,".lock"))
  assert(dir.create(lock,showWarnings=FALSE),paste("Run lock exists. Confirm no R run is active before removing:",lock))
  on.exit(unlink(lock,recursive=TRUE),add=TRUE)
  if(file.exists("logs/ERROR_REPORT.txt")) {
    backup<-file.path(Sys.getenv("TEMP"),paste0("gbc_previous_error_",format(Sys.time(),"%Y%m%d_%H%M%S"),".txt"))
    assert(file.copy("logs/ERROR_REPORT.txt",backup,overwrite=FALSE),"Cannot archive previous error report")
    unlink("logs/ERROR_REPORT.txt")
  }
  stage("START",{log_line(paste("PROGRAM",STATE$banner,"bootstrap",STATE$B,"seed",CFG$seed));TRUE})
  if(STATE$mode=="final")assert(!any(file.exists(file.path("outputs",c("DEVELOPMENT_RESULTS.xlsx","DEVELOPMENT_REPORT.md","DEVELOPMENT_MODELS.rds")))),"Existing final outputs protected: no overwrite")
  STATE$environment<-stage("ENVIRONMENT CHECK",environment_check())
  if(self_test) {stage("SOFTWARE TEST",synthetic_tests());stage("DONE",TRUE);return(invisible(TRUE))}
  stage("HASH CHECK",hash_check())
  data<-stage("DATA LOAD",load_data());counts<-check_data(data)
  software<-stage("SOFTWARE TEST",checkpoint_get("software",synthetic_tests()))
  d<-data$patient
  draws<-checkpoint_get("development_draws",patient_draws(nrow(d),STATE$B,substream=0L))
  models<-list()
  models$A<-stage("MODEL A",checkpoint_get("model_A",fit_model_a(d,full=TRUE)))
  models$B<-stage("MODEL B",checkpoint_get("model_B",fit_model_b(d,full=TRUE)))
  models$C_FULL<-stage("MODEL C FULL",checkpoint_get("model_C_FULL",fit_model_c(d,full=TRUE)))
  results<-lapply(models,evaluate_model,d=d,detailed=TRUE)
  boots<-list();summaries<-list()
  for(m in names(models)) {
    boot_stage<-paste("BOOTSTRAP",if(m=="C_FULL")"C" else m)
    boots[[m]]<-stage(boot_stage,run_bootstrap(d,m,models[[m]],draws$draws))
    summaries[[m]]<-bootstrap_summary(results[[m]],boots[[m]],m)
  }
  decision<-stage("C DECISION",decide_c(summaries$C_FULL,boots$C_FULL,"C_FULL"))
  if(!decision$criterion_pass) {
    stage("C REDUCED",{
      models$C_REDUCED<-checkpoint_get("model_C_REDUCED",fit_model_c(d,reduced=TRUE,full=TRUE))
      results$C_REDUCED<-evaluate_model(models$C_REDUCED,d,detailed=TRUE)
      boots$C_REDUCED<-run_bootstrap(d,"C_REDUCED",models$C_REDUCED,draws$draws)
      summaries$C_REDUCED<-bootstrap_summary(results$C_REDUCED,boots$C_REDUCED,"C_REDUCED")
      decision<-rbind(decision,decide_c(summaries$C_REDUCED,boots$C_REDUCED,"C_REDUCED"));TRUE
    })
  }
  ph<-stage("PH",checkpoint_get("PH_result",run_ph(d,models)))
  sensitivities<-checkpoint_get("stability_sensitivities",development_sensitivities(d,models))
  paths<-stage("EXPORT",export_results(data,counts,software,models,results,boots,summaries,decision,ph,sensitivities))
  stage("DONE",{log_line("VALIDATION PERFORMANCE ACCESSED = NO");log_line("ANALYSIS COMPLETED SUCCESSFULLY");TRUE})
  invisible(paths)
}
if(sys.nframe()==0L) {
  status<-tryCatch(withCallingHandlers({main();0L},error=function(e) {
    STATE$trace<-vapply(sys.calls(),function(c)paste(deparse(c),collapse=" "),character(1))
  }),error=function(e) {
    tryCatch(write_error(e),error=function(report_error)cat("ERROR REPORT FAILURE:",conditionMessage(report_error),"\nOriginal:",conditionMessage(e),"\n"))
    1L
  })
  quit(save="no",status=status,runLast=FALSE)
}


