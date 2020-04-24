# load packages
library(tidyverse)
library(raster)

########################################################
# Read in model helper datasets (DON'T NEED TO MODIFY) #
########################################################

# climate dataset
Dat_clim <- read_rds("helper-data/morocco-full-climate-data-1902-2097.rds")

# climate dataset helper raster
Ras_clim <- read_rds("helper-data/morocco-climate-data-helper-raster.rds")

# crop area and yield data
Brk_croparea <- read_rds("helper-data/morocco-crop-area-ha-2010.rds")
Brk_cropyield <- read_rds("helper-data/morocco-crop-yield-tonnes-per-ha-2010.rds")

# faostat yield statistics
Dat_faostat <- read_rds("helper-data/morocco-crop-yields-faostat-1961-2018.rds")

# sand % raster
Ras_sand <- read_rds("helper-data/morocco-soil-sand-percentage.rds")

# Morocco shapefile (for plots)
Shp_Mor <- read_rds("helper-data/morocco-shapefile.rds")

###################################################
# Examine helper datasets (DON'T NEED TO MODIFY)  #
###################################################

# crop rasterbrick data
plot(Brk_croparea)
plot(Brk_cropyield)

# climate data
sample_n(Dat_clim, 10, replace = F) # it's nested — we should also check out one of the nested datasets
Dat_clim$data_full[[1]] %>% head(10)

# check out the climate data 'helper' raster too
# it has numbered cells, from 1:225
plot(Ras_clim)
plot(Shp_Mor, add = T)

# soil sand raster
plot(Ras_sand)
plot(Shp_Mor, add = T)

# faostat crop yield timeseries
sample_n(Dat_faostat, 10, replace = F)

####################################################
# Define model setup variables (MODIFY AS NEEDED)  #
####################################################
crop_type <- "wheat" # name of crop of interest
frac_renew <- 1 / 1 # fraction of crop renewed every year (for e.g. crop renewed every three years, frac_renew = 1 / 3)
frac_remove <- 0.7 # fraction of crop residues removed

manure_type <- "beef-cattle" # type of animal used to produce manure
manure_nrate <- 0 # application rate of manure in kg N per hectare
till_type <- "full" # type of tillage, either full, reduced or zero

sim_start_year <- 1961 # year simulation to start (min = 1961)
sim_end_year <- 2097 ## year simulation to end (max = 2097)

#########################################################
# Define location of crop production (MODIFY AS NEEDED) #
#########################################################
lat_lon <- tibble(x = -8.1, y = 31.6) # default chosen here is a high-yielding arable land near Marrackech

#############################################################
# Extract choices from main datasets (DON'T NEED TO MODIFY) #
#############################################################
temp_cropname <- crop_type %>% str_replace_all("-", "\\.") # necessary adjustment as raster doesn't like hyphens

# extract relevant crop raster from crop bricks
Ras_cropyield <- Brk_cropyield[[which(names(Brk_cropyield) == temp_cropname)]]
Ras_croparea <- Brk_croparea[[which(names(Brk_croparea) == temp_cropname)]]
rm(temp_cropname)

# extract from rasters based on points
yield_tha <- raster::extract(Ras_cropyield, lat_lon)
area_ha <- raster::extract(Ras_croparea, lat_lon)
sand_pc <- raster::extract(Ras_sand, lat_lon)
clim_coord_no <- raster::extract(Ras_clim, lat_lon)

###############################################################################################
# create timeseries of crop yields and areas based on faostat time series (MODIFY AS DESIRED) #
###############################################################################################

# read in barley yields and convert to relative (base year 2010)
Dat_crop_ts <- Dat_faostat %>% 
  filter(crop == crop_type,
         year >= sim_start_year) %>%
  mutate(yield_rel = yield_tha / yield_tha[year == 2010],
         area_rel = area_harvested / area_harvested[year == 2010]) %>%
  dplyr::select(crop, year, yield_rel, area_rel)

# convert to yields for extracted area
Dat_crop_ts <- Dat_crop_ts %>%
  mutate(yield_tha = yield_rel * yield_tha,
         area_ha = area_rel * area_ha)

# plot
Dat_crop_ts %>%
  ggplot(aes(x = year, y = yield_tha)) +
  geom_line()

