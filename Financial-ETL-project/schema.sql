-- ============================================================
-- Financial Data ETL & Automation Project
-- Schema: financial_etl
-- Author: Mouneshwari
-- Purpose: Raw multi-table financial records staged for
--          Excel reporting layer

CREATE DATABASE IF NOT EXISTS financial_etl;
USE financial_etl;
CREATE DATABASE IF NOT EXISTS crisil_financial_etl;
USE crisil_financial_etl;

CREATE TABLE companies (
    company_id           VARCHAR(10) PRIMARY KEY,
    company_name          VARCHAR(150) NOT NULL,
    sector                  VARCHAR(60) NOT NULL,
    region                    VARCHAR(30) NOT NULL,
    incorporation_year         INT,
    listed_status                 VARCHAR(15),
    employee_count                  INT
);

CREATE TABLE financials (
    company_id           VARCHAR(10) NOT NULL,
    fiscal_year            INT NOT NULL,
    revenue_cr               DECIMAL(14,2),
    ebitda_cr                  DECIMAL(14,2),
    net_income_cr                 DECIMAL(14,2),
    total_debt_cr                    DECIMAL(14,2),
    total_equity_cr                     DECIMAL(14,2),
    interest_expense_cr                    DECIMAL(14,2),
    PRIMARY KEY (company_id, fiscal_year),
    FOREIGN KEY (company_id) REFERENCES companies(company_id)
);

CREATE TABLE loans (
    loan_id                 VARCHAR(10) PRIMARY KEY,
    company_id                VARCHAR(10) NOT NULL,
    loan_type                    VARCHAR(50),
    sanctioned_amount_cr            DECIMAL(14,2),
    interest_rate_pct                  DECIMAL(5,2),
    tenure_years                          INT,
    disbursement_date                        DATE,
    status                                     VARCHAR(20),
    FOREIGN KEY (company_id) REFERENCES companies(company_id)
);

CREATE TABLE ratings (
    company_id       VARCHAR(10) NOT NULL,
    fiscal_year        INT NOT NULL,
    credit_rating          VARCHAR(5),
    outlook                    VARCHAR(30),
    PRIMARY KEY (company_id, fiscal_year),
    FOREIGN KEY (company_id) REFERENCES companies(company_id)
);

SELECT COUNT(*) FROM companies;
SELECT COUNT(*) FROM financials;
SELECT COUNT(*) FROM loans;
SELECT COUNT(*) FROM ratings;

CREATE INDEX idx_fin_company   ON financials(company_id);
CREATE INDEX idx_fin_year      ON financials(fiscal_year);
CREATE INDEX idx_loans_company ON loans(company_id);
CREATE INDEX idx_ratings_cy    ON ratings(company_id, fiscal_year);

-- ============================================================
-- STAGING TABLE: aggregated executive-report feed for Excel/Power Query
-- ============================================================

CREATE TABLE staging_company_year_summary AS
SELECT
    f.company_id,
    c.company_name,
    c.sector,
    c.region,
    f.fiscal_year,
    f.revenue_cr,
    f.ebitda_cr,
    ROUND(f.ebitda_cr * 1.0 / NULLIF(f.revenue_cr,0), 4)  AS ebitda_margin,
    f.net_income_cr,
    f.total_debt_cr,
    f.total_equity_cr,
    ROUND(f.total_debt_cr * 1.0 / NULLIF(f.total_equity_cr,0), 2) AS debt_to_equity,
    ROUND(f.total_debt_cr * 1.0 / NULLIF(f.ebitda_cr,0), 2)       AS debt_to_ebitda,
    (SELECT r.credit_rating FROM ratings r
       WHERE r.company_id = f.company_id AND r.fiscal_year = f.fiscal_year) AS credit_rating,
    (SELECT COUNT(*) FROM loans l WHERE l.company_id = f.company_id)         AS active_loan_count,
    (SELECT SUM(l.sanctioned_amount_cr) FROM loans l WHERE l.company_id = f.company_id) AS total_sanctioned_cr
FROM financials f
JOIN companies c ON c.company_id = f.company_id;

SELECT * FROM staging_company_year_summary WHERE company_id = 'C0001';

