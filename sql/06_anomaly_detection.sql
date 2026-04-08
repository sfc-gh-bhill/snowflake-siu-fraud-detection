-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Braedon Hill

-- =============================================================================
-- DST SIU NEXUS - ANOMALY DETECTION ENGINE (Dynamic Tables)
-- =============================================================================
-- Phase 2: Continuously refreshing Dynamic Tables implementing the core
-- fraud detection rules from the SIU architecture plan:
--   1. Temporal Impossibility (>24 hrs/day billed)
--   2. EIDBI 10% Supervision Ratio (97155/97153 <= 10%)
--   3. Service Overlap Detection (same member, overlapping times)
--   4. Geospatial Distance Outliers (as-the-crow-flies)
--   5. Daily "99" Series Hour Aggregations
--   6. Provider Billing Pattern Consistency
-- =============================================================================

USE DATABASE DST_SIU_DB;
USE SCHEMA ANALYTICS;
USE WAREHOUSE DST_SIU_WH;

-- ============================================================================
-- 1. TEMPORAL IMPOSSIBILITY: Providers billing > 24 hours in a single day
-- ============================================================================
-- Aggregates TIME_IN_HOURS by NPI + SERVICE_DATE. Any day exceeding 24 hours
-- is biologically impossible and a strong fraud signal.
-- ============================================================================
CREATE OR REPLACE DYNAMIC TABLE DT_TEMPORAL_IMPOSSIBILITY
  TARGET_LAG = '1 hour'
  WAREHOUSE = DST_SIU_WH
  COMMENT = 'Detects providers billing more than 24 hours of services in a single calendar day'
AS
SELECT
    NPI,
    NPI_NAME,
    TIN,
    TIN_NAME,
    SERVICE_DATE,
    HIGH_RISK_CATEGORY,
    COUNT(DISTINCT PERSON_ID) AS UNIQUE_MEMBERS_SERVED,
    COUNT(*) AS CLAIM_LINE_COUNT,
    SUM(TIME_IN_MINUTES) AS TOTAL_MINUTES,
    ROUND(SUM(TIME_IN_MINUTES) / 60.0, 2) AS TOTAL_HOURS,
    SUM(AMOUNT_PAID) AS TOTAL_PAID,
    SUM(AMOUNT_ALLOWED) AS TOTAL_ALLOWED,
    CASE
        WHEN SUM(TIME_IN_MINUTES) > 1440 THEN 'CRITICAL'   -- >24 hrs
        WHEN SUM(TIME_IN_MINUTES) > 1200 THEN 'HIGH'       -- >20 hrs
        WHEN SUM(TIME_IN_MINUTES) > 960  THEN 'MEDIUM'     -- >16 hrs
        ELSE 'LOW'
    END AS SEVERITY,
    CURRENT_TIMESTAMP() AS DETECTED_AT
FROM DST_SIU_DB.RAW_DATA.SIU_CLAIMS
WHERE TIME_IN_MINUTES IS NOT NULL
  AND TIME_IN_MINUTES > 0
GROUP BY NPI, NPI_NAME, TIN, TIN_NAME, SERVICE_DATE, HIGH_RISK_CATEGORY
HAVING SUM(TIME_IN_MINUTES) > 960;  -- Flag anything over 16 hours

-- ============================================================================
-- 2. EIDBI SUPERVISION RATIO: 97155 must be <= 10% of 97153 direct hours
-- ============================================================================
-- Per state regulatory rules, EIDBI supervision (97155 by QSP) cannot exceed 10% of
-- direct service hours (97153 by technician) per provider per month.
-- ============================================================================
CREATE OR REPLACE DYNAMIC TABLE DT_EIDBI_RATIO_VIOLATIONS
  TARGET_LAG = '1 hour'
  WAREHOUSE = DST_SIU_WH
  COMMENT = 'Detects EIDBI providers where supervision code 97155 exceeds 10% of direct service code 97153'
