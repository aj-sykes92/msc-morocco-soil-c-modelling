library(tidyverse)
library(raster)

Shp_Mor <- read_rds("helper-data/morocco-shapefile.rds")

gisdata_repo <- "GIS data repository"

# read in crop area raster data and stack
readdir <- find_onedrive(dir = gisdata_repo, path = "MapSpam data/Physical area")
file.names <- dir(readdir, pattern =".tif")

Crop_area_stack <- raster::stack()
for(i in 1:length(file.names)){
  readpath <- paste(readdir, file.names[i], sep="/") # aggregate strings to create filepath
  x <- raster(readpath) # read raster
  Crop_area_stack <- addLayer(Crop_area_stack, x)
  rm(x)
  print(file.names[i])
}

# read in crop yield raster data and stack
readdir <- find_onedrive(dir = gisdata_repo, path = "MapSpam data/Yield")
file.names <- dir(readdir, pattern =".tif")

Crop_yield_stack <- raster::stack()
for(i in 1:length(file.names)){
  readpath <- paste(readdir, file.names[i], sep="/") # aggregate strings to create filepath
  x <- raster(readpath) # read raster
  Crop_yield_stack <- addLayer(Crop_yield_stack, x)
  rm(x)
  print(file.names[i])
}
rm(readdir, file.names, readpath, i)

Crop_area_stack <- Crop_area_stack %>%
  crop(Shp_Mor) %>%
  mask(Shp_Mor)

Crop_yield_stack <- Crop_yield_stack %>%
  crop(Shp_Mor) %>%
  mask(Shp_Mor)

plot(Crop_area_stack[[1]])
plot(Shp_Mor, add = T)
hist(Crop_area_stack[[1]])

# select out crops with zero area
isnt_zero <- function(x){
  y <- x == 0 | is.na(x)
  z <- F %in% y == T
  return(z)
}

Dat_area <- Crop_area_stack %>%
  as.data.frame()

nonzero <- Dat_area %>%
  select_if(isnt_zero) %>%
  colnames()

# select only crops which have area of > 0
Crop_area_stack <- Crop_area_stack[[which(Crop_area_stack %>% names() %in% nonzero)]]
Crop_yield_stack <- Crop_yield_stack[[which(Crop_yield_stack %>% names() %in% str_replace(nonzero, "phys_area", "yield"))]]

# cute af
plot(Crop_area_stack[[1:16]])
plot(Crop_area_stack[[17:29]])

# get rid of layers which we can't match to other data (i.e. faostat, model parameters)
Dat_fs <- read_rds("helper-data/morocco-crop-yields-1961-2018.rds")

crop_names <- tibble(orig = names(Crop_area_stack))

Dat_fs <- read_rds("helper-data/morocco-crop-yields-1961-2018.rds")

crop_names <- crop_names %>%
  mutate(trans = c(NA, "barley", "beans-and-pulses", "rye", NA, NA, NA, NA, NA, "peanut",
                   NA, "maize", "millet", NA, "potato", NA, NA, NA, "rice", "tubers",
                   NA, "sorghum", "soybean", NA, NA, NA, NA, NA, "wheat"))

crop_names <- crop_names %>%
  drop_na()
keep <- crop_names$orig

# filter stacks
Crop_area_stack <- Crop_area_stack[[which(Crop_area_stack %>% names() %in% keep)]]
Crop_yield_stack <- Crop_yield_stack[[which(Crop_yield_stack %>% names() %in% str_replace(keep, "phys_area", "yield"))]]

# rename
names(Crop_area_stack) <- crop_names$trans
names(Crop_yield_stack) <- crop_names$trans

# force R to commit to memory so we can save as .rds
Crop_area_stack <- readAll(Crop_area_stack)
Crop_yield_stack <- readAll(Crop_yield_stack)

# write out data
write_rds(Crop_area_stack, "helper-data/morocco-crop-area-ha-2010.rds")
write_rds(Crop_yield_stack, "helper-data/morocco-crop-yield-tonnes-per-ha-2010.rds")

# let's do soil sand % while we're here
Ras_sand <- raster(find_onedrive(dir = gisdata_repo, path = "SoilGrids 5km/Sand content/Fixed/SNDPPT_M_sl3_5km_ll.tif"))

Ras_sand <- Ras_sand %>%
  crop(Shp_Mor) %>%
  mask(Shp_Mor)

plot(Ras_sand)
names(Ras_sand) <- "soil_sand_pc"

Ras_sand <- readAll(Ras_sand) # throws an error cos it's already read it in — keep anyway jic
write_rds(Ras_sand, "helper-data/morocco-soil-sand-percentage.rds")

