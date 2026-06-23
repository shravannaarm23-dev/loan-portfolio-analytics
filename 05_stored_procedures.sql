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
