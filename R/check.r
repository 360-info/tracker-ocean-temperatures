#!/usr/bin/env Rscript

# Quick precuror script to check whether the monhtly observations have been updated (around the 15th of the month)

library(readr)
library(dplyr)
library(lubridate)
library(here)
source(here("R", "util.r"))

# {ClimateOperators} masks dplyr::select, so put it back
select <- dplyr::select

is_monthly_stale <- check_monthly_obs_stale()
is_daily_stale   <- check_daily_obs_stale()

stopifnot(
  "Error: check_monthly_obs_stale() returned a missing value. This could indicate a problem connecting to NOAA." =
    !is.na(is_monthly_stale),
  "Error: check_daily_obs_stale() returned a missing value. This could indicate a problem connecting to NOAA." =
    !is.na(is_daily_stale),
    )

# save whether obs are stale to env vars $*_IS_STALE for later steps
message("Are monthly obs stale? ", is_monthly_stale)
message("Are daily obs stale? ", is_monthly_stale)
write_to_gha_env("MONTHLY_IS_STALE", is_monthly_stale)
write_to_gha_env("DAILY_IS_STALE",   is_daily_stale)
