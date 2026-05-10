# =============================================================
# Predictive Analytics Project: DK1 Day-Ahead Price Forecasting
# Authors: David, Emanuele, Radu
# =============================================================

rm(list = ls())

library(fpp3)
library(here)   # robust file paths across machines
library(knitr)
library(readr)


# =============================================================
# 1. DATA LOADING AND CLEANING
# =============================================================

# Load the three raw CSVs from energidataservice.dk, aggregate
# the hourly and 15-minute observations to daily frequency,
# stitch the two price series across the 2025-10-01 schema
# migration, and join everything into one clean tsibble for use
# in 02_analysis.R.


# --- Old prices: hourly Elspot, through 2025-09-30 ---

prices_old_daily <- read_csv2(here("data/raw/elspotprices.csv")) %>%
  filter(PriceArea == "DK1") %>%
  rename(
    time_dk   = HourDK,
    price_eur = SpotPriceEUR
  ) %>%
  mutate(date = as_date(time_dk)) %>%
  group_by(date) %>%
  summarise(price_eur = mean(price_eur, na.rm = TRUE), .groups = "drop")

range(prices_old_daily$date)
head(prices_old_daily) %>% kable(digits = 2, align = "c")
tail(prices_old_daily) %>% kable(digits = 2, align = "c")


# --- New prices: 15-minute Day-Ahead, from 2025-10-01 ---

prices_new_daily <- read_csv2(here("data/raw/dayaheadprices.csv")) %>%
  filter(PriceArea == "DK1") %>%
  rename(
    time_dk   = TimeDK,
    price_eur = DayAheadPriceEUR
  ) %>%
  mutate(date = as_date(time_dk)) %>%
  group_by(date) %>%
  summarise(price_eur = mean(price_eur, na.rm = TRUE), .groups = "drop")

range(prices_new_daily$date)
head(prices_new_daily) %>% kable(digits = 2, align = "c")
tail(prices_new_daily) %>% kable(digits = 2, align = "c")


# --- Stitch the two price series into one continuous daily series ---

prices_daily <- bind_rows(prices_old_daily, prices_new_daily) %>%
  arrange(date) %>%
  distinct(date, .keep_all = TRUE)

nrow(prices_daily)
range(prices_daily$date)

prices_daily %>%
  filter(date >= as_date("2025-09-25") & date <= as_date("2025-10-05")) %>%
  kable(digits = 2, align = "c")


# --- Production and consumption: hourly, aggregated to daily totals ---

production_daily <- read_csv2(here("data/raw/production_consumption.csv")) %>%
  filter(PriceArea == "DK1") %>%
  rename(
    time_dk          = HourDK,
    wind_offshore_lt = OffshoreWindLt100MW_MWh,
    wind_offshore_ge = OffshoreWindGe100MW_MWh,
    wind_onshore_lt  = OnshoreWindLt50kW_MWh,
    wind_onshore_ge  = OnshoreWindGe50kW_MWh,
    consumption      = GrossConsumptionMWh
  ) %>%
  mutate(
    date = as_date(time_dk),
    wind_mwh = wind_offshore_lt + wind_offshore_ge + wind_onshore_lt + wind_onshore_ge
  ) %>%
  group_by(date) %>%
  summarise(
    wind_mwh    = sum(wind_mwh, na.rm = TRUE),
    consumption = sum(consumption, na.rm = TRUE),
    .groups = "drop"
  )

range(production_daily$date)
head(production_daily) %>% kable(digits = 1, align = "c")
summary(production_daily$wind_mwh)


# --- Join prices and production into the final analysis dataset ---

# Trim to 2015 onwards: the four wind generation columns are not reliably
# populated before then, so earlier years would represent a different
# DK1 generation mix.

dk1_daily <- prices_daily %>%
  inner_join(production_daily, by = "date") %>%
  filter(date >= as_date("2015-01-01")) %>%
  as_tsibble(index = date)

dk1_daily
range(dk1_daily$date)
sum(is.na(dk1_daily$price_eur))
sum(is.na(dk1_daily$wind_mwh))
has_gaps(dk1_daily)
scan_gaps(dk1_daily)

saveRDS(dk1_daily, here("data/clean/dk1_daily.rds"))
write_csv(as_tibble(dk1_daily), here("data/clean/dk1_daily.csv"))


# --- Sanity-check plots ---

dk1_daily %>%
  autoplot(price_eur) +
  labs(
    title    = "DK1 Day-Ahead Electricity Price",
    subtitle = "Daily mean, EUR/MWh",
    x = NULL, y = "EUR/MWh"
  )

dk1_daily %>%
  autoplot(wind_mwh) +
  labs(
    title    = "DK1 Wind Generation",
    subtitle = "Daily total, MWh",
    x = NULL, y = "MWh"
  )
