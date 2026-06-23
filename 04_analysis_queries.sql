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
