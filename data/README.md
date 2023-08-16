
# `/data`

This dataset updates monthly based on upstream updates from [NOAA PSL's OI SST v2](https://psl.noaa.gov/data/gridded/data.noaa.oisst.v2.highres.html) dataset ([Huang, B et al. 2021](https://doi.org/10.1175/JCLI-D-20-0166.1)).

## Processed data

The processed observations are in two places:

- `monthly-all.csv` contains observations for all regions
- `monthly/[region].csv` contains observations for a single region

If you want to create a chart that updates automatically based on one of these files (eg. in Flourish, which [supports live data sources](https://help.flourish.studio/article/163-how-to-connect-to-live-data-sources)), navigate to one of these files in GitHub, click on the "Raw" button and then copy the URL from the address bar (do not right-click the button and copy the link—it redirects).

For example, the raw URL for `monthly-all.csv` is:

```
https://raw.githubusercontent.com/360-info/tracker-ocean-temperatures/main/data/monthly-all.csv
```

## Mask file

`RECCAP2_region_masks_all_v20221025.nc` contains masks for various ocean basins. In these files, each variable is an ocean. The variable is 0 for masked-out areas (eg. land or other oceans) or an integer greater than 0 for a region within the ocean. Each ocean is broken up into sub-regions (1, 2, 3, etc.).

Masks are on a 1° by 1° grid, which is regridded to 0.25° by 0.25° to match the observations.

Masks are from [Fay, A. R., & McKinley, G. A. (2014)](https://doi.org/10.5194/essd-6-273-2014) via [the RECCAP2 project](https://github.com/RECCAP2-ocean/R2-shared-resources/) and are available [under Creative Commons Attribution 3.0](https://doi.pangaea.de/10.1594/PANGAEA.828650).

## Other files

`basins.csv` and `boxes.csv` defines the regions processed by our analysis script (so changing them will add or change the regions output).

- `basins.csv` defines regions using the variables and region values in the RECCAP2 masks file (`RECCAP2_region_masks_all_v20221025.nc`)
- `boxes.csv` defines regions using latitude-longitude boxes

`last-monthly-update.text` is a datestamp of the time of the last update on NOAA's end. We save this at the end of an update to avoid unnecessary updates when no new data is available.