# =============================================================
# Predictive Analytics Project: DK1 Day-Ahead Price Forecasting
# Authors: David, Emanuele, Radu
# =============================================================

rm(list = ls())

library(fpp3)
library(here)   # robust file paths across machines
library(knitr)
library(urca)
library(strucchange)

# Suppress Rplots.pdf when run via Rscript. ggsave() and png() open and
# close their own devices, so anything routed to the default device would
# otherwise leak into an unwanted Rplots.pdf in the working directory.
# Interactive RStudio sessions still get the normal plot pane.
if (!interactive()) pdf(NULL)

# Where to save figures used in the report. Re-running 02_analysis.R
# end-to-end overwrites every PNG under figures/02_analysis/, so the
# report figures stay in sync with the latest model fits with no manual
# exporting. Each top-level section block writes into its own subfolder.
fig_root <- here("figures", "02_analysis")
dir.create(fig_root, showWarnings = FALSE, recursive = TRUE)

save_fig <- function(plot, name, width = 7, height = 4, dpi = 300) {
  path <- file.path(fig_root, name)
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  ggsave(path, plot, width = width, height = height, dpi = dpi, units = "in")
}

# Load the cleaned dataset prepared in 01_data_preparation.R.
dk1_daily <- readRDS(here("data/clean/dk1_daily.rds"))


# =============================================================
# 2. EXPLORATORY DATA ANALYSIS
# =============================================================

# --- Box-Cox lambda (diagnostic only) ---

# guerrero() requires strictly positive values, and DK1 prices
# include real negatives (oversupply with inflexible demand). To
# still get a sense of whether variance stabilisation might help,
# compute lambda on a shifted series. Whether we actually apply
# Box-Cox is decided later, from residual diagnostics on raw-data
# models.

shift_constant <- abs(min(dk1_daily$price_eur)) + 1

lambda <- dk1_daily %>%
  mutate(price_shifted = price_eur + shift_constant) %>%
  features(price_shifted, features = guerrero) %>%
  pull(lambda_guerrero)

print(lambda)


# --- Time plot, with energy-crisis period shaded ---

p_eda_price <- dk1_daily %>%
  autoplot(price_eur) +
  annotate("rect",
           xmin = as_date("2021-09-01"), xmax = as_date("2023-06-30"),
           ymin = -Inf, ymax = Inf,
           alpha = 0.15, fill = "red") +
  labs(
    title    = "DK1 Day-Ahead Electricity Price",
    subtitle = "Shaded - 2021-2023 European energy crisis",
    x = NULL, y = "EUR/MWh"
  )
save_fig(p_eda_price, "02_eda/01_DK1 Day-Ahead Electricity Price.png")


# --- Time plot, ACF, PACF ---

# lag_max = 60 spans roughly two months: long enough for the weekly
# cycle (period 7) to repeat several times and to see whether
# persistence decays slowly, which would point to a unit root.

p_eda_tsdisplay <- dk1_daily %>%
  gg_tsdisplay(price_eur, plot_type = "partial", lag_max = 60) +
  labs(title = "DK1 price - time plot, ACF, PACF")
save_fig(p_eda_tsdisplay,
         "02_eda/02_DK1 price - time plot, ACF, PACF.png", height = 5)


# --- Seasonal plot, weekly cycle ---

p_eda_season_week <- dk1_daily %>%
  gg_season(price_eur, period = "week") +
  labs(title = "Weekly seasonality of DK1 prices",
       y = "EUR/MWh")
save_fig(p_eda_season_week,
         "02_eda/03_Weekly seasonality of DK1 prices.png")


# --- Seasonal plot, annual cycle ---

p_eda_season_year <- dk1_daily %>%
  gg_season(price_eur, period = "year") +
  labs(title = "Annual seasonality of DK1 prices",
       y = "EUR/MWh")
save_fig(p_eda_season_year,
         "02_eda/04_Annual seasonality of DK1 prices.png")


# --- Subseries plot, day-of-week ---

p_eda_subseries <- dk1_daily %>%
  gg_subseries(price_eur, period = "week") +
  labs(title = "DK1 prices by day of week",
       y = "EUR/MWh")
