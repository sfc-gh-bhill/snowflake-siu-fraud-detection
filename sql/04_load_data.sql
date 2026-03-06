-- =============================================================================
-- DST SIU NEXUS - DATA LOADING
-- =============================================================================
-- Loads CSV data files into DST_SIU_DB.RAW_DATA tables.
--
-- STEP 1: Upload CSVs to stage using SnowSQL or Snow CLI (not web UI):
--   snow stage copy data/siu_cases.csv @DST_SIU_DB.RAW_DATA.SIU_DATA_STAGE/siu_cases/
--   (repeat for each file)
--
-- STEP 2: Run the COPY INTO statements below in Snowsight or SnowSQL.
--
-- Also uploads the semantic model YAML to YAML_STAGE.
-- =============================================================================

USE DATABASE DST_SIU_DB;
USE SCHEMA RAW_DATA;
USE WAREHOUSE DST_SIU_WH;

-- ============================================================================
-- STAGE UPLOAD COMMANDS (run from SnowSQL or Snow CLI)
-- ============================================================================
-- PUT file://data/siu_cases.csv @SIU_DATA_STAGE/siu_cases AUTO_COMPRESS=TRUE;
-- PUT file://data/siu_tipline_reports.csv @SIU_DATA_STAGE/siu_tipline_reports AUTO_COMPRESS=TRUE;
-- PUT file://data/siu_provider_risk_profiles.csv @SIU_DATA_STAGE/siu_provider_risk_profiles AUTO_COMPRESS=TRUE;
-- PUT file://data/siu_member_fraud_indicators.csv @SIU_DATA_STAGE/siu_member_fraud_indicators AUTO_COMPRESS=TRUE;
-- PUT file://data/siu_pharmacy_alerts.csv @SIU_DATA_STAGE/siu_pharmacy_alerts AUTO_COMPRESS=TRUE;
-- PUT file://data/siu_investigation_notes.csv @SIU_DATA_STAGE/siu_investigation_notes AUTO_COMPRESS=TRUE;
--
-- PUT file://semantic_model/siu_sentinel_semantic_model.yaml @DST_SIU_DB.SEMANTIC_MODELS.YAML_STAGE AUTO_COMPRESS=FALSE;

-- ============================================================================
-- LOAD SIU_CASES
-- ============================================================================
TRUNCATE TABLE IF EXISTS SIU_CASES;
COPY INTO SIU_CASES (
    CASE_ID, CASE_TYPE, SUBTYPE, SUBJECT_ID, SUBJECT_NAME,
    PLAN_TYPE, REGION, STATUS, PRIORITY, ESTIMATED_EXPOSURE,
    RECOVERED_AMOUNT, OPEN_DATE, CLOSE_DATE, ASSIGNED_INVESTIGATOR, REFERRAL_SOURCE
)
FROM @SIU_DATA_STAGE/siu_cases
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- ============================================================================
-- LOAD SIU_TIPLINE_REPORTS
-- ============================================================================
TRUNCATE TABLE IF EXISTS SIU_TIPLINE_REPORTS;
COPY INTO SIU_TIPLINE_REPORTS (
    TIP_ID, REPORT_DATE, REPORTER_TYPE, CASE_TYPE_ALLEGED,
    SUBJECT_DESCRIPTION, REGION, STATUS, LINKED_CASE_ID, URGENCY
)
FROM @SIU_DATA_STAGE/siu_tipline_reports
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- ============================================================================
-- LOAD SIU_PROVIDER_RISK_PROFILES
-- ============================================================================
TRUNCATE TABLE IF EXISTS SIU_PROVIDER_RISK_PROFILES;
COPY INTO SIU_PROVIDER_RISK_PROFILES (
    PROVIDER_NPI, PROVIDER_NAME, PROVIDER_NETWORK, SPECIALTY, REGION,
    CLAIM_COUNT_12M, TOTAL_BILLED_12M, TOTAL_PAID_12M, AVG_PAID_PER_CLAIM,
    PEER_AVG_PAID, PAID_ZSCORE, CLAIMS_PER_PATIENT, PEER_AVG_CLAIMS_PER_PATIENT,
    VOLUME_ZSCORE, DUPLICATE_CLAIM_RATE, DENIAL_RATE, CLEAN_CLAIM_RATE,
    COMPOSITE_RISK_SCORE, RISK_TIER, FWA_FLAGS, LAST_AUDIT_DATE, ACTIVE_CASES
)
FROM @SIU_DATA_STAGE/siu_provider_risk_profiles
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- ============================================================================
-- LOAD SIU_MEMBER_FRAUD_INDICATORS
-- ============================================================================
TRUNCATE TABLE IF EXISTS SIU_MEMBER_FRAUD_INDICATORS;
COPY INTO SIU_MEMBER_FRAUD_INDICATORS (
    MEMBER_ID, MEMBER_NAME, PLAN_TYPE, REGION, INDICATOR_TYPE,
    UNIQUE_PROVIDERS_90D, UNIQUE_PHARMACIES_90D, CONTROLLED_SUBSTANCE_RX_90D,
    ER_VISITS_90D, OVERLAPPING_ELIGIBILITY_FLAG, ADDRESS_CHANGE_FREQUENCY_12M,
    RISK_SCORE, RISK_TIER, ESTIMATED_EXPOSURE, LINKED_CASE_ID,
    DETECTION_DATE, DETECTION_METHOD
)
FROM @SIU_DATA_STAGE/siu_member_fraud_indicators
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- ============================================================================
-- LOAD SIU_PHARMACY_ALERTS
-- ============================================================================
TRUNCATE TABLE IF EXISTS SIU_PHARMACY_ALERTS;
COPY INTO SIU_PHARMACY_ALERTS (
    ALERT_ID, PHARMACY_ID, PHARMACY_NAME, REGION, ALERT_TYPE,
    DRUG_CATEGORY, METRIC_VALUE, PEER_BENCHMARK, DEVIATION_PERCENT,
    ALERT_DATE, STATUS, ESTIMATED_EXPOSURE, LINKED_CASE_ID, PRESCRIBER_NPI
)
FROM @SIU_DATA_STAGE/siu_pharmacy_alerts
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- ============================================================================
-- LOAD SIU_INVESTIGATION_NOTES
-- ============================================================================
TRUNCATE TABLE IF EXISTS SIU_INVESTIGATION_NOTES;
COPY INTO SIU_INVESTIGATION_NOTES (
    NOTE_ID, CASE_ID, NOTE_DATE, AUTHOR, NOTE_TYPE, NOTE_TEXT
)
FROM @SIU_DATA_STAGE/siu_investigation_notes
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- ============================================================================
-- VERIFY LOADS
-- ============================================================================
SELECT 'SIU_CASES' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM SIU_CASES
UNION ALL SELECT 'SIU_TIPLINE_REPORTS', COUNT(*) FROM SIU_TIPLINE_REPORTS
UNION ALL SELECT 'SIU_PROVIDER_RISK_PROFILES', COUNT(*) FROM SIU_PROVIDER_RISK_PROFILES
UNION ALL SELECT 'SIU_MEMBER_FRAUD_INDICATORS', COUNT(*) FROM SIU_MEMBER_FRAUD_INDICATORS
UNION ALL SELECT 'SIU_PHARMACY_ALERTS', COUNT(*) FROM SIU_PHARMACY_ALERTS
UNION ALL SELECT 'SIU_INVESTIGATION_NOTES', COUNT(*) FROM SIU_INVESTIGATION_NOTES;