AS
WITH monthly_eidbi AS (
    SELECT
        NPI,
        NPI_NAME,
        TIN,
        TIN_NAME,
        DATE_TRUNC('month', SERVICE_DATE) AS SERVICE_MONTH,
        SUM(CASE WHEN PROCEDURE_CODE = '97153' THEN TIME_IN_MINUTES ELSE 0 END) AS DIRECT_MINUTES_97153,
        SUM(CASE WHEN PROCEDURE_CODE = '97155' THEN TIME_IN_MINUTES ELSE 0 END) AS SUPERVISION_MINUTES_97155,
        SUM(CASE WHEN PROCEDURE_CODE = '97153' THEN AMOUNT_PAID ELSE 0 END) AS DIRECT_PAID_97153,
        SUM(CASE WHEN PROCEDURE_CODE = '97155' THEN AMOUNT_PAID ELSE 0 END) AS SUPERVISION_PAID_97155,
        COUNT(DISTINCT CASE WHEN PROCEDURE_CODE = '97153' THEN PERSON_ID END) AS DIRECT_MEMBER_COUNT,
        COUNT(DISTINCT CASE WHEN PROCEDURE_CODE = '97155' THEN PERSON_ID END) AS SUPERVISION_MEMBER_COUNT
    FROM DST_SIU_DB.RAW_DATA.SIU_CLAIMS
    WHERE PROCEDURE_CODE IN ('97153', '97155')
      AND HIGH_RISK_CATEGORY = 'EIDBI'
    GROUP BY NPI, NPI_NAME, TIN, TIN_NAME, DATE_TRUNC('month', SERVICE_DATE)
)
SELECT
    NPI,
    NPI_NAME,
    TIN,
    TIN_NAME,
    SERVICE_MONTH,
    DIRECT_MINUTES_97153,
    SUPERVISION_MINUTES_97155,
    ROUND(DIRECT_MINUTES_97153 / 60.0, 2) AS DIRECT_HOURS_97153,
    ROUND(SUPERVISION_MINUTES_97155 / 60.0, 2) AS SUPERVISION_HOURS_97155,
    CASE
        WHEN DIRECT_MINUTES_97153 > 0
        THEN ROUND(SUPERVISION_MINUTES_97155 * 100.0 / DIRECT_MINUTES_97153, 2)
        ELSE NULL
    END AS SUPERVISION_RATIO_PCT,
    DIRECT_PAID_97153,
    SUPERVISION_PAID_97155,
    DIRECT_MEMBER_COUNT,
    SUPERVISION_MEMBER_COUNT,
    CASE
        WHEN DIRECT_MINUTES_97153 = 0 AND SUPERVISION_MINUTES_97155 > 0 THEN 'CRITICAL'
        WHEN DIRECT_MINUTES_97153 > 0 AND (SUPERVISION_MINUTES_97155 * 100.0 / DIRECT_MINUTES_97153) > 25 THEN 'CRITICAL'
        WHEN DIRECT_MINUTES_97153 > 0 AND (SUPERVISION_MINUTES_97155 * 100.0 / DIRECT_MINUTES_97153) > 15 THEN 'HIGH'
        WHEN DIRECT_MINUTES_97153 > 0 AND (SUPERVISION_MINUTES_97155 * 100.0 / DIRECT_MINUTES_97153) > 10 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS SEVERITY,
    CURRENT_TIMESTAMP() AS DETECTED_AT
FROM monthly_eidbi
WHERE DIRECT_MINUTES_97153 = 0 AND SUPERVISION_MINUTES_97155 > 0  -- Supervision with no direct = critical
   OR (DIRECT_MINUTES_97153 > 0 AND SUPERVISION_MINUTES_97155 * 100.0 / DIRECT_MINUTES_97153 > 10);

