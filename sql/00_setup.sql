-- =============================================================================
-- DST SIU NEXUS - INFRASTRUCTURE SETUP
-- =============================================================================
-- Creates the DST_SIU_DB database, schemas, warehouse, stages, and formats
-- for the Special Investigations Unit (SIU) analytics platform.
-- =============================================================================

-- ============================================================================
-- DATABASE
-- ============================================================================
CREATE DATABASE IF NOT EXISTS DST_SIU_DB
  COMMENT = 'DST Special Investigations Unit - Fraud, Waste, and Abuse detection and investigation management';

USE DATABASE DST_SIU_DB;

-- ============================================================================
-- SCHEMAS
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS RAW_DATA
  COMMENT = 'Raw investigation data: cases, tipline reports, provider risk profiles, member indicators, pharmacy alerts, investigation notes';

CREATE SCHEMA IF NOT EXISTS ANALYTICS
  COMMENT = 'Gold-layer analytic views for SIU dashboards, risk scoring, and investigation productivity';

CREATE SCHEMA IF NOT EXISTS SEARCH
  COMMENT = 'Cortex Search services over investigation notes and tipline reports';

CREATE SCHEMA IF NOT EXISTS SEMANTIC_MODELS
  COMMENT = 'Semantic model YAML files for Cortex Analyst text-to-SQL';

CREATE SCHEMA IF NOT EXISTS AGENTS
  COMMENT = 'Cortex Agent definitions for SIU_SENTINEL';

-- ============================================================================
-- WAREHOUSE
-- ============================================================================
CREATE WAREHOUSE IF NOT EXISTS DST_SIU_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for SIU Nexus analytics, Cortex Search, and Agent workloads';

USE WAREHOUSE DST_SIU_WH;

-- ============================================================================
-- FILE FORMAT
-- ============================================================================
USE SCHEMA RAW_DATA;

CREATE OR REPLACE FILE FORMAT CSV_FORMAT
  TYPE = 'CSV'
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('NULL', '')
  EMPTY_FIELD_AS_NULL = TRUE
  COMMENT = 'Standard CSV format for SIU data loading';

-- ============================================================================
-- STAGES
-- ============================================================================
CREATE OR REPLACE STAGE SIU_DATA_STAGE
  COMMENT = 'Internal stage for uploading SIU CSV data files';

USE SCHEMA SEMANTIC_MODELS;

CREATE OR REPLACE STAGE YAML_STAGE
  COMMENT = 'Internal stage for SIU Sentinel semantic model YAML';
