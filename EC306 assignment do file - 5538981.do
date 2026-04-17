***********Importing and saving data: 

frame create monthly 
frame change monthly 
import excel "C:\Users\abhik\OneDrive\Desktop\Year 3\EC306\Assignment\AssignmentData2026.xlsx", sheet("Monthly") firstrow

* Declaring the time variable: 

generate t = mofd(observation_date)
format t %tm 
tsset t, m

save monthly, replace 

frame create quarterly 
frame change quarterly 
import excel "C:\Users\abhik\OneDrive\Desktop\Year 3\EC306\Assignment\AssignmentData2026.xlsx", sheet("Quarterly") firstrow clear

* Declaring the time variable: 

// Declaring the time variable: 

generate t = qofd(observation_date)
format t %tq
tsset t, q

save quarterly, replace 

********************************************************************************
*** Question 1a: 
********************************************************************************
use monthly 

// Taking log of series: 

generate ln_UNRATE = log(UNRATE)

// Plotting the unemployment data over time

tsline ln_UNRATE
	* The series looks quite stationary as the series looks like it's reverting to a mean
	* However, there seems to be quite a lot of persistence as values do not immediately revert back to the mean after shocks 
	* There is also a cyclical component (dips followed by booms)
	* We also see a large spike caused by COVID 
	
dfuller ln_UNRATE, notrend 
	* We reject the null hypothesis that the series is a random walk without drift
	* The test statistic is significant at the 5% level	
	
// Creating dummy for COVID period: 

generate COVIDdummy = 0 
replace COVIDdummy = 1 if t >= ym(2020, 1) & t <= ym(2020, 12)

// Creating seasonal dummies:

gen month = month(dofm(t))

// Extracting effects of COVID and seasonal effects: 

regress ln_UNRATE COVIDdummy i.month 
predict unemp_pure, resid 

tsline unemp_pure
	
// Looking at the ACF or PACF of the series: 

ac unemp_pure
	* Smooth decay indicates no MA structure 
pac unemp_pure
	* Looks like an AR(1) or AR(2)

// Conducting ADF test:

dfuller unemp_pure, notrend lags(6)
	* As there is no trend, model B is appropriate 
	* Null hypothesis for the ADF test is that the process is a random walk without drift 
	* Test statistic is significant at 1%, indicating the series is I(0)
	
// Using Box-Jenkins method (i.e. testing downwards): 

* AR lags: 

