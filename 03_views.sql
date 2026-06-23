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
