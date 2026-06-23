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