-- ============================================================================
-- 3. SERVICE OVERLAP DETECTION: Same member receiving overlapping services
-- ============================================================================
-- Detects when a single member has claims from different providers on the
-- same day for services that cannot logically co-occur (e.g., ADC + PCA,
-- IRTS at two facilities).
-- ============================================================================
CREATE OR REPLACE DYNAMIC TABLE DT_SERVICE_OVERLAPS
  TARGET_LAG = '1 hour'
  WAREHOUSE = DST_SIU_WH
  COMMENT = 'Detects same-member same-day service overlaps that indicate billing fraud or coordination failures'
AS
WITH daily_services AS (
    SELECT
        PERSON_ID,
        SERVICE_DATE,
        NPI,
        NPI_NAME,
        TIN,
        TIN_NAME,
        HIGH_RISK_CATEGORY,
        PROCEDURE_CODE,
        TIME_IN_MINUTES,
        AMOUNT_PAID,
        CLAIM_ID,
        CLAIM_LINE_NBR
    FROM DST_SIU_DB.RAW_DATA.SIU_CLAIMS
    WHERE HIGH_RISK_CATEGORY IS NOT NULL
      AND TIME_IN_MINUTES > 0
),
overlap_pairs AS (
    SELECT
        a.PERSON_ID,
        a.SERVICE_DATE,
        a.NPI AS NPI_A,
        a.NPI_NAME AS NPI_NAME_A,
        a.HIGH_RISK_CATEGORY AS CATEGORY_A,
        a.PROCEDURE_CODE AS PROC_CODE_A,
        a.TIME_IN_MINUTES AS MINUTES_A,
        a.AMOUNT_PAID AS PAID_A,
        b.NPI AS NPI_B,
        b.NPI_NAME AS NPI_NAME_B,
        b.HIGH_RISK_CATEGORY AS CATEGORY_B,
        b.PROCEDURE_CODE AS PROC_CODE_B,
        b.TIME_IN_MINUTES AS MINUTES_B,
        b.AMOUNT_PAID AS PAID_B
    FROM daily_services a
    INNER JOIN daily_services b
        ON a.PERSON_ID = b.PERSON_ID
        AND a.SERVICE_DATE = b.SERVICE_DATE
        AND (a.CLAIM_ID || '-' || a.CLAIM_LINE_NBR) < (b.CLAIM_ID || '-' || b.CLAIM_LINE_NBR)
    WHERE (a.TIME_IN_MINUTES + b.TIME_IN_MINUTES) > 1440  -- Combined > 24 hrs
       OR (a.HIGH_RISK_CATEGORY = 'IRTS' AND b.HIGH_RISK_CATEGORY = 'IRTS')  -- IRTS at two facilities
       OR (a.HIGH_RISK_CATEGORY = 'ADC' AND b.HIGH_RISK_CATEGORY IN ('PCA', 'ACS'))  -- ADC + in-home
       OR (a.HIGH_RISK_CATEGORY = 'ACT' AND b.HIGH_RISK_CATEGORY = 'ACT')  -- Multiple ACT per diems
)
SELECT
    PERSON_ID,
    SERVICE_DATE,
    NPI_A,
    NPI_NAME_A,
    CATEGORY_A,
    PROC_CODE_A,
    MINUTES_A,
    PAID_A,
    NPI_B,
    NPI_NAME_B,
    CATEGORY_B,
    PROC_CODE_B,
    MINUTES_B,
    PAID_B,
    (MINUTES_A + MINUTES_B) AS COMBINED_MINUTES,
    ROUND((MINUTES_A + MINUTES_B) / 60.0, 2) AS COMBINED_HOURS,
    (PAID_A + PAID_B) AS COMBINED_PAID,
    CASE
        WHEN CATEGORY_A = 'IRTS' AND CATEGORY_B = 'IRTS' THEN 'CRITICAL'
        WHEN (MINUTES_A + MINUTES_B) > 1440 THEN 'CRITICAL'
        WHEN CATEGORY_A = 'ACT' AND CATEGORY_B = 'ACT' THEN 'HIGH'
        ELSE 'MEDIUM'
    END AS SEVERITY,
    CURRENT_TIMESTAMP() AS DETECTED_AT
