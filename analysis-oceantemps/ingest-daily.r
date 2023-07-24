#!/usr/bin/env Rscript

# arguments (all required):
# - --from=YYYY-MM-DD: first date from which to get observations
# - --to=YYYY-MM-DD: last date from which to get observations
# - --overwrite=[true|false]: if true, overwrite existing observations

library(tibble)
library(dplyr)
library(purrr)
library(collateral)
library(glue)
library(here)

message("Testing workflow. Args are:")
message(str(args))

# --- 1. process cmd line args ------------------------------------------------

# extract start date and end date (YYYY-MM-DD) + option to overwrite from args
args <- commandArgs(trailingOnly = TRUE)

# test arguments
args <- c(
  "--from=2022-10-03",
  "--to=2023-07-01",
  "--overwrite=false"
)

# extract arg values and validate
start_date <- args |> extract_arg("^--from=(\\d{4}\\-\\d{2}\\-\\d{2})")
end_date   <- args |> extract_arg("^--to=(\\d{4}\\-\\d{2}\\-\\d{2})")
overwrite  <- args |> extract_arg("^--overwrite=(true|false)")

stopifnot(
  "Error: give a single start date argument of the form --from=YYYY-MM-DD" =
    length(start_date == 1),
  "Error: give a single end date argument of the form --to=YYYY-MM-DD" =
    length(end_date == 1),
  "Error: specify whether to overwrite using --overwrite=[true|false]" =
    length(overwrite == 1))

# convert inputs
start_date <- ymd(start_date)
end_date <- ymd(end_date)
overwrite <- as.logical(overwrite)

# --- 2. load current data ----------------------------------------------------

here("data", "monthly") |>
  list.files(pattern = glob2rx("*.csv"), full.names = TRUE) |>
  map_dfr(read_csv, .id = "basin") ->
current_obs

# current_obs |>
#   mutate(basin = str_remove(basename(basin), ".csv")) 

# --- 3. determine which obs to download --------------------------------------

req_interval <- tibble(
  date = seq.Date(start_date, end_date, by = "day"))

# test interval instead of current obs
another_interval <- tibble(
  date =
    seq.Date(as.Date("2023-01-01"), as.Date("2023-12-01"), by = "day") |>
    as.Date(origin = "1970-01-01"))

# if we're not overwriting and there are current obs, take those current obs
# out of the requested range
if ((!overwrite) && nrow(current_obs) > 0) {
  req_interval |>
    filter(!(date %in% current_obs$date)) ->
  dl_interval
} else {
  dl_interval <- req_interval
}

# remote data is sorted by year, so extract unique year list
dl_interval |>
  mutate(year = year(date)) |>
  pull(year) |>
  unique() ->
years_to_dl

# --- 4. download the obs -----------------------------------------------------

# TODO - raw temperature

# daily raw: sst.day.mean.{years_to_dl}.nc

# monthly (updated july 15, 1.9 GB): sst.mon.mean.nc

# TODO - temp anomaly
# https://downloads.psl.noaa.gov/Datasets/noaa.oisst.v2.highres/icec.day.mean.1981.nc

tibble(
  year = years_to_dl) |>
  mutate(
    remote_url = glue(
      "https://downloads.psl.noaa.gov/",
      "Datasets/noaa.oisst.v2.highres/",
      "sst.day.anom.{years_to_dl}.nc"),
    dest_file = tempfile(
      pattern = paste0("anomaly-", year, "-"),
      fileext = ".nc")) |>
  map2_safely(remote_url, dest_file, download.file) ->
downloads

# TODO - check for unsuccessful downloads

# TODO - process and save the downloads

message("Done!")