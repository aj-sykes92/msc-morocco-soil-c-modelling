
library(tidyverse)

Dat_fs <- read_csv("not-for-students/FAOSTAT_data_4-24-2020.csv")

glimpse(Dat_fs)

Dat_fs <- Dat_fs %>%
  select(metric = Element, year = Year, units = Unit, value = Value, crop = Item)

Dat_fs <- Dat_fs %>%
  mutate(metric = metric %>% str_to_lower %>% str_replace_all("\\s+", "_")) %>%
  select(-units) %>%
  spread(key = metric, value = value) %>%
  mutate(yield = yield / 10) # convert to kg / ha

Dat_fs %>%
  filter(crop == "Barley") %>%
  ggplot(aes(x = year, y = yield)) +
  geom_line()

crop_types <- Dat_fs %>%
  distinct(crop)

# manual translation
crop_types <- crop_types %>%
  select(fao_orig = crop) %>%
  mutate(trans = c(NA, NA, NA, NA, NA, NA, "barley", "beans-and-pulses", "beans-and-pulses", NA,
                   NA, "beans-and-pulses", NA, NA, NA, "tubers", NA, NA, NA, NA,
                   NA, NA, NA, NA, NA, NA, NA, NA, NA, NA,
                   NA, NA, NA, NA, "peanut", NA, NA, NA, NA, NA,
                   NA, "maize", NA, NA, "millet", "oats", NA, NA, NA, NA,
                   NA, NA, NA, NA, NA, NA, NA, NA, "potato", NA,
                   NA, NA, NA, "rice", "tubers", "rye", NA, NA, NA, NA,
                   "sorghum", NA, NA, "beans-and-pulses", NA, NA, NA, NA, NA, NA,
                   NA, NA, NA, NA, NA, "wheat", NA, NA, NA, "soybean",
                   NA, NA, NA, NA, NA))

Dat_fs <- Dat_fs %>%
  rename(fao_orig = crop) %>%
  left_join(crop_types, by = "fao_orig") %>%
  drop_na(trans) %>%
  select(-fao_orig, crop = trans, yield_tha = yield) %>%
  mutate(prod_t = area_harvested * yield_tha) %>%
  group_by(year, crop) %>%
  summarise(area_harvested = sum(area_harvested, na.rm = T),
            prod_t = sum(prod_t, na.rm  = T)) %>%
  ungroup() %>%
  mutate(yield_tha = prod_t / area_harvested)

Dat_fs %>%
  filter(crop == "barley") %>%
  ggplot(aes(x = year, y = yield_tha)) +
  geom_line()

write_rds(Dat_fs, "helper-data/morocco-crop-yields-faostat-1961-2018.rds")
