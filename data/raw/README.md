# Raw data
The three CSV files below must be downloaded manually from [energidataservice.dk](https://www.energidataservice.dk/datasets)  
and placed in this folder before running `01_data_preparation.R`.

| File | Dataset | Filter | URL |
|---|---|---|---|
| `elspotprices.csv` | Elspot Prices | Price area: DK1 | [Elspotprices](https://www.energidataservice.dk/tso-electricity/Elspotprices) |
| `dayaheadprices.csv` | Day-Ahead Prices | Price area: DK1 | [DayAheadPrices](https://www.energidataservice.dk/tso-electricity/DayAheadPrices) |
| `production_consumption.csv` | Production and Consumption - Settlement | Price area: DK1 | [ProductionConsumptionSettlement](https://www.energidataservice.dk/tso-electricity/ProductionConsumptionSettlement) |

Export format: CSV with semicolon separator (the European default on the site).
