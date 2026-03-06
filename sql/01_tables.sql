-- =============================================================================
-- DST SIU NEXUS - TABLE DEFINITIONS
-- =============================================================================
-- All raw data tables in DST_SIU_DB.RAW_DATA schema.
-- Tables support the full SIU suite: Provider FWA, Member FWA,
-- Pharmacy Fraud, and Network Abuse investigations.
-- =============================================================================

USE DATABASE DST_SIU_DB;
USE SCHEMA RAW_DATA;

-- ============================================================================
-- SIU_CASES: Core investigation case records
-- ============================================================================
CREATE OR REPLACE TABLE SIU_CASES (
    CASE_ID             VARCHAR         PRIMARY KEY,
    CASE_TYPE           VARCHAR         NOT NULL,       -- Provider_FWA, Member_FWA, Pharmacy_Fraud, Network_Abuse
    SUBTYPE             VARCHAR         NOT NULL,       -- Upcoding, Doctor_Shopping, GLP1_Diversion, etc.
    SUBJECT_ID          VARCHAR         NOT NULL,       -- NPI, MEMBER_ID, or PHARMACY_ID
    SUBJECT_NAME        VARCHAR         NOT NULL,
    PLAN_TYPE           VARCHAR,                        -- MSHO, SNBC, PMAP, Commercial
    REGION              VARCHAR,                        -- Twin Cities Metro, Southeast MN, etc.
    STATUS              VARCHAR         NOT NULL,       -- Open, Under_Review, Referred_to_Law_Enforcement, etc.
    PRIORITY            VARCHAR         NOT NULL,       -- Critical, High, Medium, Low
    ESTIMATED_EXPOSURE  NUMBER(15,2),                   -- Dollar amount at risk
    RECOVERED_AMOUNT    NUMBER(15,2)    DEFAULT 0,      -- Amount recovered to date
    OPEN_DATE           DATE            NOT NULL,
    CLOSE_DATE          DATE,                           -- NULL for open cases
    ASSIGNED_INVESTIGATOR VARCHAR,
    REFERRAL_SOURCE     VARCHAR                         -- Algorithm_Detection, Tipline, Audit, etc.
)
COMMENT = 'Core SIU investigation case records covering Provider FWA, Member FWA, Pharmacy Fraud, and Network Abuse domains';

-- ============================================================================
-- SIU_TIPLINE_REPORTS: Anonymous tips and referrals
-- ============================================================================
CREATE OR REPLACE TABLE SIU_TIPLINE_REPORTS (
    TIP_ID              VARCHAR         PRIMARY KEY,
    REPORT_DATE         DATE            NOT NULL,
    REPORTER_TYPE       VARCHAR         NOT NULL,       -- Anonymous, Member, Provider, Employee, External_Agency
    CASE_TYPE_ALLEGED   VARCHAR         NOT NULL,       -- Alleged fraud type
    SUBJECT_DESCRIPTION VARCHAR(2000)   NOT NULL,       -- Narrative describing the allegation
    REGION              VARCHAR,
    STATUS              VARCHAR         NOT NULL,       -- New, Under_Review, Assigned_to_Case, Dismissed, Duplicate
    LINKED_CASE_ID      VARCHAR,                        -- FK to SIU_CASES if assigned
    URGENCY             VARCHAR                         -- Immediate, Standard, Low
)
COMMENT = 'Tipline reports and anonymous referrals alleging fraud, waste, or abuse';

-- ============================================================================
-- SIU_PROVIDER_RISK_PROFILES: Provider risk scoring and FWA indicators
-- ============================================================================
CREATE OR REPLACE TABLE SIU_PROVIDER_RISK_PROFILES (
    PROVIDER_NPI                VARCHAR     PRIMARY KEY,
    PROVIDER_NAME               VARCHAR     NOT NULL,
    PROVIDER_NETWORK            VARCHAR,                -- Provider network affiliation
    SPECIALTY                   VARCHAR,
    REGION                      VARCHAR,
    CLAIM_COUNT_12M             NUMBER,                 -- Claims in last 12 months
    TOTAL_BILLED_12M            NUMBER(15,2),
    TOTAL_PAID_12M              NUMBER(15,2),
    AVG_PAID_PER_CLAIM          NUMBER(10,2),
    PEER_AVG_PAID               NUMBER(10,2),           -- Specialty peer average
    PAID_ZSCORE                 NUMBER(5,2),            -- Z-score vs peers
    CLAIMS_PER_PATIENT          NUMBER(5,2),
    PEER_AVG_CLAIMS_PER_PATIENT NUMBER(5,2),
    VOLUME_ZSCORE               NUMBER(5,2),
    DUPLICATE_CLAIM_RATE        NUMBER(5,2),            -- Percentage 0-15
    DENIAL_RATE                 NUMBER(5,2),            -- Percentage 5-40
    CLEAN_CLAIM_RATE            NUMBER(5,2),            -- Percentage 60-99
    COMPOSITE_RISK_SCORE        NUMBER(5,2),            -- 0-100 weighted composite
    RISK_TIER                   VARCHAR,                -- Critical, High, Medium, Low
    FWA_FLAGS                   VARCHAR(1000),          -- Comma-separated triggered flags
    LAST_AUDIT_DATE             DATE,
    ACTIVE_CASES                NUMBER                  -- Count of open SIU cases
)
COMMENT = 'Provider risk profiles with composite FWA scoring, peer benchmarks, and outlier detection indicators';

