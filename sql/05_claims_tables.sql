-- =============================================================================
-- DST SIU NEXUS - CLAIMS-LEVEL TABLES & HIGH-RISK TAXONOMY
-- =============================================================================
-- Phase 2: Granular claims data schema and reference taxonomy for the 16
-- high-risk service categories per the SIU Project Plan.
--
-- The CLAIMS table follows the 24-column schema specified in the architecture:
-- person_id, claim_id, claim_line_nbr, amount_allowed, service_date,
-- TIN, TIN_NAME, NPI, NPI_NAME, Procedure_Code, Modifier1-4,
-- High_Risk_Category, Time_in_Minutes, Time_in_Hours, address/lat/lon
-- =============================================================================

USE DATABASE DST_SIU_DB;
USE SCHEMA RAW_DATA;

-- ============================================================================
-- HIGH_RISK_TAXONOMY: Reference table mapping procedure codes to categories
-- ============================================================================
-- The 16 high-risk service categories defined by DST SIU, each with
-- specific procedure codes, modifiers, and fraud-detection rules.
-- ============================================================================
CREATE OR REPLACE TABLE HIGH_RISK_TAXONOMY (
    CATEGORY_CODE       VARCHAR(10)     NOT NULL,       -- Short code: ACS, CFSS, HSS, etc.
    CATEGORY_NAME       VARCHAR(100)    NOT NULL,       -- Full name
    PROCEDURE_CODE      VARCHAR(10)     NOT NULL,       -- CPT/HCPCS code
    MODIFIER_PATTERN    VARCHAR(50),                    -- Expected modifier(s), e.g. 'UA', 'U8', NULL
    DESCRIPTION         VARCHAR(500)    NOT NULL,       -- What this code represents
    MAX_DAILY_HOURS     NUMBER(4,1),                    -- Maximum billable hours per day (NULL = no limit)
    MAX_DAILY_UNITS     NUMBER(5,0),                    -- Maximum billable units per day
    SUPERVISION_RATIO   NUMBER(5,2),                    -- Required supervision % (e.g. 10.00 for EIDBI)
    FRAUD_INDICATORS    VARCHAR(1000),                  -- Common fraud patterns for this category
    RULE_CATEGORY       VARCHAR(50),                    -- temporal, ratio, overlap, geospatial, volume
    PRIMARY KEY (CATEGORY_CODE, PROCEDURE_CODE)
)
COMMENT = 'Reference taxonomy of 16 high-risk service categories with procedure codes, billing limits, and fraud detection rules';

-- ============================================================================
-- SIU_CLAIMS: Granular claims-level data for anomaly detection
-- ============================================================================
-- 24-column schema per architecture spec. Each row = one claim line.
-- This is the primary table for the anomaly detection rules engine.
-- ============================================================================
CREATE OR REPLACE TABLE SIU_CLAIMS (
    CLAIM_ID            VARCHAR         NOT NULL,       -- Unique claim identifier
    CLAIM_LINE_NBR      NUMBER(5,0)     NOT NULL,       -- Line number within the claim
    PERSON_ID           VARCHAR         NOT NULL,       -- Member/patient identifier
    SERVICE_DATE        DATE            NOT NULL,       -- Date of service
    AMOUNT_ALLOWED      NUMBER(12,2),                   -- Allowed amount for this line
    AMOUNT_BILLED       NUMBER(12,2),                   -- Billed amount
    AMOUNT_PAID         NUMBER(12,2),                   -- Paid amount
    TIN                 VARCHAR(15)     NOT NULL,       -- Tax ID of billing entity
    TIN_NAME            VARCHAR(200),                   -- Name of billing entity
    NPI                 VARCHAR(15)     NOT NULL,       -- National Provider Identifier
    NPI_NAME            VARCHAR(200),                   -- Provider name
    PROCEDURE_CODE      VARCHAR(10)     NOT NULL,       -- CPT/HCPCS procedure code
    MODIFIER_1          VARCHAR(5),                     -- Modifier 1
    MODIFIER_2          VARCHAR(5),                     -- Modifier 2
    MODIFIER_3          VARCHAR(5),                     -- Modifier 3
    MODIFIER_4          VARCHAR(5),                     -- Modifier 4
    HIGH_RISK_CATEGORY  VARCHAR(10),                    -- FK to HIGH_RISK_TAXONOMY.CATEGORY_CODE
    TIME_IN_MINUTES     NUMBER(6,0),                    -- Service duration in minutes
    TIME_IN_HOURS       NUMBER(6,2),                    -- Service duration in hours (derived)
    ADDRESS_1           VARCHAR(200),                   -- Service location street
    CITY                VARCHAR(100),                   -- Service location city
    STATE               VARCHAR(5),                     -- Service location state
    ZIP                 VARCHAR(10),                    -- Service location ZIP
    LAT                 NUMBER(10,6),                   -- Latitude of service location
    LON                 NUMBER(11,6),                   -- Longitude of service location
    PLAN_TYPE           VARCHAR(20),                    -- MSHO, SNBC, PMAP, Commercial
    PRIMARY KEY (CLAIM_ID, CLAIM_LINE_NBR)
)
COMMENT = 'Granular claims-level data with 24+ columns for SIU anomaly detection. Each row represents one claim line with procedure codes, modifiers, time, geolocation, and high-risk categorization.';

