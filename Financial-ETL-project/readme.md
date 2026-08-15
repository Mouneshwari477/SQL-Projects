## PROJECT OVERVIEW
The excel workbook simulates the Excel reporting layer of an end-to-end ETL pipeline.
Source of truth: financial_etl.db populated with
realistic corporate financial records across 500 companies, 6 fiscal years
(2019-2024), 1,779 loan accounts and annual credit ratings.

## ETL FLOW
1. schema.sql creates 4 normalized source tables: companies, financials, loans, ratings.
2. schema.sql also builds 'staging_company_year_summary' -- a SQL-side aggregation joining
   all 4 tables and computing EBITDA margin, Debt/Equity, Debt/EBITDA and loan exposure per
   company-year. 
3. In a live environment, Excel Power Query would connect directly to this staging table via
   (Data > Get Data > From Database) and refresh with one click.
   Since this file will be viewed outside a live DB connection, the staging table's output has
   been loaded as static data on the 'Staging_Summary' tab so every formula below still works.
4. Also schema.sql contains 7 additional analyst queries (YoY growth via LAG window
   function, high-leverage watchlist, top loan exposures, rating migration, regional concentration).

## HOW TO REPRODUCE THE LIVE REFRESH IN EXCEL
  Data tab -> Get Data -> From Database -> point at financial_etl.db
  -> select 'staging_company_year_summary' -> Load To -> This Worksheet -> Refresh on open.

## TABS IN THE EXCEL WORKBOOK
  Raw_Companies       Source company master data (500 rows)
  Raw_Financials       Source annual financials (3,000 rows)
  Raw_Loans             Source loan book (1,779 rows)
  Staging_Summary       SQL staging table output -- one row per company-year (3,000 rows)
  Sector_Dashboard      SUMIFS/AVERAGEIFS pivot-style summary + charts, latest FY only
  Company_Lookup        INDEX/MATCH lookup tool -- type any Company ID to pull its full profile.
  Watchlist              Companies with Debt/EBITDA > 4x in the latest fiscal year

All monetary figures are in INR Crore (Cr). Data is synthetic, generated for portfolio/
interview demonstration purposes and does not represent real companies.
