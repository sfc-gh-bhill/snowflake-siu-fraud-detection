-- =============================================================================
-- DST SIU NEXUS - CLAIMS DATA LOADING
-- =============================================================================
-- Loads the claims CSV into SIU_CLAIMS table.
-- HIGH_RISK_TAXONOMY is seeded directly in 05_claims_tables.sql via INSERT.
--
-- STEP 1: Upload CSV to stage using Snow CLI:
--   snow stage copy data/siu_claims.csv @DST_SIU_DB.RAW_DATA.SIU_DATA_STAGE/siu_claims/
--
-- STEP 2: Run the COPY INTO statement below.
-- =============================================================================

USE DATABASE DST_SIU_DB;
USE SCHEMA RAW_DATA;
USE WAREHOUSE DST_SIU_WH;

-- ============================================================================
-- LOAD SIU_CLAIMS
-- ============================================================================
TRUNCATE TABLE IF EXISTS SIU_CLAIMS;
COPY INTO SIU_CLAIMS (
    CLAIM_ID, CLAIM_LINE_NBR, PERSON_ID, SERVICE_DATE,
    AMOUNT_ALLOWED, AMOUNT_BILLED, AMOUNT_PAID,
    TIN, TIN_NAME, NPI, NPI_NAME,
    PROCEDURE_CODE, MODIFIER_1, MODIFIER_2, MODIFIER_3, MODIFIER_4,
    HIGH_RISK_CATEGORY, TIME_IN_MINUTES, TIME_IN_HOURS,
    ADDRESS_1, CITY, STATE, ZIP,
    LAT, LON, PLAN_TYPE
)
FROM @SIU_DATA_STAGE/siu_claims
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'CONTINUE';

-- ============================================================================
-- VERIFY LOAD
-- ============================================================================
SELECT 'SIU_CLAIMS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM SIU_CLAIMS
UNION ALL
SELECT 'HIGH_RISK_TAXONOMY', COUNT(*) FROM HIGH_RISK_TAXONOMY;

-- Quick sanity: fraud pattern presence
SELECT 'Temporal Impossibility Candidates' AS CHECK_NAME,
       COUNT(DISTINCT NPI || '|' || SERVICE_DATE::VARCHAR) AS COUNT_VAL
FROM (
    SELECT NPI, SERVICE_DATE, SUM(TIME_IN_MINUTES) AS TOTAL_MIN
    FROM SIU_CLAIMS
    WHERE TIME_IN_MINUTES IS NOT NULL
    GROUP BY NPI, SERVICE_DATE
    HAVING SUM(TIME_IN_MINUTES) > 1440
)
UNION ALL
SELECT 'EIDBI Providers with Claims',
       COUNT(DISTINCT NPI)
FROM SIU_CLAIMS WHERE HIGH_RISK_CATEGORY = 'EIDBI'
UNION ALL
SELECT 'Geospatial-Enabled Claims',
       COUNT(*)
FROM SIU_CLAIMS WHERE LAT IS NOT NULL AND LON IS NOT NULL;