-- ============================================================================
-- SIU_MEMBER_FRAUD_INDICATORS: Member-side fraud signals
-- ============================================================================
CREATE OR REPLACE TABLE SIU_MEMBER_FRAUD_INDICATORS (
    MEMBER_ID                   VARCHAR     PRIMARY KEY,
    MEMBER_NAME                 VARCHAR     NOT NULL,
    PLAN_TYPE                   VARCHAR,
    REGION                      VARCHAR,
    INDICATOR_TYPE              VARCHAR     NOT NULL,    -- Doctor_Shopping, Identity_Fraud, etc.
    UNIQUE_PROVIDERS_90D        NUMBER,                 -- Distinct providers in 90 days
    UNIQUE_PHARMACIES_90D       NUMBER,
    CONTROLLED_SUBSTANCE_RX_90D NUMBER,                 -- Controlled substance Rx count
    ER_VISITS_90D               NUMBER,
    OVERLAPPING_ELIGIBILITY_FLAG BOOLEAN,
    ADDRESS_CHANGE_FREQUENCY_12M NUMBER,
    RISK_SCORE                  NUMBER(5,2),            -- 0-100
    RISK_TIER                   VARCHAR,                -- Critical, High, Medium, Low
    ESTIMATED_EXPOSURE          NUMBER(15,2),
    LINKED_CASE_ID              VARCHAR,                -- FK to SIU_CASES if under investigation
    DETECTION_DATE              DATE,
    DETECTION_METHOD            VARCHAR                 -- Algorithm, Audit, Referral, Tipline
)
COMMENT = 'Member-side fraud indicators including doctor shopping, identity fraud, eligibility abuse, and prescription surfing signals';

-- ============================================================================
-- SIU_PHARMACY_ALERTS: Pharmacy fraud detection alerts
-- ============================================================================
CREATE OR REPLACE TABLE SIU_PHARMACY_ALERTS (
    ALERT_ID            VARCHAR         PRIMARY KEY,
    PHARMACY_ID         VARCHAR         NOT NULL,
    PHARMACY_NAME       VARCHAR         NOT NULL,
    REGION              VARCHAR,
    ALERT_TYPE          VARCHAR         NOT NULL,       -- GLP1_Volume_Anomaly, Controlled_Substance_Spike, etc.
    DRUG_CATEGORY       VARCHAR,                        -- GLP-1, Opioid, Benzodiazepine, Stimulant, Other_Controlled
    METRIC_VALUE        NUMBER(10,2),                   -- The anomalous metric value
    PEER_BENCHMARK      NUMBER(10,2),                   -- Peer comparison value
    DEVIATION_PERCENT   NUMBER(7,2),                    -- Percentage deviation from normal
    ALERT_DATE          DATE            NOT NULL,
    STATUS              VARCHAR         NOT NULL,       -- New, Investigating, Confirmed_Fraud, False_Positive, Monitoring
    ESTIMATED_EXPOSURE  NUMBER(15,2),
    LINKED_CASE_ID      VARCHAR,                        -- FK to SIU_CASES if under investigation
    PRESCRIBER_NPI      VARCHAR                         -- Link to provider
)
COMMENT = 'Pharmacy fraud alerts covering GLP-1 diversion, pill mill patterns, controlled substance anomalies, and forged prescriptions';

-- ============================================================================
-- SIU_INVESTIGATION_NOTES: Case narratives for Cortex Search
-- ============================================================================
CREATE OR REPLACE TABLE SIU_INVESTIGATION_NOTES (
    NOTE_ID             VARCHAR         PRIMARY KEY,
    CASE_ID             VARCHAR         NOT NULL,       -- FK to SIU_CASES
    NOTE_DATE           DATE            NOT NULL,
    AUTHOR              VARCHAR         NOT NULL,       -- Investigator name
    NOTE_TYPE           VARCHAR         NOT NULL,       -- Initial_Assessment, Interview_Summary, etc.
    NOTE_TEXT           VARCHAR(10000)  NOT NULL        -- Detailed narrative text
)
COMMENT = 'Investigation notes and case narratives providing detailed unstructured text for Cortex Search natural language querying';