save_fig(p_eda_subseries,
         "02_eda/05_DK1 prices by day of week.png")


# --- Lag plot, weekly horizon ---

# A full lag grid is illegible for 4,127 observations, and lags 1-7
# are the most informative view: they show the day-by-day persistence
# inside one weekly cycle.

p_eda_lag <- dk1_daily %>%
  gg_lag(price_eur, lags = 1:7, geom = "point") +
  labs(title = "Lag plot of DK1 prices, lags 1-7")
save_fig(p_eda_lag,
         "02_eda/06_Lag plot of DK1 prices, lags 1-7.png", height = 6)


# --- STL decomposition, weekly seasonality ---

# Weekly period (7) is the natural starting point: weekday demand
# peaks vs. lower weekend demand are the dominant calendar effect
# on daily prices. robust = TRUE downweights the 2022 spike so it
# does not distort the trend and seasonal estimates. If the remainder
# retains visible annual structure, add a year-period seasonal term
# in a follow-up.

p_eda_stl <- dk1_daily %>%
  model(STL(price_eur ~ season(period = 7) + trend(window = 21),
            robust = TRUE)) %>%
  components() %>%
  autoplot() +
  labs(title = "STL decomposition of DK1 prices (weekly seasonality)")
save_fig(p_eda_stl,
         "02_eda/07_STL decomposition of DK1 prices (weekly seasonality).png",
         height = 6)


# --- Wind generation distribution ---

# Daily totals across the 2015-2026 modelling sample.

summary(dk1_daily$wind_mwh)


# =============================================================
# 3. STATIONARITY TESTS ON LEVELS
# =============================================================

# Use urca for the test family because it returns critical values
# at multiple significance levels and the full regression output,
# which we need to interpret in the report. ADF is run at all
# three deterministic specifications (trend, drift, none) and KPSS
# at both (tau, mu), so the verdict is robust to the chosen
# deterministic component.

# --- ADF tests on price levels ---

# H0 (ADF): unit root present. Reject (small p-value, test stat
# below critical value) means stationary.

summary(ur.df(as.ts(dk1_daily$price_eur),
              type = "trend", lag = 24, selectlags = "AIC"))

summary(ur.df(as.ts(dk1_daily$price_eur),
              type = "drift", lag = 24, selectlags = "AIC"))

summary(ur.df(as.ts(dk1_daily$price_eur),
              type = "none", lag = 24, selectlags = "AIC"))


# --- KPSS tests on price levels ---

# H0 (KPSS): stationary. Reject means non-stationary.
# Running ADF and KPSS together gives a more confident verdict
# than either alone because they have opposite null hypotheses.

summary(ur.kpss(as.ts(dk1_daily$price_eur), type = "tau"))   # trend-stationary?
summary(ur.kpss(as.ts(dk1_daily$price_eur), type = "mu"))    # level-stationary?


# =============================================================
# 4. FIRST DIFFERENCING AND STATIONARITY TESTS
# =============================================================

# --- Compute first difference ---

# Stored on the tsibble so it stays aligned with the date index
# and can be reused for the structural-break test in Section 5.

dk1_daily <- dk1_daily %>%
  mutate(d_price = difference(price_eur))


# --- ADF and KPSS on the differenced series ---

summary(ur.df(dk1_daily %>% select(d_price) %>% filter(!is.na(d_price)) %>% as.ts(),
              type = "none", lag = 24, selectlags = "AIC"))

summary(ur.kpss(dk1_daily %>% select(d_price) %>% filter(!is.na(d_price)) %>% as.ts(), type = "mu"))


# --- Visual sanity check on the differenced series ---

p_diff_tsdisplay <- dk1_daily %>%
  gg_tsdisplay(d_price, plot_type = "partial", lag_max = 60) +
  labs(title = "First-differenced DK1 price - time plot, ACF, PACF")
save_fig(p_diff_tsdisplay,
         "04_differencing/01_First-differenced DK1 price - time plot, ACF, PACF.png",
         height = 5)


# =============================================================
# 5. STRUCTURAL BREAK TEST ON FIRST-DIFFERENCED SERIES
# =============================================================

