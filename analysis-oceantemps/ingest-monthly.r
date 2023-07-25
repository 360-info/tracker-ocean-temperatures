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

# regrid to 0.25x0.25 to match obs

mask_path <- here("data", "RECCAP2_region_masks_all_v20221025.nc")
regridded_mask_path <- tempfile(pattern = "masks-", fileext = ".nc")
cdo(csl("remapnn", monthly_path), mask_path, regridded_mask_path)

# combine the masks with the obs
# unified_path <- tempfile(pattern = "unified-", fileext = ".nc")
# cdo(ssl("merge", monthly_path, regridded_mask_path, unified_path))

# now mask obs to each basin. let's do north atlantic (zones 1, 2, 3) for ex
# https://code.mpimet.mpg.de/boards/53/topics/10933

# first join the regions we want into a single, binary mask
pacific_all_mask_path <- tempfile(pattern = "pacific_all-", fileext = ".nc")
cdo(
  csl("-expr", "'sst = ((pacific>=1.0)) ? 1.0 : pacific/0'"),
  regridded_mask_path,
  pacific_all_mask_path)

# and then apply the mask to the sst obs
# cdo -mul mask_ocean.nc infile_r360x180.nc infile_r360x180_mask_ocean.nc
pacific_monthly_path <- tempfile(pattern = "pacific_all-sst-", fileext = ".nc")
cdo(
  "-mul",
  pacific_all_mask_path,
  monthly_path,
  pacific_monthly_path)

# finally, calculate and output the time series
pacific_ts_path <- tempfile(pattern = "pacific_all-ts-", fileext = ".nc")
cdo("fldmean", pacific_monthly_path, pacific_ts_path)

series <- cdo(csl("outputtab", "date", "value"), pacific_ts_path)

tibble(data = stringr::str_trim(series)) |>
  slice(-1) |>
  tidyr::separate(data, into = c("date", "value"), sep = "\\s+", convert = TRUE)



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