library(modelr)
library(tidyverse)
library(tidyr)
setwd("~/rds/hpc-work/Multiple-trial-emulation-IPTW-MSM-CIs/Code")
source("simulate_MSM_simplified.R")
source("weight_func.R")
set.seed(20222022)
library(TrialEmulation, lib.loc = '/home/jml219/R/x86_64-redhat-linux-gnu-library/4.3')
library(MASS)
library(sandwich)
library(foreach)
library(doParallel)
library(doRNG)
#library(rlist)


treat <- c(-1,0,1)
conf <- c(0.1,0.5,0.9)
outcome_prev <- c(-4.7,-3.8,-3)

scenarios <- tidyr::crossing(conf, treat, outcome_prev)


bootstrap_iter <- 2
registerDoParallel(cores = 2)

#l <- as.numeric(Sys.getenv('SLURM_ARRAY_TASK_ID'))
estimates_boot <- as.data.frame(matrix(,5,bootstrap_iter))
estimates_boot <- foreach(k = 1:bootstrap_iter, .combine=cbind) %dopar% {
  simdata_censored <-DATA_GEN_censored_reduced(100000, 5, 
                                               conf = as.numeric(scenarios[l,1]), 
                                               treat_prev = as.numeric(scenarios[l,2]),
                                               outcome_prev = as.numeric(scenarios[l,3]),
                                               censor = F)
  PP_prep <- TrialEmulation::data_preparation(simdata_censored, id='ID', period='t', treatment='A', outcome='Y', 
                                              eligible ='eligible',
                                              switch_d_cov = ~X2 + X4,
                                              outcome_cov = ~X2 + X4, model_var = c('assigned_treatment'),
                                              use_weight=T, use_censor=T, quiet = T,
                                              save_weight_models = F)
  switch_data <- PP_prep$data %>% 
    dplyr::mutate(t_1 = ifelse(followup_time == 1,1,0),
                  t_2 = ifelse(followup_time == 2,1,0),
                  t_3 = ifelse(followup_time == 3,1,0),
                  t_4 = ifelse(followup_time == 4,1,0),
                  t_1A = t_1*assigned_treatment,
                  t_2A = t_2*assigned_treatment,
                  t_3A = t_3*assigned_treatment,
                  t_4A = t_4*assigned_treatment,
                  t_1X2 = t_1*X2,
                  t_2X2 = t_2*X2,
                  t_3X2 = t_3*X2,
                  t_4X2 = t_4*X2,
                  t_1X4 = t_1*X4,
                  t_2X4 = t_2*X4,
                  t_3X4 = t_3*X4,
                  t_4X4 = t_4*X4)
  
  my_covariates <- ~ X2 + X4+ assigned_treatment+
    t_1 + t_2 + t_3 + t_4 +
    t_1A + t_2A + t_3A + t_4A + 
    t_1X2 + t_2X2 + t_3X2 + t_4X2 + 
    t_1X4 + t_2X4 + t_3X4 + t_4X4
  
  PP <- TrialEmulation::trial_msm(data = switch_data,
                                  outcome_cov = my_covariates,
                                  model_var = c('assigned_treatment'),
                                  glm_function = 'glm',
                                  include_trial_period = ~1, include_followup_time = ~1,
                                  use_weight=T, use_censor=T, quiet = T, use_sample_weights =  F)
  
  if(is.na(PP$model$coefficients['t_4A']) == T){
    PP$model <- update(PP$model, . ~ . - t_4A, data = switch_data)
    my_covariates <- ~ X2 + X4+ assigned_treatment+
      t_1 + t_2 + t_3 + t_4 +
      t_1A + t_2A + t_3A + 
      t_1X2 + t_2X2 + t_3X2 + t_4X2 + 
      t_1X4 + t_2X4 + t_3X4 + t_4X4
    if(is.na(PP$model$coefficients['t_3A']) == T){
      PP$model <- update(PP$model, . ~ . - t_3A, data = switch_data)
      my_covariates <- ~ X2 + X4+ assigned_treatment+
        t_1 + t_2 + t_3 + t_4 +
        t_1A + t_2A + 
        t_1X2 + t_2X2 + t_3X2 + t_4X2 + 
        t_1X4 + t_2X4 + t_3X4 + t_4X4
    }
  }
  
  
  design_mat <- expand.grid(id = 1:100000,
                            trial_period = 0:4,
                            followup_time = 0:4) 
  design_mat <- design_mat[which(5 -design_mat$trial_period > design_mat$followup_time),]
  
  fitting_data_treatment <-  switch_data %>% 
    dplyr::mutate(assigned_treatment = followup_time*0 + 1) %>% 
    dplyr::select(id,trial_period, followup_time, X2,  X4, assigned_treatment) %>% 
    merge(design_mat, by = c("id", "trial_period", "followup_time"), all.y = TRUE) %>% 
    dplyr::group_by(id) %>% 
    tidyr::fill( X2,X4,assigned_treatment,.direction = "down") %>% 
    dplyr::ungroup() %>% 
    dplyr::select(id, trial_period, followup_time, X2, X4, assigned_treatment) %>% 
    merge(data.frame(id = switch_data$id, trial_period = switch_data$trial_period), by = c("id", "trial_period"), all.y = TRUE) %>% 
    dplyr::arrange(id, trial_period, followup_time) %>% 
    dplyr::mutate(t_1 = ifelse(followup_time == 1,1,0),
                  t_2 = ifelse(followup_time == 2,1,0),
                  t_3 = ifelse(followup_time == 3,1,0),
                  t_4 = ifelse(followup_time == 4,1,0),
                  t_1A = t_1*assigned_treatment,
                  t_2A = t_2*assigned_treatment,
                  t_3A = t_3*assigned_treatment,
                  t_4A = t_4*assigned_treatment,
                  t_1X2 = t_1*X2,
                  t_2X2 = t_2*X2,
                  t_3X2 = t_3*X2,
                  t_4X2 = t_4*X2,
                  t_1X4 = t_1*X4,
                  t_2X4 = t_2*X4,
                  t_3X4 = t_3*X4,
                  t_4X4 = t_4*X4) %>% 
    dplyr::filter(trial_period == 0)
  
  fitting_data_treatment <- fitting_data_treatment[!duplicated(fitting_data_treatment),]
  
  fitting_data_control <- fitting_data_treatment %>% 
    dplyr::mutate(assigned_treatment = assigned_treatment*0,
                  t_1A = t_1*0,
                  t_2A = t_2*0,
                  t_3A = t_3*0,
                  t_4A = t_4*0)
  
  Y_pred_PP_treatment <- predict.glm(PP$model, 
                                     fitting_data_treatment, 
                                     type = "response")
  Y_pred_PP_control <- predict.glm(PP$model, 
                                   fitting_data_control,
                                   type = "response")
  predicted_probas_PP <- fitting_data_treatment %>% 
    dplyr::mutate(predicted_proba_treatment = Y_pred_PP_treatment,
                  predicted_proba_control = Y_pred_PP_control) %>% 
    dplyr::group_by(id, trial_period) %>% 
    dplyr::mutate(cum_hazard_treatment = cumprod(1-predicted_proba_treatment),
                  cum_hazard_control = cumprod(1-predicted_proba_control)) %>% 
    dplyr::ungroup() %>% 
    dplyr::group_by(followup_time) %>% 
    dplyr::summarise(survival_treatment = mean(cum_hazard_treatment),
                     survival_control = mean(cum_hazard_control),
                     survival_difference = survival_treatment - survival_control,
                     mrd = - survival_difference )
  
  predicted_probas_PP[,5]
}
    
true_value_boot <- rowMeans(estimates_boot, na.rm = TRUE)

save(true_value_boot, file = paste0("true_value_red_pseudo_true_boot_500it_200000p",as.character(l),".rda"))