-- ============================================================================
-- SEED HIGH_RISK_TAXONOMY with the 16 categories from the SIU plan
-- ============================================================================
INSERT INTO HIGH_RISK_TAXONOMY VALUES
-- ACS: Adult Companion Services
('ACS', 'Adult Companion Services', 'S5135', NULL, 'Adult companion services - non-medical care monitored for excessive hourly billing', 16.0, NULL, NULL, 'Excessive daily hours, billing for overnight without documentation, concurrent service overlaps', 'temporal'),

-- CFSS: Community First Services and Supports
('CFSS', 'Community First Services and Supports', 'T1019', NULL, 'Flexible support services tagged for volume analysis', 16.0, NULL, NULL, 'Volume spikes, rapid member shifting, ghost billing', 'volume'),

-- HSS: Housing Stabilization Services
('HSS', 'Housing Stabilization Services', 'H2015', 'U8', 'Housing stabilization support services monitored for billing anomalies', 16.0, NULL, NULL, 'Phantom visits, inflated time records, services to non-eligible addresses', 'temporal'),

-- Night Supervision
('NIGHT', 'Night Supervision Services', 'S5135', 'UA', 'Overnight supervision services - strict hour limits', 12.0, NULL, NULL, 'Billing exceeding overnight hours, overlapping day and night services for same member', 'temporal'),

-- ADC: Adult Day Care/Services
('ADC', 'Adult Day Services/Care', 'S5100', NULL, 'Adult day services susceptible to kickbacks - strict concurrent time monitoring', 10.0, NULL, NULL, 'Concurrent time overlaps, kickback schemes, transportation fraud pairing', 'overlap'),

-- NEMT: Nonemergency Health Plan Co.l Transportation
('NEMT', 'Nonemergency Health Plan Co.l Transportation', 'A0100', NULL, 'Non-emergency ambulance transport - base rate', NULL, NULL, NULL, 'Transport without corresponding clinical visit, excessive mileage, phantom rides', 'geospatial'),
('NEMT', 'Nonemergency Health Plan Co.l Transportation', 'A0080', NULL, 'Non-emergency ambulance transport - mileage', NULL, NULL, NULL, 'Mileage inconsistent with origin/destination, inflated distance claims', 'geospatial'),
('NEMT', 'Nonemergency Health Plan Co.l Transportation', 'T2003', NULL, 'Non-emergency transport - stretcher van', NULL, NULL, NULL, 'Stretcher transport without medical necessity documentation', 'geospatial'),

-- ARMHS: Adult Rehab Mental Health Services
('ARMHS', 'Adult Rehab Mental Health Services', 'H2017', NULL, 'Highly scrutinized category flagged for ghost billing and rapid member shifting', 16.0, NULL, NULL, 'Ghost billing, rapid member shifting, impossible daily totals, phantom services', 'temporal'),