# Regress the current first-difference on its own lag-1, scan
# F-statistics across every candidate break date, then read off
# the QLR / supF result. The from = 0.10 argument trims the first
# and last 10% of the sample so each candidate has enough
# observations on either side for the test to be valid.

# --- Build the regression data ---

d_ts <- dk1_daily %>%
  select(d_price) %>%
  filter(!is.na(d_price)) %>%
  as.ts()

dprice_ts <- cbind(
  Lag0 = d_ts,
  Lag1 = stats::lag(d_ts, k = -1)   # k = -1 gives a true lag; default k = 1 is a lead
)


# --- Fstats and supF test ---

# H0 (supF): no structural break. Rejection means at least one
# break exists somewhere in the searched range.

qlr <- Fstats(Lag0 ~ 1 + Lag1, data = dprice_ts, from = 0.10)

sctest(qlr, type = "supF")

breakpoints(qlr, alpha = 0.01)


# --- Plot the F-statistics with the estimated break date ---

dir.create(file.path(fig_root, "05_break_full"),
           showWarnings = FALSE, recursive = TRUE)
png(file.path(fig_root, "05_break_full",
              "01_QLR supF - structural-break F statistics.png"),
    width = 7, height = 4, units = "in", res = 300)
plot(qlr, alpha = 0.1, main = "QLR supF - structural-break F statistics")
lines(breakpoints(qlr))
dev.off()


# --- Map the breakpoint index back to a calendar date ---

bp_index <- breakpoints(qlr)$breakpoints

dk1_daily %>%
  filter(!is.na(d_price)) %>%
  slice(bp_index) %>%
  kable(digits = 2, align = "c")


# =============================================================
# 6. RE-TEST IN THE RESTRICTED POST-BREAK SAMPLE
# =============================================================

# The supF test pinpointed 2021-12-19, which sits in the late-2021
# European gas crisis: Gazprom had cut Yamal-Europe pipeline flows,
# TTF gas hit record highs around 21 December, and cold weather was
# draining storage. The regime shift therefore predates Russia's
# February 2022 invasion of Ukraine, although that later event almost
# certainly intensified an already-shifted regime. Restrict the sample
# to dates from the break onward and re-run the structural-break and
# stationarity tests. If the restricted sample still shows
# instability or unit-root behaviour, a further restriction or
# second differencing will follow.

# --- Restrict the sample and re-compute the first difference ---

# Keep all columns (price_eur, wind_mwh, consumption) so the
# restricted tsibble can later support the dynamic regression
# with wind as exogenous regressor in Section 13.

dk1_post <- dk1_daily %>%
  filter_index("2021-12-19" ~ .) %>%
  mutate(d_price = difference(price_eur))

range(dk1_post$date)
nrow(dk1_post)
summary(dk1_post$wind_mwh)


# --- Visual check on the restricted differenced series ---

p_post_diff_tsdisplay <- dk1_post %>%
  gg_tsdisplay(d_price, plot_type = "partial", lag_max = 60) +
  labs(title = "Post-break d_price - time plot, ACF, PACF")
save_fig(p_post_diff_tsdisplay,
         "06_break_restricted/01_Post-break d_price - time plot, ACF, PACF.png",
         height = 5)


# --- Re-run the QLR test on the restricted differenced series ---

# from = 0.15 (vs. 0.10 on the full sample): tighter trimming
# because the restricted sample is smaller and edge observations
# would otherwise have less reliable F-statistics.

d_post_ts <- dk1_post %>%
  select(d_price) %>%
  filter(!is.na(d_price)) %>%
  as.ts()

dprice_post_ts <- cbind(
  Lag0 = d_post_ts,
  Lag1 = stats::lag(d_post_ts, k = -1)   # k = -1 gives a true lag; default k = 1 is a lead
)

qlr_post <- Fstats(Lag0 ~ 1 + Lag1, data = dprice_post_ts, from = 0.15)

sctest(qlr_post, type = "supF")

breakpoints(qlr_post, alpha = 0.01)


# --- Plot the F-statistics for the restricted sample ---

dir.create(file.path(fig_root, "06_break_restricted"),
           showWarnings = FALSE, recursive = TRUE)