-- ============================================================
-- These queries feed the Excel executive dashboard (Power Query)
-- ============================================================

-- 1. Sector-wise revenue & EBITDA trend (latest fiscal year)
SELECT sector,
       COUNT(DISTINCT company_id)              AS company_count,
       ROUND(SUM(revenue_cr),2)                AS total_revenue_cr,
       ROUND(AVG(ebitda_margin)*100,2)          AS avg_ebitda_margin_pct,
       ROUND(AVG(debt_to_equity),2)             AS avg_debt_to_equity
FROM staging_company_year_summary
WHERE fiscal_year = (SELECT MAX(fiscal_year) FROM staging_company_year_summary)
GROUP BY sector
ORDER BY total_revenue_cr DESC;

-- 2. Year-over-year revenue growth per company (window function)
SELECT company_id, company_name, fiscal_year, revenue_cr,
       LAG(revenue_cr) OVER (PARTITION BY company_id ORDER BY fiscal_year) AS prev_year_revenue,
       ROUND(
         (revenue_cr - LAG(revenue_cr) OVER (PARTITION BY company_id ORDER BY fiscal_year))
         * 100.0 / NULLIF(LAG(revenue_cr) OVER (PARTITION BY company_id ORDER BY fiscal_year),0), 2
       ) AS yoy_growth_pct
FROM staging_company_year_summary
ORDER BY company_id, fiscal_year;

-- 3. High-leverage watchlist: Debt/EBITDA > 4x in the latest year, sorted by risk
SELECT company_id, company_name, sector, fiscal_year,
       debt_to_ebitda, debt_to_equity, credit_rating
FROM staging_company_year_summary
WHERE fiscal_year = (SELECT MAX(fiscal_year) FROM staging_company_year_summary)
  AND debt_to_ebitda > 4
ORDER BY debt_to_ebitda DESC;

-- 4. Top 10 companies by total sanctioned loan exposure
SELECT c.company_id, c.company_name, c.sector,
       SUM(l.sanctioned_amount_cr) AS total_sanctioned_cr,
       COUNT(l.loan_id)            AS loan_count,
       ROUND(AVG(l.interest_rate_pct),2) AS avg_interest_rate_pct
FROM loans l
JOIN companies c ON c.company_id = l.company_id
GROUP BY c.company_id, c.company_name, c.sector
ORDER BY total_sanctioned_cr DESC
LIMIT 10;

-- 5. Loan book health by status and type
SELECT loan_type, status,
       COUNT(*) AS loan_count,
       ROUND(SUM(sanctioned_amount_cr),2) AS total_amount_cr,
       ROUND(AVG(interest_rate_pct),2) AS avg_rate_pct
FROM loans
GROUP BY loan_type, status
ORDER BY loan_type, status;

-- 6. Rating migration check: companies whose rating worsened between first and last year on record
WITH first_last AS (
  SELECT company_id,
         MIN(fiscal_year) AS first_year,
         MAX(fiscal_year) AS last_year
  FROM ratings
  GROUP BY company_id
)
SELECT r1.company_id, c.company_name,
       r1.credit_rating AS rating_first_year, r1.fiscal_year AS first_year,
       r2.credit_rating AS rating_last_year,  r2.fiscal_year AS last_year
FROM first_last fl
JOIN ratings r1 ON r1.company_id = fl.company_id AND r1.fiscal_year = fl.first_year
JOIN ratings r2 ON r2.company_id = fl.company_id AND r2.fiscal_year = fl.last_year
JOIN companies c ON c.company_id = fl.company_id
WHERE r1.credit_rating <> r2.credit_rating;

-- 7. Region-wise portfolio concentration (sanctioned amount as % of total book)
SELECT c.region,
       ROUND(SUM(l.sanctioned_amount_cr),2) AS region_sanctioned_cr,
       ROUND(SUM(l.sanctioned_amount_cr) * 100.0 /
             (SELECT SUM(sanctioned_amount_cr) FROM loans), 2) AS pct_of_total_book
FROM loans l
JOIN companies c ON c.company_id = l.company_id
GROUP BY c.region
ORDER BY region_sanctioned_cr DESC;

SELECT * FROM staging_company_year_summary;


