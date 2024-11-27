library(stringr)
library(readr)
library(rvest)
library(dplyr)
library(lubridate)
library(glue)
library(ClimateOperators)
library(here)

oisst_root <- "https://downloads.psl.noaa.gov/Datasets/noaa.oisst.v2.highres"
daily_file_regex <- "sst\\.day\\.mean\\.\\d{4}\\.nc"
monthly_file <- "sst.mon.mean.nc"

# write_to_gha_env: write a key-value pair out to the github actions environment
# variables
write_to_gha_env <- function(key, value) {
  system2("echo", c(
    paste0(key, "=", value),
    ">>",
    "$GITHUB_ENV"))
}

#' Extract and validate arg values using a regex pattern
extract_arg <- function(args, pattern) {
  args |> str_extract(pattern, group = 1) |> na.omit()
}

#' Writes the supplied date-time string out to record the last monthly update
set_last_monthly_update_dt <- function(dt) {
  dt |> writeLines(here("data", "last-monthly-update.txt"))
}

#' Writes the supplied date-time string out to record the last daily update
set_last_daily_update_dt <- function(dt) {
  dt |> writeLines(here("data", "last-daily-update.txt"))
}

# scrape the current monthly update date-time from nasa psl
get_current_monthly_dt <- function() {
  oisst_root |>
    read_html() |>
    html_element("#indexlist") |>
    html_table() |>
    select(Name, `Last modified`) |>
    filter(Name == monthly_file) |>
    pull(`Last modified`) |>
    ymd_hm()
}

# scrape the current monthly update date-time from nasa psl
get_current_daily_files <- function() {
  oisst_root |>
    read_html() |>
    html_element("#indexlist") |>
    html_table() |>
    select(Name, `Last modified`) |>
    filter(str_detect(Name, regex(daily_file_regex)))
}

# scrape the current monthly update date-time from nasa psl
get_current_daily_dt <- function() {
  get_current_daily_files() |>
    pull(`Last modified`) |>
    ymd_hm() |>
    max(na.rm = TRUE)
}

#' Determine whether new monthly observations are available
#' 
#' @return A boolean. True if new obs are available for download, or if obs have
#' never been downloaded
check_monthly_obs_stale <- function() {
  last_update_path <- here("data", "last-monthly-update.txt")
  if(!file.exists(last_update_path)) {
    return(TRUE)
  }

  return(
    get_current_monthly_dt() > (last_update_path |> readLines() |> ymd_hms())
  )
}

#' Determine whether new monthly observations are available
#' 
#' @return A boolean. True if new obs are available for download, or if obs have
#' never been downloaded
check_daily_obs_stale <- function() {

  # definitely stale if we don't have any update record
  last_update_path <- here("data", "last-daily-update.csv")
  if(!file.exists(last_update_path)) {
    message("No previous daily update time found")
    return(TRUE)
  }

  # check the date of the last update and what the latest year of it was
  last_update      <- read_csv(last_update_path)
  last_update_year <- last_update$year
  last_update_date <- last_update$date

  # compare with the current data available remotely
  remote_latest      <- get_current_daily_dt()
  remote_latest_year <- remote_latest$year
  remote_latest_date <- remote_latest$date

  return(
    (remote_latest_year > last_update_year) ||
    (remote_latest_date > last_update_date))
}

#' Return the path of a mask file remapped to the grid of given observations
#' 
#' Our masks are on a 1° grid, but our obs are 0.25°x0.25°. This function
#' regrids the mask file and returns the (temporary) path to the new file.
#'
#' @param sst_path The path to an nc file with observed sea surface temps
get_regridded_mask_path <- function(sst_path) {
  source_mask_path <- here("data", "RECCAP2_region_masks_all_v20221025.nc")
  hollowed_mask_path <- tempfile(pattern = "hollowed-masks-", fileext = ".nc")
  regridded_mask_path <- tempfile(pattern = "regrid-masks-", fileext = ".nc")

  # regrid to the 0.25°x0.25° grid, and make 0 areas NaN
  # (it won't chain for some reason)
  cdo(csl("setctomiss", "0"), source_mask_path, hollowed_mask_path)
  cdo(csl("remapnn", sst_path), hollowed_mask_path, regridded_mask_path)

  unlink(hollowed_mask_path)
  return(regridded_mask_path)
}

#' Return the path of a mask for a single region defined by a lon-lat box.
#' 
#' Regions used here are largely based on ENSO and IOD monitoring regions:
#' http://www.bom.gov.au/climate/enso/indices.shtml
#' 
#' @param lon_min Longitude to start box from
#' @param lon_max Longitude to end box at
#' @param lat_min Latitude to start box from
#' @param lat_max Latitude to end box at
#' @param mask_path The path to the mask file
#' @return Path to the created NetCDF
make_lonlat_box_mask <- function(lon_min, lon_max, lat_min, lat_max,
  mask_path) {

  # rename the seamask to sst, set it to NaN globally, then set the box to 1.0
  boxmask_path <- tempfile(pattern = "boxmask-", fileext = ".nc")
  cdo(
    "-L",
    csl("setclonlatbox", "1.0", lon_min, lon_max, lat_min, lat_max),
    csl("-expr", "'sst = sst / 0'"),
    csl("-chname", "seamask", "sst"),
    csl("-select", "name=seamask"),
    mask_path,
    boxmask_path)
  return(boxmask_path)
}