png(file.path(fig_root, "06_break_restricted",
              "02_QLR supF - F statistics, restricted sample.png"),
    width = 7, height = 4, units = "in", res = 300)
plot(qlr_post, alpha = 0.1,
     main = "QLR supF - F statistics, restricted sample")
lines(breakpoints(qlr_post))
dev.off()


# --- Map any restricted-sample breakpoint back to a date ---

bp_post_index <- breakpoints(qlr_post)$breakpoints

if (!any(is.na(bp_post_index))) {
  dk1_post %>%
    filter(!is.na(d_price)) %>%
    slice(bp_post_index) %>%
    kable(digits = 2, align = "c")
}


# =============================================================
# 7. STATIONARITY TESTS, RESTRICTED SAMPLE
# =============================================================

# Re-run ADF and KPSS on the restricted sample. With the major
# regime shift excluded, the two tests should now agree, either
# both supporting stationarity or both rejecting it. Persistent
# disagreement would indicate further break-related instability.

# --- ADF and KPSS on price levels, restricted sample ---

summary(ur.df(as.ts(dk1_post$price_eur),
              type = "trend", lag = 24, selectlags = "AIC"))

summary(ur.df(as.ts(dk1_post$price_eur),
              type = "drift", lag = 24, selectlags = "AIC"))

summary(ur.df(as.ts(dk1_post$price_eur),
              type = "none", lag = 24, selectlags = "AIC"))

summary(ur.kpss(as.ts(dk1_post$price_eur), type = "tau"))
summary(ur.kpss(as.ts(dk1_post$price_eur), type = "mu"))


# --- ADF and KPSS on first-differenced price, restricted sample ---

summary(ur.df(dk1_post %>% select(d_price) %>% filter(!is.na(d_price)) %>% as.ts(),
              type = "none", lag = 24, selectlags = "AIC"))

summary(ur.kpss(dk1_post %>% select(d_price) %>% filter(!is.na(d_price)) %>% as.ts(), type = "mu"))


# =============================================================
# 8. ACF AND PACF FOR MODEL IDENTIFICATION
# =============================================================

# The first-differenced restricted series has positive ACF
# spikes at every multiple of 7 that do not decay across 60
# lags, which is the textbook signature of weekly seasonal
# non-stationarity. Apply a seasonal difference (lag 7) on top
# of the first difference and inspect the ACF/PACF of the
# doubly-differenced series for the candidate ARIMA orders.

# --- Apply a seasonal difference (lag 7) ---

dk1_post <- dk1_post %>%
  mutate(dd_price = difference(d_price, lag = 7))


# --- Quick stationarity check on the doubly-differenced series ---

# Sanity check that the seasonal difference did not over-difference.

summary(ur.df(dk1_post %>% select(dd_price) %>% filter(!is.na(dd_price)) %>% as.ts(),
              type = "none", lag = 24, selectlags = "AIC"))

summary(ur.kpss(dk1_post %>% select(dd_price) %>% filter(!is.na(dd_price)) %>% as.ts(), type = "mu"))


# --- Time plot, ACF, PACF of the doubly-differenced series ---

p_dd_tsdisplay <- dk1_post %>%
  gg_tsdisplay(dd_price, plot_type = "partial", lag_max = 60) +
  labs(title = "Seasonally + first differenced post-break d_price")
save_fig(p_dd_tsdisplay,
         "08_identification/01_Seasonally + first differenced post-break d_price.png",
         height = 5)


# =============================================================
# 9. TRAIN/TEST SPLIT AND MODEL ESTIMATION
# =============================================================

# Train through 2025-12-31, test 2026-01-01 onward: a calendar-
# clean split that holds out the last available calendar quarter
# for evaluation while keeping the bulk of the post-break sample
# for estimation.

# --- Define training set ---

train <- dk1_post %>%
  filter_index(. ~ "2025-12-31")

range(train$date)
nrow(train)


# --- Fit competing models ---