FROM overlap_pairs;

-- ============================================================================
-- 4. GEOSPATIAL DISTANCE OUTLIERS: "As the crow flies" distance analysis
-- ============================================================================
-- Calculates straight-line distance between a member's service locations
-- on the same day. Flags providers billing for members far from their
-- service area or members receiving services at impossibly distant locations.
-- Uses Haversine formula for great-circle distance.
-- ============================================================================
CREATE OR REPLACE DYNAMIC TABLE DT_GEOSPATIAL_ANOMALIES
  TARGET_LAG = '1 hour'
  WAREHOUSE = DST_SIU_WH
  COMMENT = 'Detects geospatial anomalies where same-day services occur at impossibly distant locations'
AS
WITH geo_claims AS (
    SELECT
        PERSON_ID,
        SERVICE_DATE,
        NPI,
        NPI_NAME,
        TIN,
        TIN_NAME,
        HIGH_RISK_CATEGORY,
        LAT,
        LON,
        AMOUNT_PAID,
        CLAIM_ID,
        CLAIM_LINE_NBR,
        CITY,
        ZIP
    FROM DST_SIU_DB.RAW_DATA.SIU_CLAIMS
    WHERE LAT IS NOT NULL
      AND LON IS NOT NULL
      AND LAT BETWEEN 43.0 AND 49.5  -- Regional latitude bounds
      AND LON BETWEEN -97.5 AND -89.0  -- Regional longitude bounds
),
distance_pairs AS (
    SELECT
        a.PERSON_ID,
        a.SERVICE_DATE,
        a.NPI AS NPI_A,
        a.NPI_NAME AS NPI_NAME_A,
        a.CITY AS CITY_A,
        a.ZIP AS ZIP_A,
        a.LAT AS LAT_A,
        a.LON AS LON_A,
        b.NPI AS NPI_B,
        b.NPI_NAME AS NPI_NAME_B,
        b.CITY AS CITY_B,
        b.ZIP AS ZIP_B,
        b.LAT AS LAT_B,
        b.LON AS LON_B,
        a.HIGH_RISK_CATEGORY AS CATEGORY_A,
        b.HIGH_RISK_CATEGORY AS CATEGORY_B,
        a.AMOUNT_PAID AS PAID_A,
        b.AMOUNT_PAID AS PAID_B,
        -- Haversine formula: distance in miles
        ROUND(
            3958.8 * 2 * ASIN(SQRT(
                POWER(SIN(RADIANS(b.LAT - a.LAT) / 2), 2) +
                COS(RADIANS(a.LAT)) * COS(RADIANS(b.LAT)) *
                POWER(SIN(RADIANS(b.LON - a.LON) / 2), 2)
            )), 2
        ) AS DISTANCE_MILES
    FROM geo_claims a
    INNER JOIN geo_claims b
        ON a.PERSON_ID = b.PERSON_ID
        AND a.SERVICE_DATE = b.SERVICE_DATE
        AND (a.CLAIM_ID || '-' || a.CLAIM_LINE_NBR) < (b.CLAIM_ID || '-' || b.CLAIM_LINE_NBR)
        AND a.NPI != b.NPI  -- Different providers
)
SELECT
    PERSON_ID,
    SERVICE_DATE,
    NPI_A,
    NPI_NAME_A,
    CITY_A,
    ZIP_A,
    NPI_B,
    NPI_NAME_B,
    CITY_B,
    ZIP_B,
    CATEGORY_A,
    CATEGORY_B,
    DISTANCE_MILES,
    (PAID_A + PAID_B) AS COMBINED_PAID,
    CASE
        WHEN DISTANCE_MILES > 200 THEN 'CRITICAL'
        WHEN DISTANCE_MILES > 100 THEN 'HIGH'
        WHEN DISTANCE_MILES > 50  THEN 'MEDIUM'
        ELSE 'LOW'
    END AS SEVERITY,
    CURRENT_TIMESTAMP() AS DETECTED_AT
