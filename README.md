# 🏦 Loan Portfolio Analytics — SQL & Power BI

End-to-end data engineering and business intelligence project on a **3,000-loan consumer lending portfolio worth $55.2M** in originations. Covers the full analytical stack: a normalised MySQL star schema, a structured SQL analysis layer with 20 analytical queries, and a three-page interactive Power BI dashboard backed by 46 DAX measures.

---

## 📋 Table of Contents

- [Project Overview](#project-overview)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [Database Architecture](#database-architecture)
- [SQL Analysis Layer](#sql-analysis-layer)
- [Power BI Dashboard](#power-bi-dashboard)
- [Key Findings](#key-findings)
---

## Project Overview

The raw source is a flat CSV of 3,000 rows and 39 columns — a typical export from a loan origination system. The project solves three problems that limit its analytical value in that form:

| Problem | Solution |
|---|---|
| **Redundancy** — borrower and loan metadata repeated on every row | Normalised into a Kimball star schema (1 fact + 5 dimensions) |
| **No integrity constraints** — invalid grades, statuses, dates can slip through | FK constraints, typed columns, and indexed joins enforce data quality |
| **No reusable analysis layer** — every analyst starts from scratch | 7 SQL views + 3 stored procedures give every BI tool a tested, version-controlled entry point |

**Business questions answered:**
1. 🔴 **Who defaults, and why?** — grade, DTI, and purpose drivers of credit risk
2. 🟡 **Who borrows?** — income, employment, and home ownership across the portfolio
3. 🟢 **How does money flow?** — interest earned, recoveries, and repayment progress

---

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Database | MySQL 8.0 | Star schema, FK constraints, indexes |
| ETL | Python (pandas, mysql-connector) | Load CSVs → MySQL with KPI sanity check |
| Analysis | SQL (views, stored procedures) | Reusable business logic layer |
| BI | Power BI Desktop + DAX | 3-page interactive dashboard |
| Schema design | Kimball star schema | Fact + 5 dimension tables |

---

## Repository Structure

```
loan-portfolio-analytics/
│
├── sql/
│   ├── 01_schema.sql               # CREATE DATABASE + all 6 tables with FK constraints
│   ├── 02_etl_load.py              # Python ETL — CSV → MySQL with sanity check
│   ├── 03_views.sql                # 7 reusable SQL views (abstraction layer)
│   ├── 04_analysis_queries.sql     # 20 annotated analytical queries
│   └── 05_stored_procedures.sql    # 3 parameterised stored procedures
│
├── powerbi/
│   ├── DAX_Measures.dax            # 46 DAX measures in 5 annotated sections
│   └── data/
│       ├── fact_loans.csv          # 3,000-row fact table
│       ├── dim_date.csv            # 24 distinct issue months
│       ├── dim_grade.csv           # 35 credit sub-grades (A1–G5)
│       ├── dim_purpose.csv         # 7 loan purposes
│       ├── dim_ownership.csv       # 3 home ownership types
│       └── dim_status.csv          # 6 loan statuses + is_risk flag
│
└── README.md
```

---

## Database Architecture

### Star Schema Design

```
                    ┌─────────────┐
                    │  dim_date   │
                    │─────────────│
                    │ date_key PK │
                    │ full_date   │
                    │ year        │
                    │ quarter     │
                    └──────┬──────┘
                           │
┌──────────────┐    ┌──────▼──────────────────────────────┐    ┌──────────────┐
│  dim_grade   │    │              fact_loans              │    │  dim_purpose │
│──────────────│    │──────────────────────────────────────│    │──────────────│
│ grade_key PK │◄───│ loan_id        PK                    │───►│ purpose_key  │
│ sub_grade    │    │ date_key       FK → dim_date         │    │ purpose      │
│ grade        │    │ grade_key      FK → dim_grade        │    └──────────────┘
│ grade_num    │    │ purpose_key    FK → dim_purpose      │
└──────────────┘    │ ownership_key  FK → dim_ownership    │    ┌──────────────┐
                    │ status_key     FK → dim_status       │    │ dim_ownership│
┌──────────────┐    │──────────────────────────────────────│    │──────────────│
│  dim_status  │    │ loan_amnt      DECIMAL(10,2)         │◄───│ ownership_key│
│──────────────│    │ int_rate       DECIMAL(5,2)          │    │ home_owner.. │
│ status_key PK│◄───│ dti            DECIMAL(6,2)          │    └──────────────┘
│ loan_status  │    │ total_pymnt    DECIMAL(12,2)         │
│ is_risk      │    │ total_rec_int  DECIMAL(12,2)         │
│ risk_label   │    │ recoveries     DECIMAL(12,2)         │
└──────────────┘    │ ... 20 more columns                  │
                    └──────────────────────────────────────┘

  6 tables   |   3,075 total rows   |   8 indexes on fact_loans
```

### Why Kimball Star Schema over a Flat Table?

**Storage & updates** — The `is_risk` flag lives once in `dim_status`. Reclassifying a loan status from non-risk to risk requires updating one row in one table, not scanning 3,000 fact rows.

**Query performance** — Power BI in DirectQuery mode issues a new SQL query on every slicer change. All 5 FK join columns in `fact_loans` are indexed, keeping joins fast as the dataset scales to millions of rows without restructuring.

**Semantic clarity** — Any query or DAX measure that needs to distinguish current from at-risk loans joins `dim_status` and reads the `is_risk` flag. The business definition lives in one place.

---

## SQL Analysis Layer

### The 7 Views (`03_views.sql`)

Views decouple the BI tool from the schema. Power BI connects to `vw_loan_detail` and knows nothing about the five-table join behind it. If the schema changes, only the affected view needs updating — the DAX measures and visuals remain untouched.

| View | Rows | Primary Use |
|---|---|---|
| `vw_risk_by_grade` | 7 | Grade bar chart + grade-level KPIs |
| `vw_risk_by_purpose` | 7 | Purpose bar chart sorted by at-risk rate |
| `vw_risk_by_dti` | 4 | DTI bar chart with manual sort order |
| `vw_borrower_profile` | 15 | Income band × ownership breakdown |
| `vw_repayment_by_grade` | 7 | Interest earned and progress by grade |
| `vw_repayment_by_quarter` | 8 | Quarterly payment trend line chart |
| `vw_loan_detail` | 3,000 | **Power BI import table + ad-hoc analysis base** |

### Highlight Queries (`04_analysis_queries.sql`)

#### A-1 — Portfolio KPI Snapshot

```sql
SELECT
    COUNT(*)                                              AS total_loans,
    SUM(is_risk)                                          AS at_risk_loans,
    ROUND(100.0 * SUM(is_risk) / COUNT(*), 2)            AS at_risk_pct,
    ROUND(AVG(int_rate),  2)                              AS avg_int_rate,
    ROUND(AVG(dti),       2)                              AS avg_dti,
    ROUND(SUM(loan_amnt), 0)                              AS total_originated_usd
FROM vw_loan_detail;
```

**Output:**
| total_loans | at_risk_loans | at_risk_pct | avg_int_rate | avg_dti | total_originated_usd |
|---|---|---|---|---|---|
| 3,000 | 218 | 7.27% | 20.36 | 20.25 | 55,211,100 |

---

#### A-3 — Grade × DTI Cross-Tab (Conditional Aggregation Pivot)

No temporary tables. No subqueries. No application-side pivoting. A single pass over the fact table produces the full 7×4 matrix.

```sql
SELECT
    g.grade,
    ROUND(100.0 * SUM(CASE WHEN f.dti_band='Low (0–10)'
          THEN s.is_risk ELSE 0 END) /
          NULLIF(SUM(CASE WHEN f.dti_band='Low (0–10)'
          THEN 1 ELSE 0 END), 0), 1)                      AS `Low_DTI`,
    ROUND(100.0 * SUM(CASE WHEN f.dti_band='Medium (10–20)'
          THEN s.is_risk ELSE 0 END) /
          NULLIF(SUM(CASE WHEN f.dti_band='Medium (10–20)'
          THEN 1 ELSE 0 END), 0), 1)                      AS `Medium_DTI`,
    ROUND(100.0 * SUM(CASE WHEN f.dti_band='High (20–30)'
          THEN s.is_risk ELSE 0 END) /
          NULLIF(SUM(CASE WHEN f.dti_band='High (20–30)'
          THEN 1 ELSE 0 END), 0), 1)                      AS `High_DTI`,
    ROUND(100.0 * SUM(CASE WHEN f.dti_band='Very High (30+)'
          THEN s.is_risk ELSE 0 END) /
          NULLIF(SUM(CASE WHEN f.dti_band='Very High (30+)'
          THEN 1 ELSE 0 END), 0), 1)                      AS `Very_High_DTI`
FROM fact_loans f
JOIN dim_grade  g ON f.grade_key  = g.grade_key
JOIN dim_status s ON f.status_key = s.status_key
GROUP BY g.grade ORDER BY g.grade_num;
```

**Output (at-risk % per cell):**
| Grade | Low DTI | Medium DTI | High DTI | Very High DTI |
|---|---|---|---|---|
| A | 0.0% | 1.4% | 0.7% | 3.4% |
| B | 4.8% | 1.5% | 4.5% | 7.6% |
| C | 1.9% | 6.1% | 3.4% | 7.3% |
| D | 3.5% | 8.9% | 10.7% | 12.1% |
| E | 15.4% | 15.5% | 13.6% | **15.6%** |
| F | 12.5% | 24.5% | 14.3% | 21.1% |
| G | 16.7% | 5.0% | 5.9% | **28.2%** |

> 💡 The G-grade + Very High DTI cell carries a **28.2% at-risk rate** — the highest-risk cohort in the portfolio and the first target for tightened underwriting.

---

#### A-6 — Loan Status Share with Window Function

```sql
SELECT
    loan_status,
    is_risk,
    COUNT(*)                                              AS loan_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_portfolio
FROM vw_loan_detail
GROUP BY loan_status, is_risk
ORDER BY is_risk DESC, loan_count DESC;
```

**Output:**
| loan_status | is_risk | loan_count | pct_of_portfolio |
|---|---|---|---|
| Current | 0 | 2,782 | 92.73% |
| Charged Off | 1 | 74 | 2.47% |
| Late (31–120 days) | 1 | 58 | 1.93% |
| Late (16–30 days) | 1 | 48 | 1.60% |
| In Grace Period | 1 | 19 | 0.63% |
| Default | 1 | 19 | 0.63% |

> `SUM(COUNT(*)) OVER ()` computes the denominator across all groups in one pass — no self-join, no CTE, no subquery.

---

#### A-10 — Interest Rate Spread: Pricing vs Realised Risk

```sql
SELECT
    grade,
    ROUND(AVG(CASE WHEN is_risk = 0 THEN int_rate END), 2)  AS avg_rate_current,
    ROUND(AVG(CASE WHEN is_risk = 1 THEN int_rate END), 2)  AS avg_rate_at_risk,
    ROUND(AVG(CASE WHEN is_risk = 1 THEN int_rate END)
        - AVG(CASE WHEN is_risk = 0 THEN int_rate END), 2)  AS rate_spread
FROM vw_loan_detail
GROUP BY grade ORDER BY grade;
```

> F and G grade at-risk loans carry rates only marginally higher than current loans in the same grade — despite defaulting at 18%+. The pricing model does not fully capture the risk cost of the lowest grades.

---

#### C-6 — Net Yield Proxy by Grade

```sql
SELECT
    grade,
    ROUND(SUM(total_rec_int), 2)    AS interest_earned,
    ROUND(SUM(loan_amnt),     0)    AS total_originated,
    ROUND(100.0 * SUM(total_rec_int) /
          NULLIF(SUM(loan_amnt), 0), 3)  AS yield_pct
FROM vw_loan_detail
GROUP BY grade, grade_num ORDER BY grade_num;
```

**Output:**
| Grade | Interest Earned | Total Originated | Yield % |
|---|---|---|---|
| A | $591,403 | $8,621,350 | 6.861% |
| B | **$894,783** | $12,660,850 | **7.068%** |
| C | $849,632 | $12,424,700 | 6.838% |
| D | $570,549 | $8,491,200 | 6.720% |
| E | $453,429 | $6,899,450 | 6.572% |
| F | $259,233 | $4,250,900 | 6.099% |
| G | $135,082 | $1,862,650 | 7.253% |

> B-grade generates the **most absolute interest income** ($894K) despite not having the highest rate — simply because it represents the largest volume segment. Revenue attribution requires volume × rate, not rate alone.

---

### Stored Procedures (`05_stored_procedures.sql`)

Three stored procedures package dashboard result sets into parameterisable calls. Each accepts an optional filter so a UI dropdown can drive the output.

```sql
-- All grades
CALL sp_risk_dashboard(NULL);

-- E-grade only — all 4 result sets filtered to E
CALL sp_risk_dashboard('E');

-- B-grade, 36-month loans
CALL sp_repayment_dashboard('B', 36);
```

| Procedure | Filter Parameter | Result Sets |
|---|---|---|
| `sp_risk_dashboard` | `p_grade` (A–G or NULL) | KPIs · by-grade · by-DTI · by-purpose |
| `sp_borrower_dashboard` | `p_ownership` (or NULL) | KPIs · income band · ownership · emp. length |
| `sp_repayment_dashboard` | `p_grade` + `p_term` (36/60) | KPIs · by-grade · by-quarter · exposure |

The `NULLIF(TRIM(p_grade), '')` pattern normalises both `NULL` and empty-string inputs so callers can pass either to get the unfiltered result.

---

## Power BI Dashboard

### Data Model

Power BI connects to MySQL via a **single import table**: `vw_loan_detail`. The star schema joins are already resolved in SQL — reimplementing them in Power BI's relationship editor adds complexity without benefit for this dataset.

```
MySQL (loan_portfolio db)
        │
        ▼
 vw_loan_detail          ← single flat view, 3,000 rows × 36 columns
        │
        ▼
  Power BI Import
        │
        ├── LoanDetail table
        └── _Measures table   ← 46 DAX measures, 5 sections
```

### DAX Measure Architecture

All 46 measures follow two consistent patterns:

**`DIVIDE()` everywhere** — never `/`. Division by zero returns `BLANK()` rather than an error, which Power BI handles gracefully when slicers produce empty filter contexts.

**`CALCULATE()` for context modification** — every measure that computes a filtered aggregate uses `CALCULATE()` explicitly rather than relying on implicit filter context, preventing the common DAX bug where a measure behaves correctly in a table but incorrectly under cross-filter.

```dax
-- Core KPI — used on every dashboard page
[At-Risk Rate %] =
DIVIDE( [At-Risk Loans], [Total Loans], 0 )

-- Context-modified measure — homeowner share regardless of slicer
[Homeowner Share %] =
DIVIDE(
    CALCULATE(
        COUNTROWS( LoanDetail ),
        LoanDetail[home_ownership] IN { "Own", "Mortgage" }
    ),
    COUNTROWS( LoanDetail ),
    0
)

-- Dynamic page title — updates when slicer selection changes
[Page Title – Risk] =
VAR sel = SELECTEDVALUE( LoanDetail[grade], "All Grades" )
RETURN "Risk Analysis — " & sel

-- Net yield proxy
[Portfolio Net Yield %] =
DIVIDE( [Total Interest Earned ($)], [Total Originated ($)], 0 )
```

| Section | Measures | Techniques used |
|---|---|---|
| Core KPIs | 15 | `DIVIDE`, `SUM`, `AVERAGE`, `COUNTROWS` |
| Risk Analysis | 10 | Conditional `CALCULATE`, `SWITCH` for flag labels |
| Borrower Profile | 8 | `IN` filter lists, `MEDIAN`, `[Income Band Rank]` sort |
| Repayment & Financial | 10 | `DIVIDE` for yield/recovery rates, period comparisons |
| Dynamic Titles | 3 | `SELECTEDVALUE` + string concatenation |

### Dashboard Pages

#### Page 1 — Risk Analysis
| Visual | Measure / Column | Insight |
|---|---|---|
| KPI Cards × 4 | `[Total Loans]`, `[At-Risk Loans]`, `[At-Risk Rate %]`, `[Avg Interest Rate %]` | Portfolio baseline |
| Grade bar chart | `[At-Risk Rate % by Grade]` by `grade` | 1.4% (A) → 18.2% (F) — 11× spread |
| Purpose bar chart | `[At-Risk Rate %]` by `purpose` | Home improvement 9.0% vs small business 3.7% |
| DTI band bar chart | `[At-Risk Rate %]` by `dti_band` | Very High DTI: 10.7% vs Low: 5.4% |
| Status donut | `[Total Loans]` by `loan_status` | 92.7% current / 7.3% at-risk |
| Slicer | `grade` (dropdown) | Drives all 4 charts + dynamic title |

#### Page 2 — Borrower Profile
| Visual | Measure / Column | Insight |
|---|---|---|
| KPI Cards × 4 | `[Total Borrowers]`, `[Avg Annual Income ($)]`, `[Avg Loan Amount ($)]`, `[Homeowner Share %]` | Portfolio baseline |
| Income band bar | `[Total Loans]` by `income_band` (sorted by `[Income Band Rank]`) | 50–75K is largest cohort (1,176 borrowers) |
| Ownership donut | `[Total Loans]` by `home_ownership` | Rent 44.8% · Mortgage 39.9% · Own 15.3% |
| Employment bar | `[Total Loans]` by `emp_length` (sorted by `emp_length_num`) | Evenly spread — tenure is a weak predictor |
| Purpose bar | `[Total Loans]` by `purpose` | Debt consolidation 40.3% — dominates all others |
| Slicer | `home_ownership` (dropdown) | Filters income, employment, KPI cards |

#### Page 3 — Repayment & Financial
| Visual | Measure / Column | Insight |
|---|---|---|
| KPI Cards × 4 | `[Total Originated ($)]`, `[Total Interest Earned ($)]`, `[Total Outstanding Principal ($)]`, `[Avg Repayment Progress %]` | Capital position |
| Interest by grade | `[Total Interest Earned ($)]` by `grade` | B-grade earns most ($894K) — volume × rate |
| Quarterly trend | `[Total Payments Received ($)]` by `issue_quarter` | $2.76M–$3.33M — stable collection curve |
| Progress by grade | `[Avg Repayment Progress %]` by `grade` | 36.8%–39.1% — portfolio still early in lifecycle |
| Principal donut | Received vs outstanding | $21.3M collected · $34.4M still outstanding |
| Slicer | `term_label` (36 / 60 months) | Compares 36 vs 60-month loan economics |

# 📊 Dashboard Preview

## 🔴 Risk Analysis

<img width="1193" height="673" alt="Screenshot 2026-06-23 205729" src="https://github.com/user-attachments/assets/6e8573cf-71be-40ba-9e9e-0d3dbe9b841a" />

---

## 🟡 Borrower Profile

<img width="1187" height="658" alt="Screenshot 2026-06-23 205747" src="https://github.com/user-attachments/assets/9bc33900-f11c-4f6f-a619-f43810cbe095" />

---

## 🟢 Repayment & Financial

<img width="1188" height="673" alt="Screenshot 2026-06-23 205757" src="https://github.com/user-attachments/assets/bbfc25c8-42b0-44f8-b493-a260fbc90f62" />

---

## Key Findings

### 🔴 Finding 1 — Grade is the dominant risk signal (11× spread)

At-risk rates climb monotonically from **A → F grade**, with an 11× spread that dwarfs every other variable:

| Grade | Loan Count | At-Risk Rate | Avg Interest Rate |
|---|---|---|---|
| A | 503 | **1.4%** | 17.0% |
| B | 693 | 4.5% | 18.5% |
| C | 683 | 4.5% | 20.2% |
| D | 447 | 9.2% | 21.9% |
| E | 349 | 14.9% | 22.9% |
| F | 214 | **18.2%** | 24.5% |
| G | 111 | 15.3% | 25.9% |

The rate spread between A and F (8.9pp) is far narrower than the default-rate spread (16.8pp), suggesting the lowest grades are under-priced relative to realised risk.

### 🟡 Finding 2 — DTI is a meaningful secondary screen

Borrowers with debt-to-income ratio above 30% default at **nearly double** the rate of the lowest-DTI cohort:

| DTI Band | Loan Count | At-Risk Rate |
|---|---|---|
| Low (0–10) | 634 | 5.4% |
| Medium (10–20) | 818 | 6.7% |
| High (20–30) | 855 | 6.4% |
| **Very High (30+)** | 693 | **10.7%** |

> A two-variable underwriting screen — grade first, then DTI — would reduce at-risk originations more than either variable alone.

### 🟢 Finding 3 — Recovery economics favour prevention over collection

| Metric | Value |
|---|---|
| At-risk loan value (218 loans) | $4,160,000 |
| Recoveries collected to date | $194,936 |
| **Recovery rate** | **4.7%** |
| Collection fees paid | $35,089 |

Every 1pp reduction in at-risk rate through better underwriting (~$414K in avoided exposure at current scale) is worth more than **all recovery activity combined**.

### 📈 Finding 4 — Quarterly payment trend is unexpectedly stable

Eight origination cohorts show payments ranging **$2.76M–$3.33M per quarter** — a band of less than 20% despite portfolio growth through 2024–2026.

| Quarter | Payments Received |
|---|---|
| 2024 Q3 | $3,115,951 |
| 2024 Q4 | $3,143,430 |
| 2025 Q1 | $3,312,209 |
| 2025 Q2 | $3,083,574 |
| 2025 Q3 | $3,327,973 |
| 2025 Q4 | $2,759,165 |
| 2026 Q1 | $3,236,624 |
| 2026 Q2 | $3,048,476 |

A sharp quarterly drop would be the first early-warning signal worth automating an alert around.

---

<div align="center">

**3,000 loans · $55.2M originated · 218 at-risk (7.3%) · $3.75M interest earned**

*MySQL · Python · Power BI · Kimball Star Schema · DAX*

</div>