# arma_manual is the airline ARIMA(0,1,1)(0,1,1)[7] identified
# from ACF/PACF in Section 8: single negative ACF spike at lag 1
# (non-seasonal MA(1)), single negative ACF spike at lag 7 with
# geometric PACF decay at seasonal lags 7, 14, 21, 28, 35
# (seasonal MA(1)). arma_auto lets ARIMA() select orders by AICc;
# ETS() picks error/trend/season components automatically.

models <- train %>%
  model(
    arma_manual = ARIMA(price_eur ~ pdq(0, 1, 1) + PDQ(0, 1, 1, period = 7)),
    arma_auto   = ARIMA(price_eur),
    ets         = ETS(price_eur)
  )


# =============================================================
# 10. MODEL SUMMARIES AND RESIDUAL DIAGNOSTICS
# =============================================================

# --- Print model summaries ---

models %>% select(arma_manual) %>% report()
models %>% select(arma_auto)   %>% report()
models %>% select(ets)         %>% report()


# --- Visual residual diagnostics ---

# gg_tsresiduals() shows the residual time plot, ACF, and
# distribution. type = "innovation" uses one-step-ahead errors.

p_resid_manual <- models %>% select(arma_manual) %>% gg_tsresiduals(type = "innovation")
p_resid_auto   <- models %>% select(arma_auto)   %>% gg_tsresiduals(type = "innovation")
p_resid_ets    <- models %>% select(ets)         %>% gg_tsresiduals(type = "innovation")
save_fig(p_resid_manual,
         "10_diagnostics_raw/01_Arima Manual Residual Diagnostic Raw.png",
         height = 5)
save_fig(p_resid_auto,
         "10_diagnostics_raw/02_Arima Auto Residual Diagnostic Raw.png",
         height = 5)
save_fig(p_resid_ets,
         "10_diagnostics_raw/03_ETS Residual Diagnostic Raw.png",
         height = 5)


# =============================================================
# 11. LJUNG-BOX TESTS ON RESIDUALS
# =============================================================

# H0: residuals are white noise. Rejection (small p) means
# remaining autocorrelation. lag = 20 covers roughly three
# weekly cycles. The dof argument is set to the number of ARMA
# parameters in each model, which is the standard correction:
#
#   arma_manual: ARIMA(0,1,1)(0,1,1)[7], so 2 ARMA params.
#   arma_auto:   ARIMA(3,1,1)(2,0,0)[7], so 6 ARMA params.
#   ets:         ETS(A,A,A), 3 smoothing parameters (initial
#                states are excluded from the dof correction by
#                textbook convention).

augment(models %>% select(arma_manual)) %>%
  features(.resid, features = ljung_box, lag = 20, dof = 2)

augment(models %>% select(arma_auto)) %>%
  features(.resid, features = ljung_box, lag = 20, dof = 6)

augment(models %>% select(ets)) %>%
  features(.resid, features = ljung_box, lag = 20, dof = 3)


# =============================================================
# 12. BOX-COX TRANSFORMED MODELS
# =============================================================

# Refit the three model types on Box-Cox transformed data as a
# sensitivity check, since the raw-data residuals show clear
# heteroskedasticity. Negative prices in the sample preclude
# direct application of Box-Cox, so we shift the series by
# abs(min) + 1 first; the inverse transform recovers EUR/MWh
# automatically at forecast time.

# --- Compute shift constant and lambda on the TRAINING sample ---

# Compute both on train only: using the full dk1_post would let test-period
# observations influence the transformation parameter, which is data leakage.

train <- dk1_post %>%
  filter_index(. ~ "2025-12-31")

shift_constant <- abs(min(train$price_eur, na.rm = TRUE)) + 1
print(shift_constant)

train <- train %>%
  mutate(price_shifted = price_eur + shift_constant)

lambda <- train %>%
  features(price_shifted, features = guerrero) %>%
  pull(lambda_guerrero)

print(lambda)


# --- Fit the same three model types on Box-Cox transformed data ---

models_bc <- train %>%
  model(
    arma_manual_bc = ARIMA(box_cox(price_shifted, lambda) ~ pdq(0, 1, 1) + PDQ(0, 1, 1, period = 7)),
    arma_auto_bc   = ARIMA(box_cox(price_shifted, lambda)),
    ets_bc         = ETS(box_cox(price_shifted, lambda))
  )


