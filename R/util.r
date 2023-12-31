library(stringr)
library(readr)
library(rvest)
library(dplyr)
library(lubridate)
library(glue)
library(ClimateOperators)
library(here)

#' Extract and validate arg values using a regex pattern
extract_arg <- function(args, pattern) {
  args |> str_extract(pattern, group = 1) |> na.omit()
}

#' Writes the supplied date-time string out to record the last monthly update
set_last_monthly_update_dt <- function(dt) {
  dt |> writeLines(here("data", "last-monthly-update.txt"))
}

# scrape the current monthly update date-time from nasa psl
get_current_monthly_dt <- function() {
  "https://downloads.psl.noaa.gov/Datasets/noaa.oisst.v2.highres/" |>
    read_html() |>
    html_element("#indexlist") |>
    html_table() |>
    select(Name, `Last modified`) |>
    filter(Name == "sst.mon.mean.nc") |>
    pull(`Last modified`) |>
    ymd_hm()
}

#' Return the path of a mask file remapped to the grid of iven observations
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

  message(paste("Extracting", ocean, "basin, regions", regions))

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