-- ACT: Assertive Community Treatment
('ACT', 'Assertive Community Treatment', 'H0040', NULL, 'Intensive mental health service flagged for daily per diem limits', NULL, 1, NULL, 'Multiple per diems same day, billing during inpatient stays, service outside catchment area', 'overlap'),

-- EIDBI: Early Intensive Developmental & Behavioral Intervention
('EIDBI', 'Early Intensive Dev & Behavioral Intervention', '97151', NULL, 'EIDBI - Behavior identification assessment', NULL, NULL, NULL, 'Excessive assessment frequency, assessments without follow-up treatment', 'ratio'),
('EIDBI', 'Early Intensive Dev & Behavioral Intervention', '97152', NULL, 'EIDBI - Behavior identification supporting assessment', NULL, NULL, NULL, 'Supporting assessments exceeding primary assessments', 'ratio'),
('EIDBI', 'Early Intensive Dev & Behavioral Intervention', '97153', NULL, 'EIDBI - Adaptive behavior treatment by technician (direct service)', NULL, NULL, NULL, 'Direct service hours without corresponding supervision', 'ratio'),
('EIDBI', 'Early Intensive Dev & Behavioral Intervention', '97155', NULL, 'EIDBI - Adaptive behavior treatment by QSP (supervision)', NULL, NULL, 10.00, 'Supervision ratio must be <=10% of 97153 direct service hours. Ratio violations indicate billing fraud.', 'ratio'),
('EIDBI', 'Early Intensive Dev & Behavioral Intervention', 'H0032', NULL, 'EIDBI - Mental health service plan development', NULL, NULL, NULL, 'Excessive plan development billing without service delivery', 'ratio'),

-- IRTS: Intensive Residential Treatment Services
('IRTS', 'Intensive Residential Treatment Services', 'H0019', NULL, 'Inpatient psychiatric care strictly limited to one unit per day per member', NULL, 1, NULL, 'Multiple units same day, concurrent IRTS at different facilities, billing during hospital stay', 'overlap'),

-- PCA: Personal Care Assistance
('PCA', 'Personal Care Assistance', 'T1019', 'U4', 'In-home care services highly prone to overlapping timeframes and member brokering', 16.0, NULL, NULL, 'Overlapping timeframes across providers, member brokering, excessive hours', 'overlap'),

-- SUD: Substance Use Disorder
('SUD', 'Substance Use Disorder Treatment', 'H0015', NULL, 'SUD intensive outpatient - monitored for biologically impossible daily totals', 12.0, NULL, NULL, 'Daily hours exceeding biological possibility, concurrent services, billing during inpatient', 'temporal'),

-- UDT: Urine Drug Testing
('UDT', 'Urine Drug Testing', '80305', NULL, 'Drug testing presumptive - monitored for unnecessary volume and frequency', NULL, NULL, NULL, 'Excessive testing frequency, testing without clinical indication, definitive testing without presumptive', 'volume'),
('UDT', 'Urine Drug Testing', '80306', NULL, 'Drug testing definitive - monitored for overutilization', NULL, NULL, NULL, 'Definitive testing without initial presumptive test, excessive panel complexity', 'volume'),
('UDT', 'Urine Drug Testing', '80307', NULL, 'Drug testing definitive high complexity', NULL, NULL, NULL, 'High complexity testing without medical justification', 'volume'),

-- E/M Upcoding (not one of the 16 but critical for provider FWA)
('EM', 'Evaluation & Management', '99213', NULL, 'E/M Office visit Level 3 - established patient', NULL, NULL, NULL, 'Distribution skew toward higher levels, coding intensity above peers', 'volume'),
('EM', 'Evaluation & Management', '99214', NULL, 'E/M Office visit Level 4 - established patient', NULL, NULL, NULL, 'Upcoding from 99213 to 99214 without documentation support', 'volume'),
('EM', 'Evaluation & Management', '99215', NULL, 'E/M Office visit Level 5 - established patient (highest)', NULL, NULL, NULL, 'Excessive 99215 usage, minimal documentation for complexity claimed', 'volume');