# --- Print summaries ---

models_bc %>% select(arma_manual_bc) %>% report()
models_bc %>% select(arma_auto_bc)   %>% report()
models_bc %>% select(ets_bc)         %>% report()


# --- Visual residual diagnostics ---

p_resid_manual_bc <- models_bc %>% select(arma_manual_bc) %>% gg_tsresiduals(type = "innovation")
p_resid_auto_bc   <- models_bc %>% select(arma_auto_bc)   %>% gg_tsresiduals(type = "innovation")
p_resid_ets_bc    <- models_bc %>% select(ets_bc)         %>% gg_tsresiduals(type = "innovation")
save_fig(p_resid_manual_bc,
         "12_diagnostics_boxcox/01_Arima Manual Residual Diagnostic Box Cox.png",
         height = 5)
save_fig(p_resid_auto_bc,
         "12_diagnostics_boxcox/02_Arima Auto Residual Diagnostic Box Cox.png",
         height = 5)
save_fig(p_resid_ets_bc,
         "12_diagnostics_boxcox/03_ETS Residual Diagnostic Box Cox.png",
         height = 5)


# --- Ljung-Box on transformed-data residuals ---

# arma_manual_bc: ARIMA(0,1,1)(0,1,1)[7], so 2 ARMA params.
# arma_auto_bc:   ARIMA(2,1,1)(0,0,2)[7], so 5 ARMA params.
# ets_bc:         ETS(A,N,A), 2 smoothing parameters
#                 (alpha and gamma; no trend component).

augment(models_bc %>% select(arma_manual_bc)) %>%
  features(.resid, features = ljung_box, lag = 20, dof = 2)

augment(models_bc %>% select(arma_auto_bc)) %>%
  features(.resid, features = ljung_box, lag = 20, dof = 5)

augment(models_bc %>% select(ets_bc)) %>%
  features(.resid, features = ljung_box, lag = 20, dof = 2)


# =============================================================
# 13. DYNAMIC REGRESSION AND FORECAST THE TEST PERIOD
# =============================================================

# Box-Cox transformation did not improve diagnostics: the
# negative-price outlier was amplified by the log on the shifted
# series, and Ljung-Box statistics on transformed-data residuals
# came out uniformly higher than on raw-data residuals across all
# three models. We therefore proceed with raw-data models. We then
# add dynamic regression with wind generation as a third method
# family, completing the comparison across ARIMA, ETS, and dynamic
# regression.

# --- Define training and test sets ---

train <- dk1_post %>% filter_index(. ~ "2025-12-31")
test  <- dk1_post %>% filter_index("2026-01-01" ~ .)

range(train$date); nrow(train)
range(test$date);  nrow(test)


# --- Fit four models on the training set ---

# arma_manual, arma_auto, ets as before. dyn_reg adds wind_mwh
# as exogenous regressor; ARIMA errors are auto-selected by AICc
# on the residuals after partialling out the wind effect.

models <- train %>%
  model(
    arma_manual = ARIMA(price_eur ~ pdq(0, 1, 1) + PDQ(0, 1, 1, period = 7)),
    arma_auto   = ARIMA(price_eur),
    ets         = ETS(price_eur),
    dyn_reg     = ARIMA(price_eur ~ wind_mwh)
  )


# --- Inspect the dynamic regression model ---

models %>% select(dyn_reg) %>% report()
p_resid_dynreg <- models %>% select(dyn_reg) %>% gg_tsresiduals(type = "innovation")
save_fig(p_resid_dynreg,
         "13_dyn_reg/01_Dynamic Regression Residual Diagnostic.png",
         height = 5)

# dyn_reg has LM with ARIMA(1,1,2)(2,0,0)[7] errors, so 5 ARMA
# params (the wind_mwh regression coefficient does not enter
# the dof correction).
augment(models %>% select(dyn_reg)) %>%
  features(.resid, features = ljung_box, lag = 20, dof = 5)


# --- Forecast over the test period ---

# new_data = test provides the future dates and the wind_mwh
# values that dyn_reg needs.

forc <- models %>%
  forecast(new_data = test)


# =============================================================
# 14. PLOT FORECASTS
# =============================================================

