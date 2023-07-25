#!/usr/bin/env Rscript

# arguments (all required):
# - --from=YYYY-MM-DD: first date from which to get observations
# - --to=YYYY-MM-DD: last date from which to get observations
# - --overwrite=[true|false]: if true, overwrite existing observations

library(tibble)
library(dplyr)
library(purrr)
library(ClimateOperators)
library(glue)
library(here)

# uncomment and edit this line if you need to tell r where to find cdo
Sys.setenv(PATH = paste(Sys.getenv("PATH"), "/opt/homebrew/bin", sep = ":"))

source(here("analysis-oceantemps", "util.r"))

# extract start date and end date (YYYY-MM-DD) + option to overwrite from args
args <- commandArgs(trailingOnly = TRUE)

# test arguments
args <- c("--overwrite=false")

message("Testing workflow. Args are:")
message(str(args))

# --- 1. process cmd line args ------------------------------------------------


overwrite  <- args |> extract_arg("^--overwrite=(true|false)")

stopifnot(
  "Error: specify whether to overwrite using --overwrite=[true|false]" =
    length(overwrite == 1))

# convert inputs
overwrite <- as.logical(overwrite)

# --- 2. download new data (timeout:15 mins) ----------------------------------

monthly_url <- paste0(
  "https://downloads.psl.noaa.gov/",
  "Datasets/noaa.oisst.v2.highres/",
  "sst.mon.mean.nc")
monthly_path <- tempfile(pattern = "monthly-", fileext = ".nc")
options(timeout = 900)
download.file(monthly_url, monthly_path)

# check for unsuccessful downloads
stopifnot(
  "Error: problem downloading monthly observations from NASA PSL" =
    file.exists(monthly_path)
)

# --- 3. open, crop to ocean basins and calc series ---------------------------

# regrid to 0.25x0.25 to match obs (we can reuse this mask file)
mask_path <- get_regridded_mask_path(monthly_path)



# extract_basin_timeseries <- function(ocean, regions, sst_path, mask_path)

# --- 4. if not overwriting, load current data for comparison -----------------

here("data", "monthly") |>
  list.files(pattern = glob2rx("*.csv"), full.names = TRUE) |>
  map_dfr(read_csv, .id = "basin") ->
current_obs

# current_obs |>
#   mutate(basin = str_remove(basename(basin), ".csv")) 

# --- 3. determine which obs to download --------------------------------------

# req_interval <- tibble(
#   date = seq.Date(start_date, end_date, by = "day"))

# # test interval instead of current obs
# another_interval <- tibble(
#   date =
#     seq.Date(as.Date("2023-01-01"), as.Date("2023-12-01"), by = "day") |>
#     as.Date(origin = "1970-01-01"))

# # if we're not overwriting and there are current obs, take those current obs
# # out of the requested range
# if ((!overwrite) && nrow(current_obs) > 0) {
#   req_interval |>
#     filter(!(date %in% current_obs$date)) ->
#   dl_interval
# } else {
#   dl_interval <- req_interval
# }

# remote data is sorted by year, so extract unique year list

# dl_interval |>
#   mutate(year = year(date)) |>
#   pull(year) |>
#   unique() ->
# years_to_dl

# TODO - process and save the downloads

# --- Z. record the update time -----------------------------------------------

get_current_monthly_dt() |> set_last_monthly_update_dt()

message("Done!")