forvalues i = 6(-1)1 {
	display "---------------------------AR lag `i'---------------------------"
	quietly arima unemp_pure if tin(1947m1, 2025m12), ar(1/`i')
	estat ic 
}
	* BIC favours AR(2) whislt AIC favours AR(6)

* Ensuring the model is admissable: 
	
	* T = 933
	* Using sqrt(933) = 30 lags with the Ljung-Box serial correlation test for residuals seems a bit excessive as it amounts to 2.5 years worth of lag 
	* Therefore, sensible thing to do is to use 12 months
	
	
arima unemp_pure if tin(1947m1, 2025m12), ar(1/6)
predict resid_AR6, resid  

forvalues i = 1(1)12 {
	display "--------------------------- lag `i' ---------------------------"
	wntestq resid_AR6 if tin(1947m1, 2025m12), lags (`i')
}
	* We do not reject the null hypothesis (that residuals are white noise) up to lag 9
	* This means that there is no autocorrelation within the residuals up to lag 9
	* This means that there are significant seasonal patterns that we are missing 
	* This justifies the use of the monthly dummy variable in the final model
	
* MA lags: 

forvalues i = 6(-1)1 {
	display "--------------------------- MA lag `i' ---------------------------"
	quietly arima unemp_pure if tin(1947m1, 2025m12), ma(1/`i')
	estat ic 
}
	* AIC and BIC both favour MA(6)

* Ensuring the model is admissible: 

arima unemp_pure if tin(1947m1, 2025m12), ma(1/6)
predict resid_MA6, resid 

forvalues i = 1(1)12 {
	display "--------------------------- lag `i' ---------------------------"
	wntestq resid_MA6 if tin(1947m1, 2025m12), lags (`i')
}
	* We reject the null hypothesis (that residuals are white noise) at every lag order 
	* This means that there is autocorrelation within the residuals 
	* Therefore, as the MA models leave systematic patterns in the residuals, this makes the MA models inadmissible 

* Testing downwards: 

forvalues i = 8(-1)1 {
	display "--------------------------- lag `i' ---------------------------"
	quietly arima unemp_pure if tin(1947m1, 2025m12), ar(1/`i')
	estat ic 
	predict resid_AR_`i', resid 
	wntestq resid_AR_`i'
	drop resid_AR_`i'
}

	* We see that after dropping the 3rd lag, the residuals become autocorrelated
	* Indicates that the process is at least an AR(3) model
	* BIC is lowest for AR(3) but AIC is lowest for AR(6)
	* The model could be an AR(6)

	
* ARMA model: 
arimasoc unemp_pure	if tin(1947m1, 2025m12), maxar(6) maxma(6)
	* Multiple criteria indicate an AR(5) or AR(6) structure 
	
// Estimating the model: 

quietly tabulate month, generate(m)
arima unemp_pure COVIDdummy, ar(1/6)

// Diagnostic checks: 

predict resid_unemp_pure, residuals 
ac  resid_unemp_pure, title("ACF of ARIMA Residuals")
	* Significant lags at 1,3, and 9 may indicate seasonality 
pac resid_unemp_pure, title("PACF of ARIMA Residuals")
wntestq resid_unemp_pure, lags(90)
	* I use 90 lags because of rule of thumb, where lags = 0.1*T
	* Here, T = 932 (roughly equals 900)


* I therefore confirm that the residuals have no remaining (statistically significant) autocorrelation

********************************************************************************	
*** Question 1b:
********************************************************************************

// Generating prediction: 

arima unemp_pure if tin(1970m1, 2009m12), ar(1/6)
	* Whilst q1a suggested 6 lags, estimating this model shows that only 2 lags are significant 
	* Therefore, AR(2) is estimated instead 

arima unemp_pure if tin(1970m1, 2009m12), ar(1/2)
scalar ar2_rmse = e(sigma)
scalar phi1 = _b[ARMA:L1.ar]

gen fcast_1 = .
forvalues i = 1(1)188 {
	scalar fcast_date = ym(2009, 12) + `i'
	quietly predict sixstepfcast, y dynamic(fcast_date)
	quietly replace fcast_1 = sixstepfcast if t == (fcast_date + 6)
	drop sixstepfcast 
}

label variable unemp_pure "Smoothed change in unemployment rate"
label variable fcast_1 "6-step forecast"
tsline unemp_pure fcast_1 if t >= ym(2010, 1)

// Generating confidence intervals: 

gen fcast_1_var = fcast_1_rmse^2 * (1 - phi1^(2*6))/ (1 - phi1^2) if t > ym(2009,12) 
gen fcast_1_sigma = sqrt(fcast_1_var)

gen fcast_1_10CI = fcast_1 - 1.28*fcast_1_sigma if fcast_1_sigma != .
gen fcast_1_90CI = fcast_1 + 1.28*fcast_1_sigma if fcast_1_sigma != .

label variable fcast_1_10CI "10% confidence interval"
label variable fcast_1_90CI "90% confidence interval"

tsline unemp_pure fcast_1 fcast_1_10CI fcast_1_90CI if t >= ym(2010, 1)


// Evaluating forecast performance: 

gen est_unemp_levels = .
replace est_unemp_levels = UNRATE if _n == 763
replace est_unemp_levels = L.est_unemp_levels + fcast_1 if _n > 763

gen sq_err = (unemp_pure - fcast_1)^2
gen abs_err = abs(unemp_pure - fcast_1)

* Metrics over full forecast period: 
summarize sq_err if tin(2010m1, 2025m9)
scalar RMSE_full = sqrt(r(mean))
di "Full period RMSE = " RMSE_full
	* The RMSE across the entire period is 0.29 

summarize abs_err if tin(2010m1, 2025m9)
scalar MAE_full = r(mean)
di "Full period MAE = " MAE_full
	* The MAE across the entire forecast period is 0.136
	
tsline sq_err if t >= ym(2010, 1), ///
title("Squared Error of Forecast Across Forecasting Period") ///
ytitle("Squared Error") ///
xtitle("")
	* This graph shows the period(s) with the largest squared error
	* We see that COVID caused the largest errors 
tsline unemp_pure fcast_1 if t >= ym(2010, 1), ///
title("Changes in Unemployment: Actual vs Forecast", size(medthick)) ///
ytitle("Change in Unemployment") ///
xtitle("")		

* Metrics excluding COVID: 
summarize sq_err if tin(2010m1, 2019m12)
scalar RMSE_preCOVID = sqrt(r(mean))
di "Pre-COVID RMSE = " RMSE_preCOVID



********************************************************************************	
*** Question 1c: 
********************************************************************************

tsappend, add(6)
replace COVIDdummy = 0 if t > ym(2025, 9)

// Generating forecast: 

arima unemp_pure COVIDdummy if tin(1970m1, 2025m9), ar(1/2)
scalar fcast_2_rmse = e(sigma)
scalar fcast_2_phi1 = _b[ARMA:L1.ar]

predict fcast_2, y dynamic(ym(2025,9))
label variable fcast_2 "6-month forecast from Sept 2025"
	
// Confidence intervals: 	
 
gen fcast_2_var = fcast_2_rmse^2 * (1 - fcast_2_phi1^(2*6))/ (1 - fcast_2_phi1^2) if t > ym(2009,12) 
gen fcast_2_sigma = sqrt(fcast_1_var)

gen fcast_2_10CI = fcast_2 - 1.28*fcast_2_sigma if fcast_2_sigma != .
gen fcast_2_90CI = fcast_2 + 1.28*fcast_2_sigma if fcast_2_sigma != .

tsline unemp_pure fcast_2 fcast_2_10CI fcast_2_90CI if t >= ym(2010,1)


// Obtaining unemployment forecast in levels: 
replace est_unemp_levels = L.est_unemp_levels + fcast_2 if _n > 947	
	* The forecast for March 2026 is therefore around 4.2% 

* Considering that the unemployment rate in March 2026 was 4.3%, and my January model predicted 4.2%, my current model performed quite well 

	

save monthly, replace 

********************************************************************************
***  Question 2: 
********************************************************************************

/*
=============> Preparing CPI and TCU in monthly data: 
*/

use monthly, clear
 
rename CORESTICKM159SFRBATL core_CPI

* Quarter identifier: 
gen quarter = qofd(dofm(t))
format quarter %tq

* Month within quarter identifier
gen month_in_q = mod(month(dofm(t))-1, 3) + 1

* Within-quarter averages of Core CPI
bysort quarter (t): gen coreCPI_m1 = core_CPI if month_in_q == 1
bysort quarter (t): gen coreCPI_m2 = core_CPI if month_in_q <= 2
bysort quarter: egen coreCPI_1m = mean(coreCPI_m1)
bysort quarter: egen coreCPI_2m = mean(coreCPI_m2)
bysort quarter: egen coreCPI_3m = mean(core_CPI)

* Within-quarter averages of TCU
bysort quarter (t): gen TCU_m1 = TCU if month_in_q == 1
bysort quarter (t): gen TCU_m2 = TCU if month_in_q <= 2
bysort quarter: egen TCU_1m = mean(TCU_m1)
bysort quarter: egen TCU_2m = mean(TCU_m2)
bysort quarter: egen TCU_3m = mean(TCU)

* Collapse to quarterly
keep if month_in_q == 3
keep quarter TCU_1m TCU_2m TCU_3m coreCPI_1m coreCPI_2m coreCPI_3m
rename quarter t
save TCU_coreCPI_quarterly, replace

use quarterly, clear
merge 1:1 t using TCU_coreCPI_quarterly, nogen


/*
=============> Model selection for GDP:  
*/

tsline GDPC1 

* Taking log of series: 
gen ln_GDP = ln(GDPC1)

* Examining stationarity of series: 
dfuller ln_GDP, trend lags(4)	
	* As the GDP has a trend, model C is appropriate here 
	* The test statistic is insignificant at all levels
	* This means that the series is at least an I(1)

* Taking difference of series and examining stationarity: 
generate dln_GDP = d.ln_GDP 
tsline dln_GDP 
dfuller dln_GDP, drift lags(4)
	* Series looks stationary, centred around a mean
	* However, COVID remains an issue as it causes a large spike 
	* Test statistic is significant at 1% level, indicating that the series is I(0)

ac dln_GDP
pac dln_GDP	
	* The ACF and PACF indicate that the differenced series is an ARMA(1,1)
	* This indicates that the original series (ln_GDP) was an AR(1) with a unit root

		
	
/*
=============> Preparing forecasts for all variables: 
*/

gen gdp_fcast_base = .
gen gdp_fcast_1m   = .
gen gdp_fcast_2m   = .
gen gdp_fcast_3m   = .

local start_q = tq(2010q1)
local end_q   = tq(2019q4)

forvalues q = `start_q'(1)`end_q' {
    * Baseline ARIMA(1,0,1)
    quietly arima dln_GDP if t < `q', arima(1,0,1)
    quietly predict tmp_fcast, y dynamic(`q')
    quietly replace gdp_fcast_base = tmp_fcast if t == `q'
    drop tmp_fcast

    * 3-month model: full quarter of TCU and Core CPI observed
    quietly reg dln_GDP L.dln_GDP TCU_3m coreCPI_3m if t < `q'
    matrix b = e(b)
    quietly replace gdp_fcast_3m = ///
        b[1,1]*L.dln_GDP + b[1,2]*TCU_3m + b[1,3]*coreCPI_3m + b[1,4] ///
        if t == `q'

    * 2-month model: first 2 months of TCU and Core CPI observed
    quietly reg dln_GDP L.dln_GDP TCU_2m coreCPI_2m if t < `q'
    matrix b = e(b)
    quietly replace gdp_fcast_2m = ///
        b[1,1]*L.dln_GDP + b[1,2]*TCU_2m + b[1,3]*coreCPI_2m + b[1,4] ///
        if t == `q'

    * 1-month model: only first month of TCU and Core CPI observed
    quietly reg dln_GDP L.dln_GDP TCU_1m coreCPI_1m if t < `q'
    matrix b = e(b)
    quietly replace gdp_fcast_1m = ///
        b[1,1]*L.dln_GDP + b[1,2]*TCU_1m + b[1,3]*coreCPI_1m + b[1,4] ///
        if t == `q'
}

/*
=============> Out-of-sample RMSE's: 
*/

foreach m in base 1m 2m 3m {
    gen err_`m' = (dln_GDP - gdp_fcast_`m')^2
    summarize err_`m' if tq(2010q1) <= t & t <= tq(2019q4)
    scalar rmse_oos_`m' = sqrt(r(mean))
}

display "Baseline AR(2):" rmse_oos_base
display "1-month TCU and core CPI:" rmse_oos_1m 
display "2-month TCU and core CPI:" rmse_oos_2m 
display "3-month TCU and core CPI:" rmse_oos_3m 

/*
=============> Plots: 
*/

label variable dln_GDP         "Actual GDP growth"
label variable gdp_fcast_base "Baseline AR(2)"
label variable gdp_fcast_1m   "1-month TCU + Core CPI"
label variable gdp_fcast_2m   "2-month TCU + Core CPI"
label variable gdp_fcast_3m   "3-month TCU + Core CPI"

tsline dln_GDP gdp_fcast_base gdp_fcast_1m gdp_fcast_2m gdp_fcast_3m ///
    if tq(2010q1) <= t & t <= tq(2019q4), ///
    lpattern(solid dash "-." shortdash dot) ///
    lcolor(black red blue green orange) ///
    lwidth(medthick thin thin thin thin) ///
    title("1-Quarter Ahead GDP Growth Forecasts", size(medium)) ///
    ytitle("GDP Growth (log difference)") ///
    xtitle("") ///
    legend(rows(2) size(small))

graph export "gdp_forecasts_q2_coreCPI.png", replace


save quarterly, replace 

********************************************************************************
*** Question 3a: 
********************************************************************************

use monthly, clear 

sort t 

rename CORESTICKM159SFRBATL core_CPI
generate breakeven_inf = GS10 - FII10
generate all_CPI = 100*((CPIAUCSL/l12.CPIAUCSL) - 1)

label variable core_CPI "Core CPI"
label variable breakeven_inf "Breakeven Inflation" 
label variable all_CPI "All-goods CPI"


* Graph for inflation system in levels: 
tsline all_CPI core_CPI breakeven_inf if t >= ym(2003, 1), ///
    title("System for All-Items CPI, Core-CPI, and Breakeven Inflation", size(medium)) ///
    subtitle("Annual changes for all variables at a monthly frequency", size(small)) ///
    ytitle("Year-on-year change") ///
    xtitle("") ///
    lwidth(thin thin thin) ///
    legend(rows(3))
graph export "inflation_system.png", replace 

********************************************************************************
*** Question 3b: 
********************************************************************************

* Summary of the system:  
summarize breakeven_inf all_CPI core_CPI
corr breakeven_inf all_CPI core_CPI

* ACF and PACF plots: 
ac all_CPI, title("ACF: All-Items CPI Inflation")
ac core_CPI, title("ACF: Core CPI Inflation")
ac breakeven_inf, title("ACF: Breakeven Inflation")
	* ACFs all suggest no MA() structure 

pac all_CPI, title("PACF: All-Items CPI Inflation")
	* 2 significant lags indicate AR(2)
pac core_CPI, title("PACF: Core CPI Inflation")
	* 3 significant lags indicate AR(3)
pac breakeven_inf, title("PACF: Breakeven Inflation")
	* 2 significant lags indicate AR(2)

	
tsline all_CPI if t >= ym(2003,1)	
tsline core_CPI if t >= ym(2003,1)
tsline breakeven_inf if t >= ym(2003,1)
	
	
* Unit root tests: 	
dfuller all_CPI, constant drift lags(3)
	* Reject H0 of non-stationarity ay 1% level
dfuller core_CPI, constant drift lags(3) 
	* Reject H0 of non-stationarity ay 1% level
dfuller breakeven_inf, constant drift lags(3) 
	* Reject H0 of non-stationarity ay 1% level
	
	
* Breakeven inflation measures expected inflation
	* It measures difference btwn nominal and real yields from T-bonds 
	* Driven by market liquidity, policy shifts, and econ turbulence 
* In terms of volatility: 
	* All CPI > Breakeven inflation > Core CPI 
	* Makes sense as inflation expectations are anchored around 2% b/c of central bank 
* All goods CPI has pronounced peaks and troughs around 2008/9 and 2021/2, in line with shocks 
* No major trends (i.e. inflation is not trending upwards/downwards)
* I find evidence supporting how core CPI is more backwards looking/persistent as its PACF indicates a higher-order AR() structure compared to breakeven inflation and all-items CPI; the slower geometric decay indicates how it takes longer for shocks to die out 



********************************************************************************
*** Question 3c: 
********************************************************************************

// Part (i): 

varsoc all_CPI core_CPI breakeven_inf, maxlag(24)
	* AIC suggests optimal lag length of 16; HQIC and BIC suggest 2 lags 
var all_CPI core_CPI breakeven_inf if t >= ym(2003, 1), lags(1/2)
vargranger 
	* We see that core CPI and breakeven inflation are Granger causal to all CPI 
	* All-goods CPI is Granger causal to core CPI (and breakeven inflation)
	* This supports the argument that core CPI is forward-looking, since it predicts all-goods CPI 
	* The bidirectional Granger causality indicates the presence of a feedback loop between core CPI and all-goods CPI, where the former feeds into the latter, causing the latter to feed back into the former, and so on. 
	
irf create irf_3a, step(24) set(irf_q3ci-1 irf_q3ci-2) replace 
irf graph irf, impulse(core_CPI) response(all_CPI) name(irf3cgraph1, replace) title("Core CPI Shock on All-Goods CPI")
irf graph irf, impulse(all_CPI) response(core_CPI) name(irf3cgraph2, replace) title("All-Goods CPI Shock on Core CPI")
graph combine irf3cgraph1 irf3cgraph2, ycommon cols(2)

// Part (ii): 
	* All-goods CPI is a strong predictor of breakeven inflation, and vice versa 
	* This means it's a feedback loop, i.e. bidirectional causality (essentially, both variables are endogenous to some system)

save monthly, replace 

********************************************************************************
*** Question 4a: 
********************************************************************************

// Generating IRF of inflation to breakeven inflation rate: 

use monthly 

// Estimating VAR between breakeven inflation and CPI: 
varsoc all_CPI breakeven_inf, maxlag(12)
	* HQIC and BIC prefer lag length of 3; AIC prefers lag length of 11 
	* I thus choose a lag length of 3 
var all_CPI breakeven_inf, lags(1/3)

// Checking for cointegration: 
vecrank all_CPI breakeven_inf, lags(3) trend(constant)  
	* We see that there is no cointegrating relationship 

// Generating IRF: 
quietly var all_CPI breakeven_inf, lags(1/3)

irf create irf_q4a_ST, step(12) set(irf_q4a_ST) replace 
irf graph irf, impulse(breakeven_inf) response(all_CPI) name(irfq4a_graphST, replace)
	* This IRF shows us that an increase in inflation expectations will result in an increase in actual inflation
	* This is limited to the next 12 months however and is relatively short-term

irf table irf, impulse(breakeven_inf) response(all_CPI)
	* The table shows that there will be a 1.81 unit increase in inflation in response to a unit increase in inflation expectations, after one year 
	
quietly var all_CPI breakeven_inf, lags(1/3)	
irf create irf_q4a_LT, step(50) set(irf_q4a_LT) replace 
irf graph irf, impulse(breakeven_inf) response(all_CPI) name(irfq4a_graphLT, replace) ///
title("Response of All-Goods CPI to a shock in breakeven inflation", size(medium))
	* An IRF for the long-term shows the effects of higher inflation expectations
	* There is a ST increase and then a gradual return to original state
irf table irf, impulse(breakeven_inf) response(all_CPI)

	
********************************************************************************
*** Question 4b: 
********************************************************************************

/*
=============> SVAR: 
*/

* CPI ordered first: expectations react contemporaneously to prices,
* but prices only react to expectations with a lag (no contemporaneous effect)
matrix A = (1, 0 \ ., 1)
    * Row 1 (CPI): does NOT respond contemporaneously to breakeven inflation 
    * Row 2 (breakeven_inf): responds contemporaneously to CPI 

svar all_CPI breakeven_inf, lags(1/3) aeq(A)

irf create sirf_q4b_new, step(50) set(irf_SVAR_new) replace 
irf graph sirf, impulse(breakeven_inf) response(all_CPI) ci name(svar_expect_shock_new, replace) ///
    title("Response of Inflation to Structural Expectations Shock (Revised Ordering)")

* Forecast error variance decomposition:
irf table fevd, impulse(breakeven_inf all_CPI) response(all_CPI) step(12)	
	* This table provides a breakdown of how much each structural shock contributes to the varaince of the forecast for all-items CPI over 12 monhts
	* Column 1 = expectations shock; column 2 = fundamental price shock 
	* Over time, the pure expectations shock accounts for an increasing amount of total inflation variance over a year
	* However, at the end of the year, it only represents ~16% of total inflation variance, compared to a pure price shock which represented ~83%, confirming how the IRF in question 4a overestimated the impact of an expectations shock 

	
* I choose to compare the naive IRF with the OIRF instead of the IRF generated by the SVAR because they are on different scales so the comparison would not be meaningful	

/*
=============> Cholesky decomposition:   
*/

// Estimating initial VAR: 
varsoc breakeven_inf all_CPI, maxlag(12)
	* BIC suggests 2 lags; HQIC suggests 3 lags; AIC suggests 11 lags 
	* Will use 3 lags to be safe 
quietly var breakeven_inf all_CPI if t >= tm(2003m1), lags(1/3)

// Creating IRF for short-term: 
irf create irf_q4b_S, step(12) set(irf_q4b_S) replace 
irf graph oirf, impulse(breakeven_inf) response(all_CPI) name(irfq4b_graph1, replace)

// Comparing results from 4a (long-term results): 
irf create irf_q4b_L, step(50) set(irf_q4b_L) replace 
irf graph oirf irf, impulse(breakeven_inf) response(all_CPI) ///
title("Comparison between Naive and Orthogonalised IRF")
	* The oirf command applies Cholesky decomposition to orthogonalise the shocks
	* This shock is one standard deviation of the orthogonalised innovation
	* This shows that the effect of an isolated expectations shock is much lower 
	* This makes sense, given what we've seen with how breakeven inflation and all-goods CPI are Granger-causal to one another 

	
// Robustness check - switching ordering: 

* I switch the ordering to see if my results look the same or are different 
varsoc all_CPI breakeven_inf, maxlag(12)
	* BIC suggests 2 lags; HQIC suggests 3 lags; AIC suggests 11 lags 
	* Will use 3 lags 
quietly var all_CPI breakeven_inf 

irf create irf_q4b_robchec, step(50) set(irf_q4b_robchec) replace 		
irf graph oirf, impulse(breakeven_inf) response(all_CPI) 
irf graph oirf, impulse(all_CPI) response(breakeven_inf) 

irf graph oirf, irf(irf_q4b_L irf_q4b_robchec) impulse(all_CPI) response(breakeven_inf) 
	* The IRF shows that changing the ordering did not affect the shape of the IRF, indicating that it is not sensitive to ordering

			
	
********************************************************************************
*** Question 5: 
********************************************************************************

* Plotting all series: 
tsline all_CPI GS10 FII10 if t> ym(2003, 1)
	* We see that there is no trend; the series all seem stationary about a constant 
	* Therefore, model B is appropriate for testing stationarity 

* Generating dummy variables for 2008/9 recession and 2021/22 inflation spike: 	
generate dummy1 = 0
replace dummy1 = 1 if tin(2009m1, 2010m1)
generate dummy2 = 0 
replace dummy2 = 1 if tin(2021m1, 2022m1)

* Testing stationarity of series: 

foreach y in all_CPI GS10 FII10{
	display "---------------------Testing `y'---------------------"
	dfuller `y' if t > ym(2003,1), lags(6) noconstant 
	* Using 6 lags as T = 272, so T^(1/3) = 6.47 
}
		* We do NOT reject H0 for FII10 and GS10
		* Test statistic for all_CPI is significant at 10% 

* Using varsoc command to see the best lags based on information criteria: 
varsoc all_CPI d.GS10 d.FII10, maxlag(12) exog(dummy1 dummy2)
	* BIC and HQIC prefer lag 2, whilst AIC prefers lag 12 

* Testing for residual autocorrelation: 
var all_CPI d.GS10 d.FII10, lags(1/3) exog(dummy1 dummy2)
varlmar, mlag(3)
	* No serial correlation within residuals when estimating VAR with 3 lags
	* This justifies use of 3 lags 
	
* Estimating the cointegrating rank of the VAR: 
vecrank all_CPI GS10 FII10, lags(3) trend(rconstant)  
	* Have set trend(rconstant) option as there was no trend in any of the series
	* Have used rconstant rather than constant as we expect the cointegrating relationship to have a mean of zero 
	* The results show us that there are 2 cointegrating relationships (rank = 2)
	
* Estimating the corresponding VECM: 
vec all_CPI GS10 FII10, lags(3) trend(rconstant) rank(2)  	
	* Here, we see strong support for a relationship such that: 
	* GS10 - 1.18FII10 - 1.93 = 0  
	* There is not much support for a relationship between all_CPI and FII10, as it is statistically insignificant 

* In light of how the insignificant relationship between all_CPI and FII10, the true rank of the matrix appears to be 1 rather than 2 

* Estimating the VECM with corrected rank of 1 rather than 2: 
vec all_CPI GS10 FII10, lags(3) trend(rconstant) rank(1) alpha 		
		
* Imposing constraints:  
constraint define 1 [_ce1]GS10 = 1
vec all_CPI FII10 GS10, lags(3) trend(rconstant) rank(1) dforce bconstraints(1/1) alpha 

* Checking whether variables belong in the cointegrating relationship: 
constraint define 1 [_ce1]FII10 = 0
vec all_CPI GS10 FII10, rank(1) bconstraints(1)
	* This indicates that FII10 belongs in the cointegrating relationship
	* This is because of the significant likelihood ratio of the equation
	* chi2 statistic is 9.994 

constraint define 1 [_ce1]all_CPI = 0
vec all_CPI GS10 FII10, rank(1) bconstraints(1)	
	* This indicates that CPI does NOT belong in the cointegrating relationship 
	* This is because of the insignificant likelihood ratio of the equation
	* chi2 statistic is 0.712
	

* Creating impulse response functions: 
irf create irf_question5, step(50) set(irf_question5) replace 

irf graph oirf, impulse(FII10) response (GS10)
	* Suggests that a shock to real bond yields: 
		* at first positively affects nominal bond yields 
		* Later on diminished back to a positive constant (~0.12)
		
irf graph oirf, impulse (FII10) response (all_CPI)		
	* Suggests that a shock to real bond yields: 
		* at first negatively affects CPI 
		* In the long run, effect diminishes back to zero 
		
		
		
		
		
		
		
		
		
		
		
********************************************************************************
******************************** END OF SCRIPT *********************************		
********************************************************************************


