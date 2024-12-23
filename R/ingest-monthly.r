#!/usr/bin/env Rscript

# arguments (all required):
# - --overwrite=[true|false]: if true, overwrite existing observations

library(readr)
library(dplyr)
library(tibble)
library(tidyr)
library(janitor)
library(glue)
library(purrr)
library(here)
source(here("R", "util.r"))

# set cdo path, as {ClimateOperators} usually can't find it on PATH properly
# (default to homebrrew's version if we're not on github actions)
cdo_path = Sys.getenv("CDO_PATH", "/opt/homebrew/bin")
message("CDO location to be used is ", cdo_path)
Sys.setenv(PATH = paste(Sys.getenv("PATH"), cdo_path, sep = ":"))

# {ClimateOperators} masks dplyr::select, so put it back
select <- dplyr::select

# extract start date and end date (YYYY-MM-DD) + option to overwrite from args
args <- commandArgs(trailingOnly = TRUE)

# --- 1. process cmd line args ------------------------------------------------


overwrite <- args |> extract_arg("^--overwrite=(true|false)")

stopifnot(
  "Error: specify whether to overwrite using --overwrite=[true|false]" =
    length(overwrite) == 1)

# convert inputs
overwrite <- as.logical(toupper(overwrite))

# --- 2. download new data (timeout:15 mins) ----------------------------------

monthly_path <- tempfile(pattern = "monthly-", fileext = ".nc")
options(timeout = 10000)
download.file(paste(oisst_root, monthly_file, sep = "/"), monthly_path)

# check for unsuccessful downloads
stopifnot(
  "Error: problem downloading monthly observations from NASA PSL" =
    file.exists(monthly_path)
)

# --- 3. open, crop to ocean basins and calc series ---------------------------

# regrid to 0.25x0.25 to match obs (we can reuse this mask file)
mask_path <- get_regridded_mask_path(monthly_path)

# load list of regions and extract series from each region
here("data", "basins.csv") |>
  read_csv(col_types = "ccc") |>
  mutate(
    series = map2(
      mask_ocean, mask_regions, extract_basin_timeseries,
      sst_path = monthly_path, mask_path = mask_path),
    name_safe = make_clean_names(name)) |>
  select(name_safe, series) ->
basin_series

# now load the boxes and extract series from those
here("data", "boxes.csv") |>
  read_csv(col_types = "ccccc") |>
  mutate(
    series = pmap(
      list(lon_min, lon_max, lat_min, lat_max),
      extract_box_timeseries,
      sst_path = monthly_path, mask_path = mask_path),
    name_safe = make_clean_names(name)) |>
  select(name_safe, series) ->
box_series

# --- 4. if not overwriting, load current data for comparison -----------------

# if we're not overwriting, we need to load current obs and only fill in missing
# obs
here("data", "monthly") |>
  list.files(pattern = glob2rx("*.csv"), full.names = TRUE) ->
current_obs_paths

if (length(current_obs_paths) == 0) {
  # no current obs: just write them straight out
  message("No current obs found")
  basin_outputs <- basin_series
  box_outputs <- box_series
} else {
  message("Loading current obs")
  # if there are current obs, load them
  current_obs_paths |>
    tibble() |>
    set_names("path") |>
    mutate(
      name_safe = str_remove(basename(path), ".csv"),
      series = map(path, read_csv, col_types = "Dd")) |>
    select(-path) |>
    unnest_longer(series) |>
    unpack(series) ->
  current_obs

  # merge new obs with current ones
  message("Merging current obs")
  
  basin_series |>
    unnest_longer(series) |>
    unpack(series) |>
    left_join(current_obs, c("name_safe", "date"),
      suffix = c("_new", "_current")) ->
  basin_joined

  box_series |>
    unnest_longer(series) |>
    unpack(series) |>
    left_join(current_obs, c("name_safe", "date"),
      suffix = c("_new", "_current")) ->
  box_joined

  if (overwrite) {
    # if we're overwriting, preference new obs over current ones
    message("Overwrite enabled; preferencing new obs over current ones")

    basin_joined |>
      mutate(temperature = coalesce(temperature_new, temperature_current)) |>
      select(name_safe, date, temperature) |>
      nest(series = c(date, temperature)) ->
    basin_outputs
    
    box_joined |>
      mutate(temperature = coalesce(temperature_new, temperature_current)) |>
      select(name_safe, date, temperature) |>
      nest(series = c(date, temperature)) ->
    box_outputs
  } else {
    # if we're not overwriting, preference current obs over new ones
    message("Overwrite disabled; preferencing current obs over new ones")
    basin_joined |>
      mutate(temperature = coalesce(temperature_current, temperature_new)) |>
      select(name_safe, date, temperature) |>
      nest(series = c(date, temperature)) ->
    basin_outputs
    
    box_joined |>
      mutate(temperature = coalesce(temperature_current, temperature_new)) |>
      select(name_safe, date, temperature) |>
      nest(series = c(date, temperature)) ->
    box_outputs
  } 
}

# write basins and boxes out
dir.create(here("data", "monthly"), showWarnings = FALSE, recursive = TRUE)
walk2(
  basin_outputs$series, basin_outputs$name_safe,
  ~ write_csv(.x, here("data", "monthly", paste0(.y, ".csv"))))
walk2(
  box_outputs$series, box_outputs$name_safe,
  ~ write_csv(.x, here("data", "monthly", paste0(.y, ".csv"))))

# now write all basins and boxes out as single csv
basin_outputs |>
  unnest_longer(series) |>
  unpack(series) ->
basin_outputs_long
box_outputs |>
  unnest_longer(series) |>
  unpack(series) ->
box_outputs_long

bind_rows(basin_outputs_long, box_outputs_long) |>
  rename(region = name_safe) |>
  arrange(region, date) |>
  write_csv(here("data", "monthly-all.csv"))

# --- Z. record the update time -----------------------------------------------

new_update_time <- get_current_monthly_dt()
set_last_monthly_update_dt(as.character(new_update_time))

system2("echo", c(
  "MONTHLY_UPDATED=true",
  ">>",
  "$GITHUB_ENV"))
system2("echo", c(
  paste0("MONTHLY_UPDATE_TIME=", new_update_time),
  ">>",
  "$GITHUB_ENV"))
system2("echo", c(
  paste0("MONTHLY_RUN_END=", Sys.time()),
  ">>",
  "$GITHUB_ENV"))
message("Successfully updated!")