FROM distance_pairs
WHERE DISTANCE_MILES > 50;  -- Flag same-day services > 50 miles apart

-- ============================================================================
-- 5. DAILY HOUR AGGREGATION BY CATEGORY: "99-series" and high-risk rollups
-- ============================================================================
-- Aggregates daily hours per provider per high-risk category, comparing
-- against the MAX_DAILY_HOURS defined in the taxonomy reference table.
-- ============================================================================
CREATE OR REPLACE DYNAMIC TABLE DT_DAILY_HOUR_VIOLATIONS
  TARGET_LAG = '1 hour'
  WAREHOUSE = DST_SIU_WH
  COMMENT = 'Flags providers exceeding maximum daily hours per high-risk service category per taxonomy rules'
AS
SELECT
    c.NPI,
    c.NPI_NAME,
    c.TIN,
    c.TIN_NAME,
    c.SERVICE_DATE,
    c.HIGH_RISK_CATEGORY,
    t.CATEGORY_NAME,
    t.MAX_DAILY_HOURS,
    COUNT(DISTINCT c.PERSON_ID) AS UNIQUE_MEMBERS,
    COUNT(*) AS CLAIM_LINES,
    SUM(c.TIME_IN_MINUTES) AS TOTAL_MINUTES,
    ROUND(SUM(c.TIME_IN_MINUTES) / 60.0, 2) AS TOTAL_HOURS,
    SUM(c.AMOUNT_PAID) AS TOTAL_PAID,
    ROUND(SUM(c.TIME_IN_MINUTES) / 60.0, 2) - t.MAX_DAILY_HOURS AS HOURS_OVER_LIMIT,
    CASE
        WHEN SUM(c.TIME_IN_MINUTES) / 60.0 > t.MAX_DAILY_HOURS * 1.5 THEN 'CRITICAL'
        WHEN SUM(c.TIME_IN_MINUTES) / 60.0 > t.MAX_DAILY_HOURS * 1.25 THEN 'HIGH'
        WHEN SUM(c.TIME_IN_MINUTES) / 60.0 > t.MAX_DAILY_HOURS THEN 'MEDIUM'
        ELSE 'LOW'
    END AS SEVERITY,
    CURRENT_TIMESTAMP() AS DETECTED_AT
FROM DST_SIU_DB.RAW_DATA.SIU_CLAIMS c
INNER JOIN DST_SIU_DB.RAW_DATA.HIGH_RISK_TAXONOMY t
    ON c.HIGH_RISK_CATEGORY = t.CATEGORY_CODE
    AND c.PROCEDURE_CODE = t.PROCEDURE_CODE
WHERE c.TIME_IN_MINUTES IS NOT NULL
  AND c.TIME_IN_MINUTES > 0
  AND t.MAX_DAILY_HOURS IS NOT NULL
GROUP BY c.NPI, c.NPI_NAME, c.TIN, c.TIN_NAME, c.SERVICE_DATE,
         c.HIGH_RISK_CATEGORY, t.CATEGORY_NAME, t.MAX_DAILY_HOURS
HAVING SUM(c.TIME_IN_MINUTES) / 60.0 > t.MAX_DAILY_HOURS;

-- ============================================================================
-- 6. PROVIDER BILLING PATTERN CONSISTENCY: Statistical outlier detection
-- ============================================================================
-- Computes per-provider billing metrics and flags those with Z-scores
-- significantly above their peer group (same HIGH_RISK_CATEGORY).
-- ============================================================================
CREATE OR REPLACE DYNAMIC TABLE DT_PROVIDER_BILLING_OUTLIERS
  TARGET_LAG = '1 hour'
  WAREHOUSE = DST_SIU_WH
  COMMENT = 'Statistical outlier detection comparing provider billing patterns against category peers'
