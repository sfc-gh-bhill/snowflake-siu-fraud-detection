# DST SIU Nexus — Cortex Code SKILL Context

## Project Overview
DST SIU Nexus is a Snowflake-native fraud detection platform for the client's Special Investigations Unit. It combines a Cortex Intelligence Agent (SIU_SENTINEL), Cortex Search over investigation notes/tipline reports, a claims-level anomaly detection engine using Dynamic Tables, and a Streamlit in Snowflake dashboard.

## Snowflake Objects

### Database: `DST_SIU_DB`
| Schema | Purpose |
|---|---|
| `RAW_DATA` | Source tables: SIU_CASES, SIU_TIPLINE_REPORTS, SIU_PROVIDER_RISK_PROFILES, SIU_MEMBER_FRAUD_INDICATORS, SIU_PHARMACY_ALERTS, SIU_INVESTIGATION_NOTES, SIU_CLAIMS, HIGH_RISK_TAXONOMY |
| `ANALYTICS` | Gold-layer views + Dynamic Tables for anomaly detection |
| `SEARCH` | Cortex Search services (SIU_INVESTIGATION_SEARCH, SIU_TIPLINE_SEARCH) |
| `SEMANTIC_MODELS` | YAML_STAGE with siu_sentinel_semantic_model.yaml |
| `AGENTS` | SIU_SENTINEL agent definition |

### Warehouse: `DST_SIU_WH` (XSMALL, auto_suspend=60)

### Key Dynamic Tables (in ANALYTICS schema)
- `DT_TEMPORAL_IMPOSSIBILITY` — Providers billing >24hrs/day
- `DT_EIDBI_RATIO_VIOLATIONS` — 97155 supervision >10% of 97153 direct
- `DT_SERVICE_OVERLAPS` — Same member, conflicting same-day services
- `DT_GEOSPATIAL_ANOMALIES` — Same-day services >50 miles apart (Haversine)
- `DT_DAILY_HOUR_VIOLATIONS` — Category-specific max daily hour breaches
- `DT_PROVIDER_BILLING_OUTLIERS` — Z-score outlier detection vs peers
- `ANOMALY_SUMMARY` — Unified triage view across all engines

### High-Risk Service Categories (16 types)
ACS, CFSS, HSS, NIGHT, ADC, NEMT, ARMHS, ACT, EIDBI, IRTS, PCA, SUD, UDT, EM + procedure codes mapped in HIGH_RISK_TAXONOMY table.

## Claims Schema (SIU_CLAIMS — 26 columns)
CLAIM_ID, CLAIM_LINE_NBR, PERSON_ID, SERVICE_DATE, AMOUNT_ALLOWED, AMOUNT_BILLED, AMOUNT_PAID, TIN, TIN_NAME, NPI, NPI_NAME, PROCEDURE_CODE, MODIFIER_1-4, HIGH_RISK_CATEGORY, TIME_IN_MINUTES, TIME_IN_HOURS, ADDRESS_1, CITY, STATE, ZIP, LAT, LON, PLAN_TYPE

## Streamlit App
- Location: `streamlit/streamlit_app.py`
- Deploy: `snow streamlit deploy --replace` from `streamlit/` directory
- Config: `streamlit/snowflake.yml` + `streamlit/environment.yml`
- Design: DST HUB palette (#1CA08E teal, #0D2B3E dark, WCAG AA)
- Pages: Anomaly Triage, Temporal Analysis, EIDBI Ratios, Service Overlaps, Geospatial, Claims Explorer, Case Overview

## Agent: SIU_SENTINEL
- Model: claude-4-sonnet
- Tools: Analyst (text-to-SQL), InvestigationSearch (cortex_search), TiplineSearch (cortex_search), data_to_chart
- Semantic model: `@DST_SIU_DB.SEMANTIC_MODELS.YAML_STAGE/siu_sentinel_semantic_model.yaml`

## Deployment Order
1. `sql/00_setup.sql` — Database, schemas, warehouse, stages
2. `sql/01_tables.sql` — Case management tables (6 tables)
3. `sql/05_claims_tables.sql` — Claims table + HIGH_RISK_TAXONOMY with seed data
4. Upload CSVs: `snow stage copy data/*.csv @DST_SIU_DB.RAW_DATA.SIU_DATA_STAGE/`
5. Upload YAML: `snow stage copy semantic_model/*.yaml @DST_SIU_DB.SEMANTIC_MODELS.YAML_STAGE/`
6. `sql/04_load_data.sql` — Load 6 investigation CSVs
7. `sql/07_load_claims.sql` — Load claims CSV
8. `sql/02_views.sql` — Gold-layer analytic views
9. `sql/06_anomaly_detection.sql` — Dynamic Tables (requires claims data loaded first)
10. `sql/03_cortex_search.sql` — Cortex Search services
11. `agent/create_siu_sentinel_agent.sql` — SIU_SENTINEL agent
12. Deploy Streamlit: `cd streamlit && snow streamlit deploy --replace`

## Synthetic Data
- 500 SIU cases, 200 tipline reports, 150 provider profiles, 300 member indicators, 250 pharmacy alerts, 500 investigation notes
- 4,699 claims with 5 seeded fraud patterns: temporal impossibility (10 providers), EIDBI ratio violations (5 providers), service overlaps (40 member-days), geospatial anomalies (30 pairs), daily hour violations (30 claims)
- All generated with `random.seed(42)` for reproducibility

## Key Business Rules
- EIDBI: 97155 supervision must be <=10% of 97153 direct service hours per provider per month
- Temporal: No provider can legitimately bill >24 hours in one calendar day
- IRTS: Limited to 1 unit per day per member (H0019)
- ACT: 1 per diem per day per member (H0040)
- Geospatial: Same-day services >50 miles apart flag for investigation
- Plan types: Plan types and financial details configured per client
