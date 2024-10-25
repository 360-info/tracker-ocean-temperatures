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

# --- 1a. which days do we need, considering current obs? ---------------------

daily_folder <- here("data", "daily")
daily_files_current <- daily_folder |> list.files(pattern = glob2rx("*.csv"))

# get the dates for which we have any missing observations
# (either because we don't have files for all the marked regions, or because
# some days are missing)
basins <- here("data", "basins.csv") |> read_csv()
boxes <- here("data", "boxes.csv") |> read_csv()

c(basins$name, boxes$name) |>
  make_clean_names() |>
  paste0(".csv") ->
required_regions

required_regions |>
  setdiff(daily_files_current) ->
missing_regions

# if there are missing regions, download all years from NOAA
if (length(missing_regions) != 0) {
  message(
    "Regions missing - getting all available data from NOAA")
  get_current_daily_files() |>
    pull(Name) |>
    str_extract(regex("\\d{4}")) |>
    unique() |>
    as.numeric() ->
  missing_years
} else {
  # if there are NO missing regions, work it out based on the days in the
  # data for which at least one region is missing data
  message("No regions missing - getting only NOAA data for missing days")
  daily_files_current |>
    tibble(path = _, data = map(path, ~ read_csv(file.path(daily_folder, .x)))) |>
    unnest(data) |>
    filter(!is.na(date)) |>
    pivot_wider(names_from = date, values_from = temperature) |>
    summarise(across(where(is.numeric), ~ anyNA(.x))) |>
    pivot_longer(everything(), names_to = "date", values_to = "any_missing") |>
    filter(any_missing) |>
    pull(date) |>
    as.Date() |> 
    year() |>
    unique() ->
  missing_years
}

# --- 3. download, open and crop: repeat for each missing year ----------------

tibble(year = missing_years) |>
  mutate(data = map(year, process_year_of_dailies)) |>
  unnest_wider(data) ->
all_processed

basin_series <-

all_processed |>
  pull(basins) |>
  bind_rows() |>
  unnest_longer(series) |>
  unpack(series) |>
  nest(basins = -name_safe) ->
basin_series

all_processed |>
  pull(boxes) |>
  bind_rows() |>
  unnest_longer(series) |>
  unpack(series) |>
  nest(boxes = -name_safe) ->
box_series

# --- 4. if not overwriting, load current data for comparison -----------------

# if we're not overwriting, we need to load current obs and only fill in missing
# obs
here("data", "daily") |>
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
dir.create(here("data", "daily"), showWarnings = FALSE, recursive = TRUE)
walk2(
  basin_outputs$series, basin_outputs$name_safe,
  ~ write_csv(.x, here("data", "daily", paste0(.y, ".csv"))))
walk2(
  box_outputs$series, box_outputs$name_safe,
  ~ write_csv(.x, here("data", "daily", paste0(.y, ".csv"))))

# now write all basins and boxes out as single csv
basin_outputs |>
  unnest_longer(series) |>
  unpack(series) ->
basin_outputs_long
box_outputs |>
  unnest_longer(series) |>
  unpack(series) ->
box_outputs_long

# bind_rows(basin_outputs_long, box_outputs_long) |>
#   rename(region = name_safe) |>
#   arrange(region, date) |>
#   write_csv(here("data", "daily-all.csv"))

# --- Z. record the update time -----------------------------------------------

new_update_time <- get_current_daily_dt()
set_last_daily_update_dt(as.character(new_update_time))

system2("echo", c(
  "DAILY_UPDATED=true",
  ">>",
  "$GITHUB_ENV"))
system2("echo", c(
  paste0("DAILY_UPDATE_TIME=", new_update_time),
  ">>",
  "$GITHUB_ENV"))
system2("echo", c(
  paste0("DAILY_RUN_END=", Sys.time()),
  ">>",
  "$GITHUB_ENV"))
message("Successfully updated!")
