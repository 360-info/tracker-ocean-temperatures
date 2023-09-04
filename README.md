# [Ocean temperature tracker]

Updates with ocean temperatures from around the world. Daily and monthly updates are available. 

## 📦 [Get the data](data) • 📊 [Get the chart](https://aug2023.360info-tracker-ocean-temperatures.pages.dev/vis-monthly-pub)

## ♻️ Use + Remix rights

![[Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0)](https://mirrors.creativecommons.org/presskit/buttons/80x15/png/by.png)

These charts, as well as the analyses that underpin them, are available under a Creative Commons Attribution 4.0 licence. This includes commercial reuse and derivates.

<!-- Do any of the data sources fall under a different licence? If so, describe the licence and which parts of the data fall under it here! if most of it does, change the above and replace LICENCE.md too -->

Data in these charts comes from:

* Ocean temperatures are from [NOAA PSL's OI SST v2](https://psl.noaa.gov/data/gridded/data.noaa.oisst.v2.highres.html):
  - [Huang, B et al. 2021](https://doi.org/10.1175/JCLI-D-20-0166.1): Improvements of the Daily Optimum Interpolation Sea Surface Temperature (DOISST) Version 2.1, Journal of Climate, 34, 2923-2939.
* Masks are from [Fay, A. R., & McKinley, G. A. (2014)](https://doi.org/10.5194/essd-6-273-2014) via [the RECCAP2 project](https://github.com/RECCAP2-ocean/R2-shared-resources/)

**Please attribute 360info and the data sources when you use and remix these visualisations.**

## Getting the data

The daily data are updated each day from NOAA, while the monthly data are updated each month around the middle of the month. The data can be found in the [`/data`](data) folder.

## 💻 Reproduce the analysis

The analysis scripts in this project are designed to run in the cloud using GitHub Actions. The GitHub Actions workflow files are in the [`.github/workflows`](.github/workflows) folder; the R scripts themselves are in [`analysis-oceantemps`](analysis-oceantemps).

The chart comes in two flavours:

* A publication-ready one with fewer options but some extra features for editorial use is in `vis-monthly-pub`; and
* An expanded version (more regions, toggle between between observed temperatures and anomalies) is in `vis-monthly`.

If you have Quarto installed, you can render the charts using:

```bash
quarto render
quarto preview
```

## ❓ Help

If you find any problems with our analysis or charts, please feel free to [create an issue](https://github.com/360-info/tracker-ocean-temperatures/issues/new)!
