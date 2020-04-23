
library(raster)
library(sp)
library(tidyverse)

gisdata_repo <- "GIS data repository"

Mor_shp <- shapefile(find_onedrive(dir = gisdata_repo, path = "Country shapefile/countries.shp"))

Mor_shp <- Mor_shp %>% subset(ISO3 == "MAR")
plot(Mor_shp)
Mor_shp

write_rds(Mor_shp, "helper-data/morocco-shapefile.rds")
