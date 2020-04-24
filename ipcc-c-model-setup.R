
library(tidyverse)

#####################################################
# get set up with data and functions
#####################################################

# source function script
source("ipcc-c-model-functions.R")

# read in main climate data
# we'll use this as the basis for the model simulation
Dat_nest <- read_rds("model-data/morocco-example-climate-data.rds")

# yield data for default morocco crop data
Dat_crop <- read_csv("model-data/morocco-example-crop-data.csv")

# manure application for default morocco crop data
Dat_manure <- read_csv("model-data/morocco-example-manure-data.csv")

#####################################################
# starting with monthly climate variables, condensing to annual modification factors (tfac and wfac)
#####################################################
Dat_nest <- Dat_nest %>%
  mutate(data_full = data_full %>%
           map(function(df){
             df %>%
               group_by(year) %>%
               summarise(wfac = wfac(precip = precip_mm, PET = pet_mm),
                         tfac = tfac(temp = temp_centigrade)) %>%
               ungroup()
           }))

#####################################################
# calculate crop-specific variables in the crop dataset
#####################################################

# C inputs from crop residues and manure
Dat_crop <- Dat_crop %>%
  mutate(C_res = pmap_dbl(list(yield_tha, crop_type, frac_renew, frac_remove),
                          C_in_residues)) %>%
  left_join(Dat_manure, by = "year") %>%
  mutate(C_man = pmap_dbl(list(man_nrate, man_type),
                          C_in_manure),
         N_frac = pmap_dbl(list(crop_type, man_type, C_res, C_man),
                           N_frac),
         lignin_frac = pmap_dbl(list(crop_type, man_type, C_res, C_man),
                                lignin_frac),
         C_tot = C_res + C_man)
rm(Dat_manure)

#####################################################
# join crop-specific variables to main model data
#####################################################
# also adding in sand fraction data here since it's an odd one out
Dat_nest <- Dat_nest %>%
  mutate(data_full = data_full %>%
           map(function(df){
             df %>%
               #mutate(sand_frac = sand_frac) %>%
               left_join(Dat_crop %>%
                           select(year, N_frac, lignin_frac, C_tot, sand_frac), by = "year")
           }))

#####################################################
# run in model for 20 year period and add tillage type
# can't run in with tillage already added, since it can't be averaged
#####################################################
runin_years <- 20

Dat_nest <- Dat_nest %>%
  mutate(data_runin = data_full %>%
           map2(runin_years, run_in) %>%
           map(function(df){
             df %>%
               left_join(Dat_crop %>% select(year, till_type), by = "year") %>%
               mutate(till_type = ifelse(is.na(till_type), "full", till_type))
           }))
           
#####################################################
# run model
#####################################################
Dat_nest <- Dat_nest %>%
  mutate(scenario_baseline = data_runin %>%
           map(run_model))

#####################################################
# write out .rds with baseline scenario
#####################################################
Dat_nest %>%
  select(sample, scenario_baseline) %>%
  write_rds("model-scenarios/scenario-baseline.rds")