# Filter the backdrop to mid-2025 onward so the test period
# is visible without the 2022-2023 spike compressing the y-axis.

p_fc_manual <- forc %>%
  filter(.model == "arma_manual") %>%
  autoplot(dk1_post %>% filter_index("2025-07-01" ~ .)) +
  labs(title = "Manual ARIMA (airline) forecast vs actual",
       y = "EUR/MWh")
save_fig(p_fc_manual,
         "14_forecasts/01_Manual ARIMA (airline) forecast vs actual.png")

p_fc_auto <- forc %>%
  filter(.model == "arma_auto") %>%
  autoplot(dk1_post %>% filter_index("2025-07-01" ~ .)) +
  labs(title = "Auto-ARIMA forecast vs actual",
       y = "EUR/MWh")
save_fig(p_fc_auto,
         "14_forecasts/02_Auto-ARIMA forecast vs actual.png")

p_fc_ets <- forc %>%
  filter(.model == "ets") %>%
  autoplot(dk1_post %>% filter_index("2025-07-01" ~ .)) +
  labs(title = "ETS forecast vs actual",
       y = "EUR/MWh")
save_fig(p_fc_ets,
         "14_forecasts/03_ETS forecast vs actual.png")

p_fc_dynreg <- forc %>%
  filter(.model == "dyn_reg") %>%
  autoplot(dk1_post %>% filter_index("2025-07-01" ~ .)) +
  labs(title = "Dynamic regression (wind) forecast vs actual",
       y = "EUR/MWh")
save_fig(p_fc_dynreg,
         "14_forecasts/04_Dynamic regression (wind) forecast vs actual.png")


# =============================================================
# 15. COMPARE FORECAST ACCURACY
# =============================================================

# RMSE penalises large errors more than MAE. MAPE is scale-free
# but breaks near zero (negative prices). MASE scales by the
# in-sample naive forecast error, which is the most defensible
# single metric for this series.

accuracy(forc, dk1_post) %>%
  select(.model, RMSE, MAE, MAPE, MASE) %>%
  arrange(RMSE) %>%
  kable(digits = 2, align = "c")


# =============================================================
# 16. ROLLING-ORIGIN CROSS-VALIDATION
# =============================================================

# A more robust accuracy comparison than the single train/test
# split: stretch_tsibble() builds many overlapping training
# windows, each followed by a 30-day-ahead forecast. Accuracy
# is averaged across windows.
#
# Dynamic regression with wind requires future regressor values
# for each rolling window's horizon. An honest CV would need to
# forecast wind too, which compounds uncertainty in a way that
# the single-split Section 15 evaluation does not have to confront.
# We restrict CV to the three univariate models; the dyn_reg
# result from Section 15 stands.

# --- Build the rolling-window tsibble ---

# Slice off the last 30 days first so even the final window has
# 30 days of actuals to compare its forecast against.

dk1_cv <- dk1_post %>%
  slice(1:(n() - 30)) %>%
  stretch_tsibble(.init = 730, .step = 30)

# Sanity-check: how many windows, what sizes?
dk1_cv %>%
  count(.id) %>%
  summarise(
    n_windows = n(),
    smallest  = min(n),
    largest   = max(n)
  )


# --- Fit the three univariate models on each rolling window ---

# Several minutes of compute, since auto-ARIMA stepwise runs
# once per window per model.

models_cv <- dk1_cv %>%
  model(
    arma_manual = ARIMA(price_eur ~ pdq(0, 1, 1) + PDQ(0, 1, 1, period = 7)),
    arma_auto   = ARIMA(price_eur),
    ets         = ETS(price_eur)
  )


# --- Forecast 30 days ahead from each window ---

forc_cv <- models_cv %>%
  forecast(h = 30)


# --- Accuracy averaged across all rolling windows ---

# accuracy() compares each window's forecast against the
# corresponding 30 days of actuals from dk1_post, then averages
# by model.

forc_cv %>%
  accuracy(dk1_post) %>%
  select(.model, RMSE, MAE, MAPE, MASE) %>%
  arrange(RMSE) %>%
  kable(digits = 2, align = "c")
