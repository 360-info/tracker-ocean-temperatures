#!/usr/bin/env Rscript

# Quick precuror script to check whether the monhtly observations have been updated (around the 15th of the month)

library(readr)
library(dplyr)
library(lubridate)
library(here)
source(here("R", "util.r"))

# {ClimateOperators} masks dplyr::select, so put it back
select <- dplyr::select

is_daily_stale <- check_daily_obs_stale()

stopifnot(
  "Error: check_daily_obs_stale() returned a missing value. This could indicate a problem connecting to NOAA." =
    !is.na(is_daily_stale))

# save whether obs are stale to env vars $*_IS_STALE for later steps
message("Are daily obs stale? ", is_daily_stale)
write_to_gha_env("DAILY_IS_STALE",   is_daily_stale)
