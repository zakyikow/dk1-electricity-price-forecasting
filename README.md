<div align="center">

# ⚡ DK1 Electricity Price Forecasting

### Day-Ahead Spot Price Models for Denmark's Western Bidding Zone

[![Built with](https://img.shields.io/badge/Built_with-R_%7C_RStudio-2469bd?logo=r&logoColor=white)]()
[![Methods](https://img.shields.io/badge/Methods-ARIMA_%7C_ETS_%7C_Dynamic_Regression-674fff)]()
[![Data](https://img.shields.io/badge/Data-energidataservice.dk-00525f)](https://www.energidataservice.dk/)

*Time series forecasting of daily DK1 day-ahead electricity prices, comparing ARIMA, ETS, and dynamic regression across the 2022 European energy crisis on a 30-day horizon.*

</div>

#

<br>

## Overview

This project forecasts daily day-ahead electricity spot prices in DK1, the Danish bidding zone covering Jutland and Funen. The goal is to identify the model class that best forecasts DK1 prices on a 30-day horizon and to quantify the role of wind generation as a structural driver of price.

The pipeline pulls 4,127 daily observations spanning 2015 to 2026 from energidataservice.dk, handles the Elspot to Day-Ahead schema migration at 2025-10-01, detects a structural break tied to the 2022 European energy crisis, and runs the full forecasting workflow: EDA, stationarity testing, structural-break detection, sample restriction, model identification, estimation, Box-Cox sensitivity, forecast evaluation, and rolling-origin cross-validation.

```
4,127 daily observations from 2015-01-01 to 2026-04-19
Restricted sample post-break: 1,514 obs from 2022-02-26 onward
Train: 2022-02-26 to 2025-12-31 (1,405 obs)
Test:  2026-01-01 to 2026-04-19 (109 obs)
```

<br>

## Results

**Headline model: ARIMA(3,1,1)(2,0,0)[7] on raw post-2022 data**, selected on residual diagnostics and prediction-interval calibration rather than point accuracy alone.

### Single-split accuracy (109-day test window)

| Model | Specification | RMSE | MAE | MASE |
|-------|---------------|-----:|----:|-----:|
| arma_auto | ARIMA(3,1,1)(2,0,0)[7] | **32.73** | **26.53** | **0.59** |
| ets | ETS(A,A,A) | 34.79 | 28.84 | 0.64 |
| dyn_reg | LM + ARIMA(1,1,3)(2,0,0)[7], wind | 34.99 | 28.58 | 0.63 |
| arma_manual | ARIMA(0,1,1)(0,1,1)[7] | 37.70 | 32.07 | 0.71 |

### Rolling-origin CV (26 windows, h = 30)

| Model | RMSE | MAE | MASE |
|-------|-----:|----:|-----:|
| ets | **50.85** | 38.87 | 0.88 |
| arma_manual | 50.93 | **36.50** | **0.83** |
| arma_auto | 55.58 | 36.90 | 0.83 |

### Residual diagnostics (Ljung-Box, lag = 20)

| Model | lb_stat | dof | p |
|-------|--------:|----:|--:|
| arma_auto | 27.4 | 6 | 0.017 |
| dyn_reg | 38.6 | 6 | 0.0004 |
| arma_manual | 134 | 2 | ≈ 0 |
| ets | 169 | 3 | ≈ 0 |

### Key findings

* **Structural break aligned with geopolitics.** The QLR / supF test on the first-differenced series locates a break at 2022-02-26 (supF = 22.5, p = 0.00048), exactly two days after Russia's invasion of Ukraine.
* **Manual airline ARIMA was falsified by auto-ARIMA.** ACF/PACF of the doubly-differenced series shows a textbook airline signature, motivating manual ARIMA(0,1,1)(0,1,1)[7]. Auto-ARIMA instead chose ARIMA(3,1,1)(2,0,0)[7] with D = 0. The manual model's near-zero ma1 coefficient (-0.047) is the smoking gun for over-differencing.
* **Box-Cox rejected on evidence.** λ ≈ -0.04 on the shifted series amplifies the single most-negative-price day into a >4σ outlier. Ljung-Box on transformed residuals is uniformly worse than raw (arma_auto: 27.4 → 290, arma_manual: 134 → 257, ets: 169 → 244).
* **Prediction interval calibration is the decisive selection criterion.** Auto-ARIMA's 30-day-plus PIs stay bounded at roughly ±200 EUR/MWh around the central forecast, whereas the manual airline and ETS PIs explode to ±1,000 EUR/MWh by the end of the same window. On rolling-origin CV the three univariate models are tied on MASE, but auto-ARIMA's intervals are the only ones that remain operationally usable.
* **Wind validates merit-order theory but does not enhance forecasts.** The dynamic-regression wind coefficient is -9 × 10⁻⁴ EUR/MWh per MWh (≈ -0.9 EUR/MWh per GWh), right-signed and significant. For a typical median wind day on the post-break sample (~35 GWh) that translates to about -31 EUR/MWh on price; for a high-wind day (Q3 ≈ 58 GWh), about -52 EUR/MWh. The economic effect is real; the forecasting gain over univariate auto-ARIMA is not.

<br>

## Methodology

1. **Stationarity diagnosis.** ADF and KPSS on the full-sample price series give a textbook disagreement: ADF rejects unit root decisively, KPSS strongly rejects stationarity. The diagnosis flags structural instability rather than a unit root.

2. **Structural break detection.** QLR test on the first-differenced series with 10% trimming locates a break at 2022-02-26 (supF = 22.5, p = 0.00048). A second QLR pass on the restricted sample finds no statistically significant additional break, so one restriction is sufficient.

3. **Model identification.** ACF/PACF of the doubly-differenced restricted series shows a single negative spike at lag 1, a large negative spike at lag 7, and geometric PACF decay at seasonal lags 7, 14, 21, 28, 35. The manual identification is ARIMA(0,1,1)(0,1,1)[7]. Auto-ARIMA on the same data selects ARIMA(3,1,1)(2,0,0)[7] with D = 0, handling weekly persistence via seasonal AR(2) rather than seasonal differencing.

4. **Estimation and Box-Cox sensitivity.** Four models are fitted on the post-2022 training set: manual airline ARIMA, auto-ARIMA, ETS(A,A,A), and dynamic regression with wind generation. Box-Cox is attempted as a sensitivity check against visible heteroskedasticity but rejected on evidence: the shift required to handle negative prices turns the most-negative day into a >4σ outlier under the log-like transformation.

5. **Forecast evaluation.** Two regimes: a single train/test split (test 2026-01-01 to 2026-04-19) and rolling-origin CV with `stretch_tsibble(.init = 730, .step = 30)` producing 26 windows each followed by a 30-day-ahead forecast. Dynamic regression is excluded from CV because honest evaluation would require forecasting wind for each horizon.

<br>

## Data Sources

All data is pulled from [**energidataservice.dk**](https://www.energidataservice.dk/), the free official API maintained by Energinet (the Danish transmission system operator).

| Dataset | Frequency | Coverage |
|---------|-----------|----------|
| Elspot Prices | Hourly | Through 2025-09-30 |
| Day-Ahead Prices | 15-minute | From 2025-10-01 |
| Production and Consumption (Settlement) | Hourly | From 2015-01-01 |

The schema migration on 2025-10-01 (when energidataservice.dk replaced the hourly Elspot endpoint with a 15-minute Day-Ahead one) is handled by aggregating both sources to daily means and stitching them on the date index. Wind generation is the sum of four sub-series (offshore <100 MW, offshore ≥100 MW, onshore <50 kW, onshore ≥50 kW).

<br>

## Repository Structure

```
dk1-electricity-price-forecasting/
│
├── 01_data_preparation.R   # Raw CSV loading, daily aggregation, schema-migration stitching
├── 02_analysis.R           # EDA, stationarity & break tests, ARIMA/ETS/dyn-reg, forecasting, CV
│
├── data/
│   ├── raw/                # gitignored, see data/raw/README.md for download instructions
│   └── clean/
│       ├── dk1_daily.rds
│       └── dk1_daily.csv
│
├── figures/
│   ├── 01_data_preparation/  # plots exported from 01_data_preparation.R
│   └── 02_analysis/          # plots exported from 02_analysis.R
│
├── dk1-electricity-price-forecasting.Rproj
├── .gitignore
└── README.md
```

> **Note**: `data/raw/` is git-ignored. The three source CSVs must be downloaded manually from energidataservice.dk before running `01_data_preparation.R`. See `data/raw/README.md` for instructions.

<br>

## Technologies Used

* **R 4.x** in **RStudio**
* [`fpp3`](https://otexts.com/fpp3/), bundling `tsibble`, `fable`, and `feasts` for the tsibble workflow, ARIMA / ETS / dynamic regression fitting, and forecast accuracy.
* [`urca`](https://cran.r-project.org/package=urca) for ADF and KPSS tests with full critical-value reporting.
* [`strucchange`](https://cran.r-project.org/package=strucchange) for the QLR / supF structural-break test.
* [`readr`](https://readr.tidyverse.org/) for the semicolon-delimited CSVs from energidataservice.dk, [`knitr`](https://yihui.org/knitr/) for rendered tables.

<br>

## How to Run

1. Clone the repository and open `dk1-electricity-price-forecasting.Rproj` in RStudio.
2. Install dependencies:
   ```r
   install.packages(c("fpp3", "here", "knitr", "readr",
                      "urca", "tseries", "strucchange"))
   ```
3. Download the three source CSVs from energidataservice.dk into `data/raw/` (see `data/raw/README.md`).
4. Run `01_data_preparation.R`. Saves the cleaned tsibble to `data/clean/dk1_daily.rds` and `dk1_daily.csv`.
5. Run `02_analysis.R`. Reads `data/clean/dk1_daily.rds` and runs the full analytical pipeline; plots render to the RStudio plot pane.

> Re-runs: `01_data_preparation.R` is idempotent. You can skip directly to `02_analysis.R` if `data/clean/dk1_daily.rds` already exists.

<br>

## Known Limitations

1. **Daily aggregation discards intra-day structure.** Real market participants trade in hourly (and now quarter-hourly) blocks; high-frequency dynamics are averaged out by the daily mean.
2. **Heteroskedasticity is accepted, not modelled.** All four models show 2022-2023 residual variance roughly 4x the post-2024 level. Point forecasts are unbiased, but prediction intervals should be interpreted with caution.
3. **Perfect-foresight caveat on dynamic regression.** The forecast comparison feeds dyn_reg the actual realised wind values from the test window. In production, wind would itself need to be forecast.
4. **Rolling-origin CV is univariate only.** Dynamic regression is left out of the CV comparison because honest evaluation would require iterated wind forecasts.
