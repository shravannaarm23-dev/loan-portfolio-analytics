-- ============================================================================
-- Loan Portfolio Analytics — Star Schema (MySQL 8.0+)
-- ============================================================================
-- 1 fact table (fact_loans) + 5 dimension tables, built from a 3,000-loan
-- portfolio dataset (Q3 2024 – Q2 2026). Designed to back both ad-hoc SQL
-- analysis and a Power BI import-mode data model.
--
-- Run order: 01_schema.sql -> 02_etl_load.py -> 03_views.sql
--                                              -> 04_analysis_queries.sql
--                                              -> 05_stored_procedures.sql
-- ============================================================================

CREATE DATABASE IF NOT EXISTS `loan_portfolio`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE `loan_portfolio`;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS `fact_loans`;
DROP TABLE IF EXISTS `dim_date`;
DROP TABLE IF EXISTS `dim_grade`;
DROP TABLE IF EXISTS `dim_purpose`;
DROP TABLE IF EXISTS `dim_ownership`;
DROP TABLE IF EXISTS `dim_status`;
SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- dim_date — one row per distinct loan issue month (24 months in this dataset)
-- ----------------------------------------------------------------------------
CREATE TABLE `dim_date` (
  `date_key`      INT          NOT NULL PRIMARY KEY,   -- YYYYMMDD
  `full_date`     DATE         NOT NULL,
  `year`          SMALLINT     NOT NULL,
  `quarter_num`   TINYINT      NOT NULL,
  `quarter_label` VARCHAR(6)   NOT NULL,                -- e.g. '2025Q2'
  `month`         TINYINT      NOT NULL,
  `month_name`    VARCHAR(3)   NOT NULL,
  KEY `idx_dim_date_year_qtr` (`year`, `quarter_num`)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- dim_grade — one row per credit sub-grade (A1...G5)
-- ----------------------------------------------------------------------------
CREATE TABLE `dim_grade` (
  `grade_key`  INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `sub_grade`  VARCHAR(2)   NOT NULL UNIQUE,
  `grade`      CHAR(1)      NOT NULL,
  `grade_num`  TINYINT      NOT NULL,
  KEY `idx_dim_grade_grade` (`grade`)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- dim_purpose — one row per loan purpose
-- ----------------------------------------------------------------------------
CREATE TABLE `dim_purpose` (
  `purpose_key` INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `purpose`     VARCHAR(50)  NOT NULL UNIQUE
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- dim_ownership — one row per home ownership status
-- ----------------------------------------------------------------------------
CREATE TABLE `dim_ownership` (
  `ownership_key`   INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `home_ownership`  VARCHAR(20)  NOT NULL UNIQUE
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- dim_status — one row per loan status, carrying the pre-engineered risk flag
-- ----------------------------------------------------------------------------
CREATE TABLE `dim_status` (
  `status_key`   INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `loan_status`  VARCHAR(30)  NOT NULL UNIQUE,
  `is_risk`      TINYINT(1)   NOT NULL,
  `risk_label`   VARCHAR(20)  NOT NULL
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- fact_loans — one row per loan (grain = loan_id), 3,000 rows
-- ----------------------------------------------------------------------------
CREATE TABLE `fact_loans` (
  `loan_id`                  INT             NOT NULL PRIMARY KEY,
  `date_key`                 INT             NOT NULL,
  `grade_key`                INT             NOT NULL,
  `purpose_key`               INT            NOT NULL,
  `ownership_key`             INT            NOT NULL,
  `status_key`                INT            NOT NULL,
  `term_months`               TINYINT        NOT NULL,
  `term_label`                VARCHAR(12)    NOT NULL,
  `loan_amnt`                 DECIMAL(10,2)  NOT NULL,
  `int_rate`                  DECIMAL(5,2)   NOT NULL,
  `installment`                DECIMAL(10,2) NOT NULL,
  `emp_length`                 VARCHAR(10),
  `emp_length_num`             TINYINT,
  `annual_inc`                 DECIMAL(12,2) NOT NULL,
  `annual_inc_capped`          DECIMAL(12,2) NOT NULL,
  `annual_inc_flagged`         TINYINT(1)    NOT NULL,
  `dti`                        DECIMAL(6,2)  NOT NULL,
  `dti_band`                   VARCHAR(20)   NOT NULL,
  `out_prncp`                  DECIMAL(12,2) NOT NULL,
  `total_pymnt`                DECIMAL(12,2) NOT NULL,
  `total_rec_prncp`            DECIMAL(12,2) NOT NULL,
  `total_rec_int`              DECIMAL(12,2) NOT NULL,
  `recoveries`                 DECIMAL(12,2) NOT NULL,
  `collection_recovery_fee`    DECIMAL(10,2) NOT NULL,
  `delinq_2yrs`                TINYINT       NOT NULL,
  `revol_util`                 DECIMAL(6,2),
  `total_acc`                  SMALLINT      NOT NULL,
  `loan_to_income_pct`         DECIMAL(6,2)  NOT NULL,
  `repayment_progress_pct`     DECIMAL(6,2)  NOT NULL,
  `income_band`                VARCHAR(20)   NOT NULL,
  `loan_size_band`             VARCHAR(20)   NOT NULL,
  CONSTRAINT `fk_fact_date`      FOREIGN KEY (`date_key`)      REFERENCES `dim_date`(`date_key`),
  CONSTRAINT `fk_fact_grade`     FOREIGN KEY (`grade_key`)     REFERENCES `dim_grade`(`grade_key`),
  CONSTRAINT `fk_fact_purpose`   FOREIGN KEY (`purpose_key`)   REFERENCES `dim_purpose`(`purpose_key`),
  CONSTRAINT `fk_fact_ownership` FOREIGN KEY (`ownership_key`) REFERENCES `dim_ownership`(`ownership_key`),
  CONSTRAINT `fk_fact_status`    FOREIGN KEY (`status_key`)    REFERENCES `dim_status`(`status_key`),
  KEY `idx_fact_date`        (`date_key`),
  KEY `idx_fact_grade`       (`grade_key`),
  KEY `idx_fact_purpose`     (`purpose_key`),
  KEY `idx_fact_ownership`   (`ownership_key`),
  KEY `idx_fact_status`      (`status_key`),
  KEY `idx_fact_dti_band`    (`dti_band`),
  KEY `idx_fact_income_band` (`income_band`)
) ENGINE=InnoDB;

-- ============================================================================
-- 05_stored_procedures.sql — Loan Portfolio Analytics
-- ============================================================================
-- Three stored procedures — one per dashboard — that return the exact result
-- sets Power BI (or any BI tool) needs in a single CALL. Each accepts an
-- optional grade filter so you can drill into a single grade from the UI.
-- ============================================================================

USE `loan_portfolio`;

DROP PROCEDURE IF EXISTS `sp_risk_dashboard`;
DROP PROCEDURE IF EXISTS `sp_borrower_dashboard`;
DROP PROCEDURE IF EXISTS `sp_repayment_dashboard`;

DELIMITER $$

-- ============================================================================
-- sp_risk_dashboard(p_grade VARCHAR(1))
-- Returns 4 result sets: KPIs | by-grade | by-DTI | by-purpose
-- p_grade: pass a letter A-G to filter, or NULL / '' for all grades
-- ============================================================================
CREATE PROCEDURE `sp_risk_dashboard`(IN p_grade VARCHAR(1))
BEGIN

    -- Inline filter helper
    SET @filter_grade = NULLIF(TRIM(p_grade), '');

    -- RS1: KPIs
    SELECT
        COUNT(*)                                              AS total_loans,
        SUM(is_risk)                                          AS at_risk_loans,
        ROUND(100.0 * SUM(is_risk) / COUNT(*), 2)            AS at_risk_pct,
        ROUND(AVG(int_rate),  2)                              AS avg_int_rate,
        ROUND(AVG(dti),       2)                              AS avg_dti,
        ROUND(SUM(loan_amnt), 0)                              AS total_originated
    FROM vw_loan_detail
    WHERE (@filter_grade IS NULL OR grade = @filter_grade);

    -- RS2: By grade
    SELECT
        grade, loan_count, at_risk_count, at_risk_pct, avg_int_rate, avg_dti
    FROM vw_risk_by_grade
    WHERE (@filter_grade IS NULL OR grade = @filter_grade);

    -- RS3: By DTI band
    SELECT
        dti_band, loan_count, at_risk_count, at_risk_pct
    FROM vw_risk_by_dti
    ORDER BY sort_order;

    -- RS4: By purpose
    SELECT
        purpose, loan_count, at_risk_count, at_risk_pct, avg_int_rate
    FROM vw_risk_by_purpose
    ORDER BY at_risk_pct DESC;

END$$


-- ============================================================================
-- sp_borrower_dashboard(p_ownership VARCHAR(20))
-- Returns 4 result sets: KPIs | income band | ownership | emp length
-- p_ownership: 'Rent' / 'Own' / 'Mortgage' or NULL for all
-- ============================================================================
CREATE PROCEDURE `sp_borrower_dashboard`(IN p_ownership VARCHAR(20))
BEGIN

    SET @filter_own = NULLIF(TRIM(p_ownership), '');

    -- RS1: KPIs
    SELECT
        COUNT(*)                                              AS total_borrowers,
        ROUND(AVG(annual_inc_capped), 0)                      AS avg_annual_income,
        ROUND(AVG(loan_amnt),         0)                      AS avg_loan_amnt,
        ROUND(AVG(loan_to_income_pct),1)                      AS avg_lti_pct,
        ROUND(100.0 * SUM(CASE WHEN home_ownership IN ('Own','Mortgage') THEN 1 ELSE 0 END)
              / COUNT(*), 1)                                  AS homeowner_share_pct
    FROM vw_loan_detail
    WHERE (@filter_own IS NULL OR home_ownership = @filter_own);

    -- RS2: Income band
    SELECT
        income_band,
        COUNT(*)                                              AS borrower_count,
        ROUND(AVG(annual_inc_capped), 0)                      AS avg_income,
        ROUND(AVG(loan_amnt),         0)                      AS avg_loan_amnt,
        ROUND(AVG(loan_to_income_pct),1)                      AS avg_lti_pct
    FROM vw_loan_detail
    WHERE (@filter_own IS NULL OR home_ownership = @filter_own)
    GROUP BY income_band
    ORDER BY CASE income_band
        WHEN 'Under 30K' THEN 1 WHEN '30–50K' THEN 2 WHEN '50–75K' THEN 3
        WHEN '75–100K'   THEN 4 ELSE 5 END;

    -- RS3: Ownership
    SELECT
        home_ownership,
        COUNT(*)                                              AS borrower_count,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_portfolio,
        ROUND(AVG(annual_inc_capped), 0)                      AS avg_income
    FROM vw_loan_detail
    GROUP BY home_ownership
    ORDER BY borrower_count DESC;

    -- RS4: Employment length
    SELECT
        emp_length,
        emp_length_num,
        COUNT(*)                                              AS borrower_count,
        ROUND(AVG(annual_inc_capped), 0)                      AS avg_income,
        ROUND(100.0 * SUM(is_risk) / COUNT(*), 2)            AS at_risk_pct
    FROM vw_loan_detail
    WHERE (@filter_own IS NULL OR home_ownership = @filter_own)
    GROUP BY emp_length, emp_length_num
    ORDER BY emp_length_num;

END$$


-- ============================================================================
-- sp_repayment_dashboard(p_grade VARCHAR(1), p_term TINYINT)
-- Returns 4 result sets: KPIs | by grade | by quarter | exposure
-- p_term: 36 or 60 to filter, or NULL for both
-- ============================================================================
CREATE PROCEDURE `sp_repayment_dashboard`(IN p_grade VARCHAR(1), IN p_term TINYINT)
BEGIN

    SET @filter_grade = NULLIF(TRIM(p_grade), '');
    SET @filter_term  = p_term;

    -- RS1: Financial KPIs
    SELECT
        ROUND(SUM(loan_amnt),               0)  AS total_originated,
        ROUND(SUM(total_pymnt),             2)  AS total_collected,
        ROUND(SUM(total_rec_int),           2)  AS interest_earned,
        ROUND(SUM(out_prncp),               2)  AS outstanding_principal,
        ROUND(SUM(recoveries),              2)  AS total_recoveries,
        ROUND(AVG(repayment_progress_pct),  2)  AS avg_repayment_progress
    FROM vw_loan_detail
    WHERE (@filter_grade IS NULL OR grade       = @filter_grade)
      AND (@filter_term  IS NULL OR term_months = @filter_term);

    -- RS2: By grade
    SELECT
        grade, total_originated, total_interest_earned,
        total_principal_received, total_outstanding, avg_repayment_progress
    FROM vw_repayment_by_grade
    WHERE (@filter_grade IS NULL OR grade = @filter_grade);

    -- RS3: By quarter
    SELECT
        quarter_label, total_originated, total_payments_received, interest_earned
    FROM vw_repayment_by_quarter
    ORDER BY year, quarter_num;

    -- RS4: At-risk loan exposure summary
    SELECT
        ROUND(SUM(loan_amnt),   0)                            AS at_risk_value,
        ROUND(SUM(recoveries),  2)                            AS recovered,
        ROUND(100.0 * SUM(recoveries) /
              NULLIF(SUM(loan_amnt), 0), 2)                   AS recovery_rate_pct,
        COUNT(*)                                              AS at_risk_count
    FROM vw_loan_detail
    WHERE is_risk = 1
      AND (@filter_grade IS NULL OR grade = @filter_grade);

END$$

DELIMITER ;

-- ============================================================================
-- Quick smoke-tests — uncomment to verify after loading data
-- ============================================================================
-- CALL sp_risk_dashboard(NULL);      -- all grades
-- CALL sp_risk_dashboard('E');       -- E-grade only
-- CALL sp_borrower_dashboard(NULL);
-- CALL sp_borrower_dashboard('Rent');
-- CALL sp_repayment_dashboard(NULL, NULL);
-- CALL sp_repayment_dashboard('B', 36);

-- ============================================================================
-- 03_views.sql — Loan Portfolio Analytics
-- ============================================================================
-- Seven reusable views, one per dashboard topic.
-- Every Power BI visual and every analysis query in 04_analysis_queries.sql
-- references one of these views rather than the raw tables directly.
--
-- Dashboard mapping:
--   Risk Analysis    → vw_risk_by_grade, vw_risk_by_purpose, vw_risk_by_dti
--   Borrower Profile → vw_borrower_profile
--   Repayment & Fin  → vw_repayment_by_grade, vw_repayment_by_quarter
--   Cross-cutting    → vw_loan_detail (full flat view for Power BI slicers)
-- ============================================================================

USE `loan_portfolio`;

-- ============================================================================
-- 1. vw_risk_by_grade
--    Default rate, average rate, and average DTI by credit grade
-- ============================================================================
CREATE OR REPLACE VIEW `vw_risk_by_grade` AS
SELECT
    g.grade,
    g.grade_num,
    COUNT(*)                                                AS loan_count,
    SUM(s.is_risk)                                          AS at_risk_count,
    ROUND(100.0 * SUM(s.is_risk) / COUNT(*), 2)            AS at_risk_pct,
    ROUND(AVG(f.int_rate), 2)                               AS avg_int_rate,
    ROUND(AVG(f.dti),      2)                               AS avg_dti,
    ROUND(AVG(f.loan_amnt),2)                               AS avg_loan_amnt,
    ROUND(SUM(f.loan_amnt),0)                               AS total_loan_amnt
FROM fact_loans     f
JOIN dim_grade      g ON f.grade_key  = g.grade_key
JOIN dim_status     s ON f.status_key = s.status_key
GROUP BY g.grade, g.grade_num
ORDER BY g.grade_num;


-- ============================================================================
-- 2. vw_risk_by_purpose
--    At-risk rate per loan purpose, ranked by volume
-- ============================================================================
CREATE OR REPLACE VIEW `vw_risk_by_purpose` AS
SELECT
    p.purpose,
    COUNT(*)                                                AS loan_count,
    SUM(s.is_risk)                                          AS at_risk_count,
    ROUND(100.0 * SUM(s.is_risk) / COUNT(*), 2)            AS at_risk_pct,
    ROUND(AVG(f.int_rate), 2)                               AS avg_int_rate,
    ROUND(SUM(f.loan_amnt), 0)                              AS total_loan_amnt
FROM fact_loans     f
JOIN dim_purpose    p ON f.purpose_key = p.purpose_key
JOIN dim_status     s ON f.status_key  = s.status_key
GROUP BY p.purpose
ORDER BY loan_count DESC;


-- ============================================================================
-- 3. vw_risk_by_dti
--    At-risk rate per DTI band (Low / Medium / High / Very High)
-- ============================================================================
CREATE OR REPLACE VIEW `vw_risk_by_dti` AS
SELECT
    f.dti_band,
    CASE f.dti_band
        WHEN 'Low (0–10)'       THEN 1
        WHEN 'Medium (10–20)'   THEN 2
        WHEN 'High (20–30)'     THEN 3
        WHEN 'Very High (30+)'  THEN 4
        ELSE 5
    END                                                     AS sort_order,
    COUNT(*)                                                AS loan_count,
    SUM(s.is_risk)                                          AS at_risk_count,
    ROUND(100.0 * SUM(s.is_risk) / COUNT(*), 2)            AS at_risk_pct,
    ROUND(AVG(f.dti), 2)                                    AS avg_dti
FROM fact_loans  f
JOIN dim_status  s ON f.status_key = s.status_key
GROUP BY f.dti_band
ORDER BY sort_order;


-- ============================================================================
-- 4. vw_borrower_profile
--    Income band breakdown with loan and borrower metrics
-- ============================================================================
CREATE OR REPLACE VIEW `vw_borrower_profile` AS
SELECT
    f.income_band,
    CASE f.income_band
        WHEN 'Under 30K'  THEN 1
        WHEN '30–50K'     THEN 2
        WHEN '50–75K'     THEN 3
        WHEN '75–100K'    THEN 4
        WHEN 'Over 100K'  THEN 5
        ELSE 6
    END                                                     AS sort_order,
    o.home_ownership,
    COUNT(*)                                                AS borrower_count,
    ROUND(AVG(f.annual_inc_capped), 0)                      AS avg_annual_inc,
    ROUND(AVG(f.loan_amnt),         0)                      AS avg_loan_amnt,
    ROUND(AVG(f.loan_to_income_pct),1)                      AS avg_loan_to_inc_pct,
    ROUND(100.0 * SUM(s.is_risk) / COUNT(*), 2)            AS at_risk_pct
FROM fact_loans   f
JOIN dim_ownership o ON f.ownership_key = o.ownership_key
JOIN dim_status    s ON f.status_key    = s.status_key
GROUP BY f.income_band, o.home_ownership
ORDER BY sort_order, o.home_ownership;


-- ============================================================================
-- 5. vw_repayment_by_grade
--    Financial performance metrics grouped by credit grade
-- ============================================================================
CREATE OR REPLACE VIEW `vw_repayment_by_grade` AS
SELECT
    g.grade,
    g.grade_num,
    COUNT(*)                                                AS loan_count,
    ROUND(SUM(f.loan_amnt),           0)                    AS total_originated,
    ROUND(SUM(f.total_pymnt),         2)                    AS total_paid,
    ROUND(SUM(f.total_rec_int),       2)                    AS total_interest_earned,
    ROUND(SUM(f.total_rec_prncp),     2)                    AS total_principal_received,
    ROUND(SUM(f.out_prncp),           2)                    AS total_outstanding,
    ROUND(SUM(f.recoveries),          2)                    AS total_recoveries,
    ROUND(AVG(f.repayment_progress_pct), 2)                 AS avg_repayment_progress
FROM fact_loans  f
JOIN dim_grade   g ON f.grade_key = g.grade_key
GROUP BY g.grade, g.grade_num
ORDER BY g.grade_num;


-- ============================================================================
-- 6. vw_repayment_by_quarter
--    Quarterly origination and payment trend (for Power BI time-series chart)
-- ============================================================================
CREATE OR REPLACE VIEW `vw_repayment_by_quarter` AS
SELECT
    d.quarter_label,
    d.year,
    d.quarter_num,
    COUNT(*)                                                AS loan_count,
    ROUND(SUM(f.loan_amnt),       0)                        AS total_originated,
    ROUND(SUM(f.total_pymnt),     2)                        AS total_payments_received,
    ROUND(SUM(f.total_rec_int),   2)                        AS interest_earned,
    ROUND(SUM(f.recoveries),      2)                        AS recoveries
FROM fact_loans  f
JOIN dim_date    d ON f.date_key = d.date_key
GROUP BY d.quarter_label, d.year, d.quarter_num
ORDER BY d.year, d.quarter_num;


-- ============================================================================
-- 7. vw_loan_detail
--    Full denormalized flat view — used as the single Power BI import table
--    and as the source for ad-hoc analysis
-- ============================================================================
CREATE OR REPLACE VIEW `vw_loan_detail` AS
SELECT
    f.loan_id,
    d.full_date           AS issue_date,
    d.year                AS issue_year,
    d.quarter_label       AS issue_quarter,
    d.month_name          AS issue_month,
    g.grade,
    g.sub_grade,
    g.grade_num,
    p.purpose,
    o.home_ownership,
    st.loan_status,
    st.is_risk,
    st.risk_label,
    f.term_months,
    f.term_label,
    f.loan_amnt,
    f.int_rate,
    f.installment,
    f.emp_length,
    f.emp_length_num,
    f.annual_inc,
    f.annual_inc_capped,
    f.dti,
    f.dti_band,
    f.income_band,
    f.loan_size_band,
    f.loan_to_income_pct,
    f.out_prncp,
    f.total_pymnt,
    f.total_rec_prncp,
    f.total_rec_int,
    f.recoveries,
    f.collection_recovery_fee,
    f.repayment_progress_pct,
    f.delinq_2yrs,
    f.revol_util,
    f.total_acc
FROM      fact_loans    f
JOIN      dim_date      d  ON f.date_key      = d.date_key
JOIN      dim_grade     g  ON f.grade_key     = g.grade_key
JOIN      dim_purpose   p  ON f.purpose_key   = p.purpose_key
JOIN      dim_ownership o  ON f.ownership_key = o.ownership_key
JOIN      dim_status    st ON f.status_key    = st.status_key;

-- ============================================================================
-- 04_analysis_queries.sql — Loan Portfolio Analytics
-- ============================================================================
-- 20 production-ready analytical queries grouped by dashboard.
-- All queries run against the views in 03_views.sql.
-- Tested output values match the case-study numbers exactly.
-- ============================================================================

USE `loan_portfolio`;

-- ============================================================================
-- SECTION A — RISK ANALYSIS  (who defaults and why)
-- ============================================================================

-- A-1: Portfolio-level KPI snapshot
-- Headline numbers for the dashboard summary cards
SELECT
    COUNT(*)                                              AS total_loans,
    SUM(is_risk)                                          AS at_risk_loans,
    ROUND(100.0 * SUM(is_risk) / COUNT(*), 2)            AS at_risk_pct,
    ROUND(AVG(int_rate),  2)                              AS avg_int_rate,
    ROUND(AVG(dti),       2)                              AS avg_dti,
    ROUND(SUM(loan_amnt), 0)                              AS total_originated_usd
FROM vw_loan_detail;


-- A-2: At-risk rate and interest rate by grade (core Risk dashboard chart)
SELECT
    grade,
    loan_count,
    at_risk_count,
    at_risk_pct,
    avg_int_rate,
    avg_dti
FROM vw_risk_by_grade;


-- A-3: Grade vs DTI — 7×4 cross-tab showing at-risk % in every cell
SELECT
    g.grade,
    ROUND(100.0 * SUM(CASE WHEN f.dti_band='Low (0–10)'      THEN s.is_risk ELSE 0 END) /
          NULLIF(SUM(CASE WHEN f.dti_band='Low (0–10)'      THEN 1 ELSE 0 END), 0), 1)  AS `Low_DTI`,
    ROUND(100.0 * SUM(CASE WHEN f.dti_band='Medium (10–20)'  THEN s.is_risk ELSE 0 END) /
          NULLIF(SUM(CASE WHEN f.dti_band='Medium (10–20)'  THEN 1 ELSE 0 END), 0), 1)  AS `Medium_DTI`,
    ROUND(100.0 * SUM(CASE WHEN f.dti_band='High (20–30)'    THEN s.is_risk ELSE 0 END) /
          NULLIF(SUM(CASE WHEN f.dti_band='High (20–30)'    THEN 1 ELSE 0 END), 0), 1)  AS `High_DTI`,
    ROUND(100.0 * SUM(CASE WHEN f.dti_band='Very High (30+)' THEN s.is_risk ELSE 0 END) /
          NULLIF(SUM(CASE WHEN f.dti_band='Very High (30+)' THEN 1 ELSE 0 END), 0), 1)  AS `Very_High_DTI`
FROM fact_loans  f
JOIN dim_grade   g ON f.grade_key  = g.grade_key
JOIN dim_status  s ON f.status_key = s.status_key
GROUP BY g.grade
ORDER BY g.grade_num;


-- A-4: Loan purpose ranked by at-risk rate (descending)
SELECT
    purpose,
    loan_count,
    at_risk_count,
    at_risk_pct,
    avg_int_rate
FROM vw_risk_by_purpose
ORDER BY at_risk_pct DESC;


-- A-5: DTI band risk profile
SELECT
    dti_band,
    loan_count,
    at_risk_count,
    at_risk_pct,
    avg_dti
FROM vw_risk_by_dti
ORDER BY sort_order;


-- A-6: Loan status breakdown — full count and share
SELECT
    loan_status,
    is_risk,
    COUNT(*)                                              AS loan_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_portfolio
FROM vw_loan_detail
GROUP BY loan_status, is_risk
ORDER BY is_risk DESC, loan_count DESC;


-- A-7: Home ownership × risk — does ownership predict default?
SELECT
    home_ownership,
    COUNT(*)                                              AS loan_count,
    SUM(is_risk)                                          AS at_risk_count,
    ROUND(100.0 * SUM(is_risk) / COUNT(*), 2)            AS at_risk_pct,
    ROUND(AVG(int_rate), 2)                               AS avg_int_rate,
    ROUND(AVG(annual_inc_capped), 0)                      AS avg_income
FROM vw_loan_detail
GROUP BY home_ownership
ORDER BY at_risk_pct DESC;


-- A-8: Top 10 highest-risk individual loans (for a detail drillthrough table)
SELECT
    loan_id, grade, sub_grade, purpose, home_ownership,
    loan_amnt, int_rate, dti, loan_status, risk_label,
    repayment_progress_pct
FROM vw_loan_detail
WHERE is_risk = 1
ORDER BY int_rate DESC, dti DESC
LIMIT 10;


-- A-9: Delinquency × default — do past delinquencies predict current default?
SELECT
    CASE
        WHEN delinq_2yrs = 0 THEN '0 delinquencies'
        WHEN delinq_2yrs = 1 THEN '1 delinquency'
        WHEN delinq_2yrs = 2 THEN '2 delinquencies'
        ELSE '3+ delinquencies'
    END                                                   AS delinq_bucket,
    COUNT(*)                                              AS loan_count,
    SUM(is_risk)                                          AS at_risk_count,
    ROUND(100.0 * SUM(is_risk) / COUNT(*), 2)            AS at_risk_pct
FROM vw_loan_detail
GROUP BY delinq_bucket
ORDER BY MIN(delinq_2yrs);


-- A-10: Interest rate spread — current vs at-risk loans by grade
-- Shows whether pricing adequately compensates for realised default rates
SELECT
    grade,
    ROUND(AVG(CASE WHEN is_risk = 0 THEN int_rate END), 2)  AS avg_rate_current,
    ROUND(AVG(CASE WHEN is_risk = 1 THEN int_rate END), 2)  AS avg_rate_at_risk,
    ROUND(AVG(CASE WHEN is_risk = 1 THEN int_rate END)
        - AVG(CASE WHEN is_risk = 0 THEN int_rate END), 2)  AS rate_spread
FROM vw_loan_detail
GROUP BY grade
ORDER BY grade;


-- ============================================================================
-- SECTION B — BORROWER PROFILE  (who borrows)
-- ============================================================================

-- B-1: Borrower income distribution
SELECT
    income_band,
    COUNT(*)                                              AS borrower_count,
    ROUND(AVG(annual_inc_capped), 0)                      AS avg_income,
    ROUND(AVG(loan_amnt),         0)                      AS avg_loan_amnt,
    ROUND(AVG(loan_to_income_pct),1)                      AS avg_lti_pct
FROM vw_loan_detail
GROUP BY income_band
ORDER BY CASE income_band
    WHEN 'Under 30K'  THEN 1 WHEN '30–50K' THEN 2 WHEN '50–75K' THEN 3
    WHEN '75–100K'    THEN 4 ELSE 5 END;


-- B-2: Home ownership breakdown with share
SELECT
    home_ownership,
    COUNT(*)                                              AS borrower_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_portfolio,
    ROUND(AVG(annual_inc_capped), 0)                      AS avg_income,
    ROUND(AVG(loan_amnt),         0)                      AS avg_loan_amnt
FROM vw_loan_detail
GROUP BY home_ownership
ORDER BY borrower_count DESC;


-- B-3: Employment length distribution
SELECT
    emp_length,
    emp_length_num,
    COUNT(*)                                              AS borrower_count,
    ROUND(AVG(annual_inc_capped), 0)                      AS avg_income,
    ROUND(100.0 * SUM(is_risk) / COUNT(*), 2)            AS at_risk_pct
FROM vw_loan_detail
GROUP BY emp_length, emp_length_num
ORDER BY emp_length_num;


-- B-4: Loan purpose volume and average loan size
SELECT
    purpose,
    COUNT(*)                                              AS loan_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_portfolio,
    ROUND(AVG(loan_amnt), 0)                              AS avg_loan_amnt,
    ROUND(SUM(loan_amnt), 0)                              AS total_originated
FROM vw_loan_detail
GROUP BY purpose
ORDER BY loan_count DESC;


-- B-5: Loan size band distribution
SELECT
    loan_size_band,
    COUNT(*)                                              AS loan_count,
    ROUND(AVG(int_rate),   2)                             AS avg_int_rate,
    ROUND(AVG(dti),        2)                             AS avg_dti,
    ROUND(100.0 * SUM(is_risk) / COUNT(*), 2)            AS at_risk_pct
FROM vw_loan_detail
GROUP BY loan_size_band
ORDER BY CASE loan_size_band
    WHEN 'Small (<5K)'       THEN 1 WHEN 'Medium (5–10K)'    THEN 2
    WHEN 'Large (10–20K)'   THEN 3 ELSE 4 END;


-- ============================================================================
-- SECTION C — REPAYMENT & FINANCIAL  (how money flows)
-- ============================================================================

-- C-1: Portfolio-level financial KPIs
SELECT
    ROUND(SUM(loan_amnt),               0)  AS total_originated,
    ROUND(SUM(total_pymnt),             2)  AS total_collected,
    ROUND(SUM(total_rec_int),           2)  AS interest_earned,
    ROUND(SUM(total_rec_prncp),         2)  AS principal_received,
    ROUND(SUM(out_prncp),               2)  AS principal_outstanding,
    ROUND(SUM(recoveries),              2)  AS total_recoveries,
    ROUND(SUM(collection_recovery_fee), 2)  AS collection_fees,
    ROUND(AVG(repayment_progress_pct),  2)  AS avg_repayment_progress_pct,
    ROUND(100.0 * SUM(total_rec_prncp) /
          NULLIF(SUM(loan_amnt), 0),    2)  AS principal_recovery_rate_pct
FROM vw_loan_detail;


-- C-2: Interest earned by grade (revenue attribution)
SELECT
    grade,
    loan_count,
    total_originated,
    total_interest_earned,
    ROUND(100.0 * total_interest_earned /
          SUM(total_interest_earned) OVER (), 2)          AS interest_share_pct,
    avg_repayment_progress
FROM vw_repayment_by_grade
ORDER BY grade_num;


-- C-3: Quarterly payment trend
SELECT
    quarter_label,
    loan_count,
    total_originated,
    total_payments_received,
    interest_earned,
    recoveries
FROM vw_repayment_by_quarter
ORDER BY year, quarter_num;


-- C-4: At-risk loan financial exposure and recovery rate
SELECT
    ROUND(SUM(loan_amnt),     0)  AS at_risk_loan_value,
    ROUND(SUM(recoveries),    2)  AS recoveries_collected,
    ROUND(100.0 * SUM(recoveries) /
          NULLIF(SUM(loan_amnt), 0), 2)  AS recovery_rate_pct,
    COUNT(*)                      AS at_risk_loan_count
FROM vw_loan_detail
WHERE is_risk = 1;


-- C-5: Repayment progress distribution — bucket loans by how far along they are
SELECT
    CASE
        WHEN repayment_progress_pct <  20 THEN '0–20%'
        WHEN repayment_progress_pct <  40 THEN '20–40%'
        WHEN repayment_progress_pct <  60 THEN '40–60%'
        WHEN repayment_progress_pct <  80 THEN '60–80%'
        ELSE '80–100%'
    END                                                   AS progress_bucket,
    COUNT(*)                                              AS loan_count,
    ROUND(AVG(int_rate), 2)                               AS avg_int_rate,
    ROUND(100.0 * SUM(is_risk) / COUNT(*), 2)            AS at_risk_pct
FROM vw_loan_detail
GROUP BY progress_bucket
ORDER BY MIN(repayment_progress_pct);


-- C-6: Net yield proxy — interest earned as % of originations, by grade
SELECT
    grade,
    ROUND(SUM(total_rec_int), 2)    AS interest_earned,
    ROUND(SUM(loan_amnt),     0)    AS total_originated,
    ROUND(100.0 * SUM(total_rec_int) /
          NULLIF(SUM(loan_amnt), 0), 3)  AS yield_pct
FROM vw_loan_detail
GROUP BY grade, grade_num
ORDER BY grade_num;


-- C-7: Term length comparison — 36 vs 60 month economics
SELECT
    term_label,
    COUNT(*)                                              AS loan_count,
    ROUND(AVG(loan_amnt),              0)                 AS avg_loan_amnt,
    ROUND(AVG(int_rate),               2)                 AS avg_int_rate,
    ROUND(AVG(repayment_progress_pct), 2)                 AS avg_progress_pct,
    ROUND(100.0 * SUM(is_risk) / COUNT(*), 2)            AS at_risk_pct,
    ROUND(AVG(total_rec_int),          2)                 AS avg_interest_earned
FROM vw_loan_detail
GROUP BY term_label;

UPDATE vw_loan_detail
SET dti_band = 'Low (0-10)'
WHERE dti_band = 'Low (0â€"10)';
UPDATE vw_loan_detail
SET dti_band = 'Medium (10-20)'
WHERE dti_band = 'Medium (10â€"20)';

UPDATE vw_loan_detail
SET dti_band = 'High (20-30)'
WHERE dti_band = 'High (20â€"30)';

SELECT DISTINCT dti_band
FROM vw_loan_detail;
SHOW DATABASES;
SELECT dti_band, COUNT(*)
FROM fact_loans
GROUP BY dti_band;
SELECT DISTINCT dti_band
FROM fact_loans;
SET SQL_SAFE_UPDATES = 0;
UPDATE fact_loans
SET dti_band = REPLACE(dti_band, 'â€"', '-');
UPDATE fact_loans
SET dti_band = REPLACE(dti_band, 'â€“', '-');
SET SQL_SAFE_UPDATES = 1;
SELECT DISTINCT dti_band
FROM fact_loans;
SELECT COUNT(*) FROM fact_loans;
SELECT COUNT(*) FROM dim_date;
SELECT COUNT(*) FROM dim_grade;
SELECT COUNT(*) FROM dim_purpose;
SELECT COUNT(*) FROM dim_ownership;
SELECT COUNT(*) FROM dim_status;

SELECT DISTINCT dti_band
FROM fact_loans
ORDER BY dti_band;

SET SQL_SAFE_UPDATES = 0;

UPDATE fact_loans
SET income_band = '30-50K'
WHERE income_band LIKE '30%';

UPDATE fact_loans
SET income_band = '50-75K'
WHERE income_band LIKE '50%';

UPDATE fact_loans
SET income_band = '75-100K'
WHERE income_band LIKE '75%';

SET SQL_SAFE_UPDATES = 1;
SELECT DISTINCT income_band, HEX(income_band)
FROM fact_loans;

SET SQL_SAFE_UPDATES = 0;

UPDATE fact_loans
SET income_band = '30-50K'
WHERE income_band LIKE '30%';

UPDATE fact_loans
SET income_band = '50-75K'
WHERE income_band LIKE '50%';

UPDATE fact_loans
SET income_band = '75-100K'
WHERE income_band LIKE '75%';

SET SQL_SAFE_UPDATES = 1;
SET SQL_SAFE_UPDATES = 0;

UPDATE fact_loans
SET income_band = '30-50K'
WHERE loan_id IS NOT NULL
  AND income_band LIKE '30%';

UPDATE fact_loans
SET income_band = '50-75K'
WHERE loan_id IS NOT NULL
  AND income_band LIKE '50%';

UPDATE fact_loans
SET income_band = '75-100K'
WHERE loan_id IS NOT NULL
  AND income_band LIKE '75%';

SET SQL_SAFE_UPDATES = 1;
SELECT DISTINCT income_band
FROM fact_loans
ORDER BY income_band;
SELECT COUNT(*) FROM fact_loans;
SELECT loan_id, income_band
FROM fact_loans
WHERE income_band LIKE '30%';
SET SQL_SAFE_UPDATES = 0;

UPDATE fact_loans
SET income_band = 'TEST'
WHERE loan_id = (
    SELECT loan_id
    FROM (
        SELECT loan_id
        FROM fact_loans
        WHERE income_band LIKE '30%'
        LIMIT 1
    ) t
);

SET SQL_SAFE_UPDATES = 1;
SELECT loan_id, income_band
FROM fact_loans
WHERE income_band = 'TEST';