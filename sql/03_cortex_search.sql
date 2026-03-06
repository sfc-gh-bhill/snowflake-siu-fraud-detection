-- =============================================================================
-- DST SIU NEXUS - CORTEX SEARCH SERVICES
-- =============================================================================
-- Creates Cortex Search services for natural language querying of
-- investigation notes and tipline reports by the SIU_SENTINEL agent.
-- =============================================================================

USE DATABASE DST_SIU_DB;
USE SCHEMA SEARCH;
USE WAREHOUSE DST_SIU_WH;

-- ============================================================================
-- INVESTIGATION NOTES SEARCH
-- ============================================================================
-- Enables SIU_SENTINEL to search investigation narratives, interview
-- summaries, surveillance reports, and closing summaries using natural
-- language. Enriched with case metadata for filtered searching.
-- ============================================================================
CREATE OR REPLACE CORTEX SEARCH SERVICE SIU_INVESTIGATION_SEARCH
  ON NOTE_TEXT
  ATTRIBUTES CASE_ID, AUTHOR, NOTE_TYPE, CASE_TYPE, SUBTYPE, SUBJECT_NAME, REGION, CASE_STATUS, CASE_PRIORITY
  WAREHOUSE = DST_SIU_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Search service over SIU investigation notes and case narratives'
  AS (
    SELECT
      n.NOTE_ID,
      n.CASE_ID,
      n.NOTE_DATE::VARCHAR AS NOTE_DATE,
      n.AUTHOR,
      n.NOTE_TYPE,
      n.NOTE_TEXT,
      c.CASE_TYPE,
      c.SUBTYPE,
      c.SUBJECT_NAME,
      c.PLAN_TYPE,
      c.REGION,
      c.STATUS AS CASE_STATUS,
      c.PRIORITY AS CASE_PRIORITY
    FROM DST_SIU_DB.RAW_DATA.SIU_INVESTIGATION_NOTES n
    LEFT JOIN DST_SIU_DB.RAW_DATA.SIU_CASES c ON n.CASE_ID = c.CASE_ID
  );

-- ============================================================================
-- TIPLINE REPORTS SEARCH
-- ============================================================================
-- Enables SIU_SENTINEL to search tipline allegations and referral
-- descriptions using natural language.
-- ============================================================================
CREATE OR REPLACE CORTEX SEARCH SERVICE SIU_TIPLINE_SEARCH
  ON SUBJECT_DESCRIPTION
  ATTRIBUTES TIP_ID, REPORTER_TYPE, CASE_TYPE_ALLEGED, REGION, STATUS, URGENCY
  WAREHOUSE = DST_SIU_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Search service over SIU tipline reports and fraud allegations'
  AS (
    SELECT
      t.TIP_ID,
      t.REPORT_DATE::VARCHAR AS REPORT_DATE,
      t.REPORTER_TYPE,
      t.CASE_TYPE_ALLEGED,
      t.SUBJECT_DESCRIPTION,
      t.REGION,
      t.STATUS,
      t.LINKED_CASE_ID,
      t.URGENCY
    FROM DST_SIU_DB.RAW_DATA.SIU_TIPLINE_REPORTS t
  );