AS
WITH provider_metrics AS (
    SELECT
        NPI,
        NPI_NAME,
        TIN,
        TIN_NAME,
        HIGH_RISK_CATEGORY,
        COUNT(*) AS TOTAL_CLAIMS,
        COUNT(DISTINCT PERSON_ID) AS UNIQUE_MEMBERS,
        SUM(AMOUNT_PAID) AS TOTAL_PAID,
        AVG(AMOUNT_PAID) AS AVG_PAID_PER_LINE,
        SUM(TIME_IN_MINUTES) AS TOTAL_MINUTES,
        COUNT(DISTINCT SERVICE_DATE) AS ACTIVE_DAYS
    FROM DST_SIU_DB.RAW_DATA.SIU_CLAIMS
    WHERE HIGH_RISK_CATEGORY IS NOT NULL
    GROUP BY NPI, NPI_NAME, TIN, TIN_NAME, HIGH_RISK_CATEGORY
),
peer_stats AS (
    SELECT
        HIGH_RISK_CATEGORY,
        AVG(TOTAL_PAID) AS PEER_AVG_PAID,
        STDDEV(TOTAL_PAID) AS PEER_STDDEV_PAID,
        AVG(TOTAL_CLAIMS) AS PEER_AVG_CLAIMS,
        STDDEV(TOTAL_CLAIMS) AS PEER_STDDEV_CLAIMS,
        AVG(TOTAL_MINUTES) AS PEER_AVG_MINUTES,
        STDDEV(TOTAL_MINUTES) AS PEER_STDDEV_MINUTES,
        COUNT(*) AS PEER_COUNT
    FROM provider_metrics
    GROUP BY HIGH_RISK_CATEGORY
    HAVING COUNT(*) >= 3  -- Need at least 3 peers for meaningful stats
)
SELECT
    pm.NPI,
    pm.NPI_NAME,
    pm.TIN,
    pm.TIN_NAME,
    pm.HIGH_RISK_CATEGORY,
    pm.TOTAL_CLAIMS,
    pm.UNIQUE_MEMBERS,
    pm.TOTAL_PAID,
    pm.AVG_PAID_PER_LINE,
    pm.TOTAL_MINUTES,
    pm.ACTIVE_DAYS,
    ps.PEER_AVG_PAID,
    ps.PEER_COUNT,
    CASE WHEN ps.PEER_STDDEV_PAID > 0
         THEN ROUND((pm.TOTAL_PAID - ps.PEER_AVG_PAID) / ps.PEER_STDDEV_PAID, 2)
         ELSE 0
    END AS PAID_ZSCORE,
    CASE WHEN ps.PEER_STDDEV_CLAIMS > 0
         THEN ROUND((pm.TOTAL_CLAIMS - ps.PEER_AVG_CLAIMS) / ps.PEER_STDDEV_CLAIMS, 2)
         ELSE 0
    END AS VOLUME_ZSCORE,
    CASE WHEN ps.PEER_STDDEV_MINUTES > 0
         THEN ROUND((pm.TOTAL_MINUTES - ps.PEER_AVG_MINUTES) / ps.PEER_STDDEV_MINUTES, 2)
         ELSE 0
    END AS TIME_ZSCORE,
    CASE
        WHEN GREATEST(
            ABS(CASE WHEN ps.PEER_STDDEV_PAID > 0 THEN (pm.TOTAL_PAID - ps.PEER_AVG_PAID) / ps.PEER_STDDEV_PAID ELSE 0 END),
            ABS(CASE WHEN ps.PEER_STDDEV_CLAIMS > 0 THEN (pm.TOTAL_CLAIMS - ps.PEER_AVG_CLAIMS) / ps.PEER_STDDEV_CLAIMS ELSE 0 END)
        ) > 3.0 THEN 'CRITICAL'
        WHEN GREATEST(
            ABS(CASE WHEN ps.PEER_STDDEV_PAID > 0 THEN (pm.TOTAL_PAID - ps.PEER_AVG_PAID) / ps.PEER_STDDEV_PAID ELSE 0 END),
            ABS(CASE WHEN ps.PEER_STDDEV_CLAIMS > 0 THEN (pm.TOTAL_CLAIMS - ps.PEER_AVG_CLAIMS) / ps.PEER_STDDEV_CLAIMS ELSE 0 END)
        ) > 2.5 THEN 'HIGH'
        WHEN GREATEST(
            ABS(CASE WHEN ps.PEER_STDDEV_PAID > 0 THEN (pm.TOTAL_PAID - ps.PEER_AVG_PAID) / ps.PEER_STDDEV_PAID ELSE 0 END),
            ABS(CASE WHEN ps.PEER_STDDEV_CLAIMS > 0 THEN (pm.TOTAL_CLAIMS - ps.PEER_AVG_CLAIMS) / ps.PEER_STDDEV_CLAIMS ELSE 0 END)
        ) > 2.0 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS SEVERITY,
    CURRENT_TIMESTAMP() AS DETECTED_AT
