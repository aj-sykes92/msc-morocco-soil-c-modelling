
library(raster)
library(tidyverse)
library(ncdf4)
library(lubridate)

gisdata_repo <- "GIS data repository"

# check out ncdf data and read in as raster bricks
nc_open(find_onedrive(dir = gisdata_repo, path = "UKCP/60km-global/tas_rcp85_land-gcm_global_60km_01_mon_189912-209911.nc"))
nc_open(find_onedrive(dir = gisdata_repo, path = "UKCP/60km-global/pr_rcp85_land-gcm_global_60km_01_mon_189912-209911.nc"))

Stk_temp <- brick(find_onedrive(dir = gisdata_repo, path = "UKCP/60km-global/tas_rcp85_land-gcm_global_60km_01_mon_189912-209911.nc"))
Stk_precip <- brick(find_onedrive(dir = gisdata_repo, path = "UKCP/60km-global/pr_rcp85_land-gcm_global_60km_01_mon_189912-209911.nc"))

# read in shapefile and mask brick
Shp_Mor <- read_rds("helper-data/morocco-shapefile.rds")
Stk_temp <- Stk_temp %>% crop(Shp_Mor)
Stk_precip <- Stk_precip %>% crop(Shp_Mor)

plot(Stk_temp[[1:12]])
plot(Stk_precip[[1:12]])

# make names unique
sum(names(Stk_temp) != names(Stk_precip)) # names/dates match exactly

names(Stk_temp) <- names(Stk_temp) %>% str_replace("^X", "temp")
names(Stk_precip) <- names(Stk_precip) %>% str_replace("^X", "precip")

# convert all to dataframe
Dat_clim <- stack(Stk_temp, Stk_precip) %>% as.data.frame(xy = T) %>% as_tibble()

# gather and spread by variable type
Dat_clim <- Dat_clim %>%
  gather(-x, -y, key = "key", value = "value") %>%
  mutate(date = key %>%
           str_replace_all("[:lower:]", "") %>%
           str_replace_all("\\.", "-") %>%
           ymd_hms(),
         metric = key %>%
           str_extract("^[:lower:]+(?=\\d)")) %>%
  select(-key) %>%
  spread(key = metric, value = value) %>%
  rename(temp_centigrade = temp,
         precip_mm = precip)

nrow(Dat_clim %>% drop_na()) # no NAs to speak of

# convert precipitation to monthly total
Dat_clim <- Dat_clim %>%
  mutate(precip_mm = precip_mm * days_in_month(date))

# calculate month and year and nest
Dat_clim <- Dat_clim %>%
  mutate(date = as_date(date),
         month = month(date),
         year = year(date)) %>%
  group_by(x, y) %>%
  nest() %>%
  ungroup()

# compress and interpolate where necessary
# this UKCP data is bloody awkward to get in monthly format
temp <- tibble(date = seq(from = ymd("1902-01-16"), to = ymd("2096-12-17"), by = as.difftime(months(1))) %>% ymd(),
               month = month(date),
               year = year(date)) %>%
  select(-date)

Dat_clim <- Dat_clim %>%
  mutate(data_reg = data %>%
           map(function(df){
             df %>%
               group_by(month, year) %>%
               summarise(temp_centigrade = mean(temp_centigrade),
                         precip_mm = mean(precip_mm))
           }),
         data_reg = data_reg %>%
           map(function(df){
             df %>%
               right_join(temp, by = c("month", "year"))
           }),
         data_reg = data_reg %>%
           map(function(df){
             df %>%
               mutate(temp_centigrade = temp_centigrade %>% forecast::na.interp() %>% as.numeric(),
                      precip_mm = precip_mm %>% forecast::na.interp() %>% as.numeric())
           })
  )

# calculate pet using thornthwaite method
# https://upcommons.upc.edu/bitstream/handle/2117/89152/Appendix_10.pdf?sequence=3&isAllowed=y

# daylength calculations using insol
library(insol)

lats <- Dat_clim %>%
  pull(y) %>%
  unique()

jdays <- tibble(date = seq(from = ymd("2019-01-01"), to = ymd("2019-12-31"), by = as.difftime(days(1)))) %>%
  mutate(month = month(date),
         jday = yday(date),
         mday = days_in_month(date)) %>%
  group_by(month) %>%
  summarise(mday = mean(mday),
            jday = mean(jday))


daylength <- tibble(y = rep(lats, 12),
                    month = rep(1:12, each = length(lats))) %>%
  left_join(jdays, by = "month") %>%
  mutate(lon = 0,
         time_zone = 0,
         daylength = pmap_dbl(list(y, lon, jday, time_zone), function(a, b, c, d){
           return(daylength(a, b, c, d)[3])
         }))

# function required to combat annoying R 'feature' (returns NaN for negative numbers raised to non-integer powers...)
rtp <- function(x, power){
  sign(x) * abs(x) ^ (power)
}

Dat_clim <- Dat_clim %>%
  mutate(data_reg = map2(y, data_reg, function(lat, df){
    df %>%
      mutate(y = lat) %>%
      group_by(year) %>%
      mutate(I = sum(rtp(temp_centigrade / 5, 1.514)),
             alpha = 675*10^-9 * rtp(I, 3) - 771*10^-7 * rtp(I, 2) + 1792*10^-5 * I + 0.49239,
             pet_mm = rtp(16 * ((10 * temp_centigrade) / I), alpha)) %>%
      ungroup() %>%
      left_join(daylength %>% select(y, month, daylength, mday), by = c("y", "month")) %>%
      mutate(pet_mm = pet_mm * daylength / 12 * mday / 30,
             pet_mm = ifelse(pet_mm < 1, 1, pet_mm)) %>% # prevents errors with negative PET/div by zero
      select(-y, -I, -alpha, -mday, -daylength) %>%
      mutate(precip_mm = ifelse(precip_mm < 0, 0, precip_mm)) # # another quick and dirty fix for potential errors - occasional negative precipitation values
  }))

# number cells (x-y pairs) to allow raster-based extraction of data
Dat_clim <- Dat_clim %>%
  mutate(cell_no = 1:nrow(Dat_clim)) %>%
  select(x, y, cell_no, data_full = data_reg)

# filter data to > 1961 (no data for crops from before this)
Dat_clim <- Dat_clim %>%
  mutate(data_full = data_full %>%
           map(function(df){
             df %>%
               filter(year >= 1961)
           }))

# write out full climate data
write_rds(Dat_clim, "helper-data/morocco-full-climate-data-1902-2097.rds")

# how about a helper raster to allow spatial point querying of data?
# number lat/lon values and transform to raster, keep numbers in climate df
Ras_help <- Dat_clim %>%
  select(x, y, z = cell_no) %>%
  rasterFromXYZ()

# write out
write_rds(Ras_help, "helper-data/morocco-climate-data-helper-raster.rds")