# 10 year mean and sd for crop yield
yield_mean <- Dat_crop_ts %>% tail(10) %>% pull(yield_tha) %>% mean()
yield_sd <- Dat_crop_ts %>% tail(10) %>% pull(yield_tha) %>% sd()
area_mean <- Dat_crop_ts %>% tail(10) %>% pull(area_ha) %>% mean()
area_sd <- Dat_crop_ts %>% tail(10) %>% pull(area_ha) %>% sd()

# randomly generated barley yield to 2070 based on 10-year performance
set.seed(260592)
Dat_preds <- tibble(year = 2019:sim_end_year,
                    yield_tha = rnorm(n = length(2019:sim_end_year), mean = yield_mean, sd = yield_sd),
                    area_ha = rnorm(n = length(2019:sim_end_year), mean = area_mean, sd = area_sd))

# bind simulation with historical data
Dat_crop_ts <- bind_rows("historical" = Dat_crop_ts,
                       "simulated" = Dat_preds,
                       .id = "origin")

# plot to check
Dat_crop_ts %>%
  ggplot(aes(x = year, y = yield_tha, colour = origin)) +
  geom_line()

Dat_crop_ts %>%
  ggplot(aes(x = year, y = area_ha, colour = origin)) +
  geom_line()

######################################################################
# write out crop and manure data files (MODIFY FILE NAMES AS NEEDED) #
######################################################################

# write out crop data
Dat_crop_ts %>%
  mutate(crop_type = crop_type,
         frac_renew = frac_renew,
         frac_remove = frac_remove,
         till_type = till_type,
         sand_frac = sand_pc / 100) %>%
  dplyr::select(origin, year, crop_type, yield_tha, frac_renew, frac_remove, sand_frac, till_type) %>%
  write_csv("model-data/morocco-example-crop-data.csv")

# write out manure data
tibble(year = sim_start_year:sim_end_year,
       man_type = manure_type,
       man_nrate = manure_nrate) %>%
  write_csv("model-data/morocco-example-manure-data.csv")

#####################################################################################
# build stochastic climate simulation and write out climate file (MODIFY AS NEEDED) #
#####################################################################################

# climate adjustment by simulation end (fractional, default i.e. no change = 0)
mean_sim_end <- 0

# climate uncertainty (fractional std. dev. default i.e. no uncertainty = 0)
sd_sim_end <- 0.3

# number of Monte Carlo repetitions
# (more than 100 at your own risk — depending on your processor it may be too much for it to handle)
MC_n <- 100

Dat_clim <- Dat_clim %>%
  filter(cell_no == clim_coord_no) %>%
  dplyr::select(-cell_no) %>%
  slice(rep(1, MC_n)) %>%
  add_column(sample = 1:MC_n, .before = "data_full") %>%
  mutate(data_full = pmap(list(mean_sim_end, sd_sim_end, sim_start_year, sim_end_year, data_full), function(mean, sd, start, end, df){
    
    df <- df %>% filter(year >= start,
                        year <= end)
    
    det <- df %>% filter(year < 2020) %>% nrow()
    stoch <- df %>% filter(year >= 2020) %>% nrow()
    
    mean_seq <- seq(from = 0, to = mean, length.out = stoch)
    sd_seq <- seq(from = 0, to = sd, length.out = stoch)
    
    # stationary autoregressive process
    x <- w <- rnorm(n = stoch, mean = mean_seq, sd = sd_seq)
    for(t in 2:stoch) x[t] <- (x[t - 1] / 2) + w[t]
    x1 <- c(rep(0, det), x)
    
    x <- w <- rnorm(n = stoch, mean = mean_seq, sd = sd_seq)
    for(t in 2:stoch) x[t] <- (x[t - 1] / 2) + w[t]
    x2 <- c(rep(0, det), x)
    
    x <- w <- rnorm(n = stoch, mean = mean_seq, sd = sd_seq)
    for(t in 2:stoch) x[t] <- (x[t - 1] / 2) + w[t]
    x3 <- c(rep(0, det), x)
    
    df %>%
      mutate(temp_centigrade = temp_centigrade * (1 + x1),
             precip_mm = precip_mm * (1 + x2),
             pet_mm = pet_mm * (1 + x3),
             temp_centigrade = ifelse(temp_centigrade < 0, 0, temp_centigrade),
             precip_mm = ifelse(precip_mm < 0, 0, precip_mm),
             pet_mm = ifelse(pet_mm < 0, 0, pet_mm)) %>%
      return()
  }))

# write out climate data  
write_rds(Dat_clim, "model-data/morocco-example-climate-data.rds")