FROM provider_metrics pm
INNER JOIN peer_stats ps ON pm.HIGH_RISK_CATEGORY = ps.HIGH_RISK_CATEGORY
WHERE CASE WHEN ps.PEER_STDDEV_PAID > 0
           THEN ABS((pm.TOTAL_PAID - ps.PEER_AVG_PAID) / ps.PEER_STDDEV_PAID)
           ELSE 0
      END > 2.0
   OR CASE WHEN ps.PEER_STDDEV_CLAIMS > 0
           THEN ABS((pm.TOTAL_CLAIMS - ps.PEER_AVG_CLAIMS) / ps.PEER_STDDEV_CLAIMS)
           ELSE 0
      END > 2.0;

-- ============================================================================
-- 7. ANOMALY SUMMARY: Unified triage view across all detection engines
-- ============================================================================
CREATE OR REPLACE VIEW ANOMALY_SUMMARY AS
SELECT 'Temporal Impossibility' AS ANOMALY_TYPE, NPI, NPI_NAME, TIN, SERVICE_DATE::VARCHAR AS DETAIL_DATE, SEVERITY, TOTAL_PAID AS FINANCIAL_IMPACT, DETECTED_AT FROM DT_TEMPORAL_IMPOSSIBILITY
UNION ALL
SELECT 'EIDBI Ratio Violation', NPI, NPI_NAME, TIN, SERVICE_MONTH::VARCHAR, SEVERITY, SUPERVISION_PAID_97155, DETECTED_AT FROM DT_EIDBI_RATIO_VIOLATIONS
UNION ALL
SELECT 'Service Overlap', NPI_A, NPI_NAME_A, NULL, SERVICE_DATE::VARCHAR, SEVERITY, COMBINED_PAID, DETECTED_AT FROM DT_SERVICE_OVERLAPS
UNION ALL
SELECT 'Geospatial Anomaly', NPI_A, NPI_NAME_A, NULL, SERVICE_DATE::VARCHAR, SEVERITY, COMBINED_PAID, DETECTED_AT FROM DT_GEOSPATIAL_ANOMALIES
UNION ALL
SELECT 'Daily Hour Violation', NPI, NPI_NAME, TIN, SERVICE_DATE::VARCHAR, SEVERITY, TOTAL_PAID, DETECTED_AT FROM DT_DAILY_HOUR_VIOLATIONS
UNION ALL
SELECT 'Billing Pattern Outlier', NPI, NPI_NAME, TIN, NULL, SEVERITY, TOTAL_PAID, DETECTED_AT FROM DT_PROVIDER_BILLING_OUTLIERS;