#' Returns a time series of field-averaged SSTs for the specified lon-lat box
#' 
#' @param lon_min Longitude to start box from
#' @param lon_max Longitude to end box at
#' @param lat_min Latitude to start box from
#' @param lat_max Latitude to end box at
#' @param sst_path The path to the downloaded sea surface temperatures (.nc)
#' @param mask_path The path to the global mask file (.nc)
#' @return A tibble with two columns: `date` and `temperature`
extract_box_timeseries <- function(lon_min, lon_max, lat_min, lat_max,
  sst_path, mask_path) {

  message(paste("Extracting box: longitude", lon_min, "to", lon_max,
    "latitude", lat_min, "to", lat_max))

  # create a mask just for the lon-lat box (var: "seamask")
  box_mask_path <- make_lonlat_box_mask(lon_min, lon_max, lat_min, lat_max,
    mask_path)

  # apply the mask to the sst obs
  region_monthly_path <- tempfile(pattern = "maskedssts-", fileext = ".nc")
  cdo("-mul", box_mask_path, sst_path, region_monthly_path)

  # finally, calculate and output the time series
  box_ts_path <- tempfile(pattern = "timeseries-", fileext = ".nc")
  cdo("fldmean", region_monthly_path, box_ts_path)
  series <- cdo(csl("outputtab", "date", "value"), box_ts_path)

  # cleanup temp files (we're doing this a few times, so best to save on space)
  
  unlink(region_monthly_path)
  unlink(box_ts_path)

  # tidy the time series up and return
  series |>
    str_trim() |>
    tibble(data = _) |>
    slice(-1) |>
    separate(data, into = c("date", "temperature"), sep = "\\s+",
      convert = TRUE) |>
    mutate(
      date = as.Date(date),
      temperature = round(as.numeric(temperature), 2))
}

#' Returns a time series of field-averaged SSTs for the specified ocean region
#' 
#' Masking procedure based on https://code.mpimet.mpg.de/boards/53/topics/10933
#' 
#' @param ocean One of the oceans in the masks file. Includes arctic, atlantic,
#'   indian, pacific, southern.
#' @param regions A string specifying one or more regions within the ocean
#'   mask, separated by commas. Eg. "1,2,3"
#' @param sst_path The path to the downloaded sea surface temperatures (.nc)
#' @param mask_path The path to the mask file (.nc)
#' @return A tibble with two columns: `date` and `temperature`
extract_basin_timeseries <- function(ocean, regions, sst_path, mask_path) {

  message(paste("Extracting", ocean, "basin: regions", regions))

  region <- str_split(regions, ",\\s?") |> unlist()
  region_expression <- glue("({ocean}=={region})") |> paste(collapse = " || ")

  # join the mask regions we want into a single, binary mask (1 or NaN)
  region_mask_path <- tempfile(pattern = "regionmask-", fileext = ".nc")
  cdo(
    csl("-expr", glue("'sst = ({region_expression}) ? 1.0 : {ocean}/0'")),
    mask_path,
    region_mask_path)

  # apply the mask to the sst obs
  region_monthly_path <- tempfile(pattern = "maskedssts-", fileext = ".nc")
  cdo("-mul", region_mask_path, sst_path, region_monthly_path)

  # finally, calculate and output the time series
  region_ts_path <- tempfile(pattern = "timeseries-", fileext = ".nc")
  cdo("fldmean", region_monthly_path, region_ts_path)
  series <- cdo(csl("outputtab", "date", "value"), region_ts_path)

  # cleanup temp files (we're doing this a few times, so best to save on space)
  unlink(region_mask_path)
  unlink(region_monthly_path)
  unlink(region_ts_path)

  # tidy the time series up and return
  series |>
    str_trim() |>
    tibble(data = _) |>
    slice(-1) |>
    separate(data, into = c("date", "temperature"), sep = "\\s+") |>
    mutate(
      date = as.Date(date),
      temperature = round(as.numeric(temperature), 2))
}

#' Download and process a year's worth of saily SSTs from NOAA.
#' 
#' @param missing_year The year to download dailies for
#' @return A list with two elements:
#' - basins: a data frame of observations for ocean basin regions
#' - boxes: a data frame of observations for box-based regions
process_year_of_dailies <- function(missing_year) {

  # 1. download year
  options(timeout = 10000)
  daily_url <- glue("{oisst_root}/sst.day.mean.{missing_year}.nc")
  daily_path <- tempfile(pattern = "daily-", fileext = ".nc")
  download.file(daily_url, daily_path)
  
  stopifnot("Error: problem downloading daily obs from NASA PSL" =
    file.exists(daily_path))

  # 2. regrid region mask to match obs (we can reuse this mask file)
  mask_path <- get_regridded_mask_path(daily_path)

  # 3a. extract region series from regions...
  here("data", "basins.csv") |>
    read_csv(col_types = "ccc") |>
    mutate(
      series = map2(
        mask_ocean, mask_regions, extract_basin_timeseries,
        sst_path = daily_path, mask_path = mask_path),
      name_safe = make_clean_names(name)) |>
    select(name_safe, series) ->
  basin_series

  # 3b. ... and boxes
  here("data", "boxes.csv") |>
    read_csv(col_types = "ccccc") |>
    mutate(
      series = pmap(
        list(lon_min, lon_max, lat_min, lat_max),
        extract_box_timeseries,
        sst_path = daily_path, mask_path = mask_path),
      name_safe = make_clean_names(name)) |>
    select(name_safe, series) ->
  box_series

  message("BASINS:")
  print(basin_series)
  message("BOXES:")
  print(box_series)

  unlink(daily_path)

  return(list(basins = basin_series, boxes = box_series))
}
