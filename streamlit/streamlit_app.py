# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Braedon Hill

import streamlit as st

st.set_page_config(
    page_title="SIU Nexus | DST",
    page_icon="🛡️",
    layout="wide",
    initial_sidebar_state="expanded",
)

from utils.styles import (
    apply_styles, render_header, render_metric_card, render_feature_card,
    SNOWFLAKE_LOGO_BYTES, CLIENT_LOGO_BYTES, render_section_separator,
    render_warning_callout, render_success_callout,
)
from utils.navigation import render_sidebar, render_nav_buttons, get_snowflake_session

apply_styles()
render_sidebar("Home")

# --- Hero Banner: dual logos ---
logo_spacer, logo_area = st.columns([3, 1])
with logo_area:
    lc1, lc2, lc3 = st.columns([1, 0.3, 1])
    with lc1:
        if SNOWFLAKE_LOGO_BYTES:
            st.image(SNOWFLAKE_LOGO_BYTES, width=50)
    with lc2:
        st.markdown(
            '<p style="text-align:center;color:#8892b0;font-size:1.2rem;'
            'font-weight:300;margin-top:0.2rem;">+</p>',
            unsafe_allow_html=True,
        )
    with lc3:
        if CLIENT_LOGO_BYTES:
            st.image(CLIENT_LOGO_BYTES, width=120)

st.markdown("""
<div class="main-header animate-in" style="text-align:center; padding:2rem 2rem 1.5rem;">
    <h1 style="font-size:2.5rem; margin-bottom:0.25rem;">🛡️ SIU NEXUS</h1>
    <p style="font-size:1.2rem; font-weight:600; color:rgba(255,255,255,0.95);">
        Special Investigations Unit — Fraud Detection Command Center
    </p>
    <p style="font-size:0.9rem; margin-top:0.5rem;">
        DST on Snowflake AI Data Cloud — 6 Anomaly Engines &bull; Real-Time Dynamic Tables &bull; Cortex Intelligence
    </p>
</div>
""", unsafe_allow_html=True)

# --- KPI Tiles (live from Snowflake if available) ---
session = get_snowflake_session()

# Default values (static fallback)
total_anomalies = "—"
critical_count = "—"
financial_impact = "—"
flagged_providers = "—"
open_cases = "—"
claims_monitored = "—"

if session:
    try:
        row = session.sql("""
            SELECT COUNT(*) AS TOTAL,
                   SUM(CASE WHEN SEVERITY = 'CRITICAL' THEN 1 ELSE 0 END) AS CRITICAL_CNT,
                   SUM(FINANCIAL_IMPACT) AS IMPACT,
                   COUNT(DISTINCT NPI) AS PROVIDERS
            FROM DST_SIU_DB.ANALYTICS.ANOMALY_SUMMARY
        """).to_pandas().iloc[0]
        total_anomalies = f"{int(row['TOTAL']):,}"
        critical_count = f"{int(row['CRITICAL_CNT']):,}"
        financial_impact = f"${row['IMPACT']/1_000_000:,.1f}M" if row["IMPACT"] and row["IMPACT"] >= 1_000_000 else f"${row['IMPACT']/1_000:,.0f}K" if row["IMPACT"] else "$0"
        flagged_providers = f"{int(row['PROVIDERS']):,}"
    except Exception:
        pass

    try:
        case_row = session.sql("""
            SELECT SUM(OPEN_CASES) AS OPEN_CASES
            FROM DST_SIU_DB.ANALYTICS.SIU_CASE_SUMMARY
        """).to_pandas().iloc[0]
        open_cases = f"{int(case_row['OPEN_CASES']):,}"
    except Exception:
        pass

    try:
        claims_row = session.sql("""
            SELECT COUNT(*) AS CNT FROM DST_SIU_DB.RAW_DATA.SIU_CLAIMS
        """).to_pandas().iloc[0]
        claims_monitored = f"{int(claims_row['CNT']):,}"
    except Exception:
        pass


col1, col2, col3, col4, col5, col6 = st.columns(6)
with col1:
    st.markdown(render_metric_card(total_anomalies, "Total Anomalies", accent="#FF6B6B"), unsafe_allow_html=True)
with col2:
    st.markdown(render_metric_card(critical_count, "Critical Alerts", accent="#FF6B6B"), unsafe_allow_html=True)
with col3:
    st.markdown(render_metric_card(financial_impact, "Financial Impact", accent="#FFB74D"), unsafe_allow_html=True)
with col4:
    st.markdown(render_metric_card(flagged_providers, "Flagged Providers", accent="#29B5E8"), unsafe_allow_html=True)
with col5:
    st.markdown(render_metric_card(open_cases, "Open Cases", accent="#29B5E8"), unsafe_allow_html=True)
with col6:
    st.markdown(render_metric_card(claims_monitored, "Claims Monitored", accent="#00D4AA"), unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

# --- Detection Engine Overview ---
st.markdown(render_section_separator(
    "6 Anomaly Detection Engines",
    "Real-time Dynamic Tables continuously scan claims for fraud, waste, and abuse patterns"
), unsafe_allow_html=True)

engines = [
    ("⏱️", "Temporal Impossibility", "Providers billing >24 hours of services in a single calendar day", "#FF6B6B"),
    ("📊", "EIDBI Ratio Monitoring", "97155 supervision hours exceeding the 10% threshold vs 97153 direct service", "#FFB74D"),
    ("🔄", "Service Overlaps", "Same member receiving conflicting services on the same day (ADC+PCA, dual IRTS)", "#29B5E8"),
    ("📍", "Geospatial Distance", "Same-day services for one member at locations >50 miles apart (Haversine)", "#00D4AA"),
    ("🕐", "Daily Hour Violations", "Individual providers exceeding maximum allowable daily service hours", "#FF6B6B"),
    ("📈", "Billing Outliers", "Provider billing Z-scores >2.5 standard deviations from peer group averages", "#FFB74D"),
]

row1 = st.columns(3)
for i, (icon, title, desc, color) in enumerate(engines):
    if i == 3:
        row2 = st.columns(3)
    col = row1[i % 3] if i < 3 else row2[i % 3]
    with col:
        st.markdown(render_feature_card(icon, title, desc, color), unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

# --- How It Works ---
st.markdown("### How SIU Nexus Works")

col_before, col_after = st.columns(2)

with col_before:
    st.markdown("#### Traditional SIU Process")
    challenges = [
        ("Manual Review", "Investigators manually sift through claims data — months of delay before fraud is identified"),
        ("Siloed Data", "Claims, provider, member, and pharmacy data in separate systems with no cross-referencing"),
        ("Reactive Detection", "Fraud discovered only after payment — pay-and-chase model with low recovery rates"),
        ("No Pattern Recognition", "Unable to detect complex schemes spanning providers, members, or service categories"),
    ]
    for title, desc in challenges:
        st.markdown(f"""
        <div style="background:rgba(255,107,107,0.08); border-left:3px solid #FF6B6B; border-radius:0 8px 8px 0;
                    padding:0.75rem 1rem; margin:0.5rem 0;">
            <strong style="color:#FF6B6B;">{title}</strong>
            <p style="color:#8892b0; margin:0.25rem 0 0; font-size:0.85rem;">{desc}</p>
        </div>
        """, unsafe_allow_html=True)

with col_after:
    st.markdown("#### SIU Nexus on Snowflake")
    solutions = [
        ("Real-Time Detection", "6 Dynamic Tables with 1-hour target lag — anomalies surface within an hour of claims ingestion"),
        ("Unified Claims Lake", "All claims, providers, members, and taxonomy in one governed Snowflake database"),
        ("Proactive Intelligence", "Cortex AI agent (SIU Sentinel) answers natural language questions over the full SIU data estate"),
        ("Multi-Vector Analysis", "Temporal, geospatial, ratio, overlap, and statistical engines cross-reference simultaneously"),
    ]
    for title, desc in solutions:
        st.markdown(f"""
        <div style="background:rgba(0,212,170,0.08); border-left:3px solid #00D4AA; border-radius:0 8px 8px 0;
                    padding:0.75rem 1rem; margin:0.5rem 0;">
            <strong style="color:#00D4AA;">{title}</strong>
            <p style="color:#8892b0; margin:0.25rem 0 0; font-size:0.85rem;">{desc}</p>
        </div>
        """, unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

# --- High-Risk Categories ---
st.markdown("### Monitored High-Risk Service Categories")
st.markdown("""
<p style="color:#8892b0;font-size:0.9rem;">
SIU Nexus monitors 16 high-risk service categories across Health Plan Co.id and commercial plans,
covering personal care, behavioral health, transportation, and substance use disorder services.
</p>
""", unsafe_allow_html=True)

cats = st.columns(4)
categories = [
    ("ACS", "Adult Companion", "S5135"),
    ("CFSS", "Community First", "T1019"),
    ("HSS", "Home Support", "H2015+U8"),
    ("NIGHT", "Overnight Care", "S5135+UA"),
    ("ADC", "Adult Day Care", "S5100"),
    ("NEMT", "Transport", "A0100/A0080"),
    ("ARMHS", "Mental Health", "H2017"),
    ("ACT", "Assertive Comm.", "H0040"),
    ("EIDBI", "Early Intensive", "97151-97155"),
    ("IRTS", "Residential Tx", "H0019"),
    ("PCA", "Personal Care", "T1019+U4"),
    ("SUD", "Substance Use", "H0015"),
    ("UDT", "Drug Testing", "80305-80307"),
    ("EM", "E&M Visits", "99213-99215"),
    ("PHY", "Physical Therapy", "97110-97140"),
    ("OCC", "Occupational Tx", "97530-97542"),
]
for i, (code, name, procs) in enumerate(categories):
    with cats[i % 4]:
        st.markdown(f"""
        <div style="background:linear-gradient(145deg,#1a1f35,#0d1117);border-radius:12px;
                    padding:0.75rem 1rem;margin:0.25rem 0;border:1px solid rgba(255,255,255,0.08);">
            <strong style="color:#29B5E8;font-size:0.9rem;">{code}</strong>
            <span style="color:#8892b0;font-size:0.8rem;"> — {name}</span>
            <p style="color:#4ECDC4;font-size:0.7rem;margin:0.2rem 0 0;font-family:monospace;">{procs}</p>
        </div>
        """, unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

# --- Architecture ---
st.markdown("### SIU Nexus Architecture")
_spacer_l, _diagram_col, _spacer_r = st.columns([1, 3, 1])
with _diagram_col:
    st.graphviz_chart("""
    digraph siu_nexus {
        bgcolor="transparent"
        graph [size="8,5" dpi=72]
        node [fontname="Helvetica" fontsize=9 style="filled,rounded" shape=box]
        edge [fontname="Helvetica" fontsize=8 color="#8892b0"]

        subgraph cluster_ingest {
            label="Data Ingestion" style="rounded,dashed" color="#29B5E8" fontcolor="#29B5E8" fontname="Helvetica" fontsize=9
            claims [label="Claims Data\\n(SIU_CLAIMS)" fillcolor="#1a2332" fontcolor="#FAFAFA"]
            taxonomy [label="Risk Taxonomy\\n(16 Categories)" fillcolor="#1a2332" fontcolor="#FAFAFA"]
            cases [label="SIU Cases\\n& Tipline" fillcolor="#1a2332" fontcolor="#FAFAFA"]
        }

        subgraph cluster_engines {
            label="6 Dynamic Table Engines" style="rounded,filled" fillcolor="#11567F" color="#29B5E8" fontcolor="#29B5E8" fontname="Helvetica" fontsize=9
            temporal [label="Temporal\\nImpossibility" fillcolor="#FF6B6B" fontcolor="white"]
            eidbi [label="EIDBI\\nRatio" fillcolor="#FFB74D" fontcolor="white"]
            overlap [label="Service\\nOverlaps" fillcolor="#29B5E8" fontcolor="white"]
            geo [label="Geospatial\\nDistance" fillcolor="#00D4AA" fontcolor="white"]
            hours [label="Daily Hour\\nViolations" fillcolor="#FF6B6B" fontcolor="white"]
            outlier [label="Billing\\nOutliers" fillcolor="#FFB74D" fontcolor="white"]
        }

        subgraph cluster_ai {
            label="Cortex AI Layer" style="rounded,dashed" color="#00D4AA" fontcolor="#00D4AA" fontname="Helvetica" fontsize=9
            sentinel [label="SIU SENTINEL\\nAgent" fillcolor="#00D4AA" fontcolor="white" shape=oval]
            search [label="Cortex Search\\n(Notes + Tipline)" fillcolor="#1a2332" fontcolor="#FAFAFA"]
            analyst [label="Cortex Analyst\\n(Semantic Model)" fillcolor="#1a2332" fontcolor="#FAFAFA"]
        }

        claims -> temporal
        claims -> eidbi
        claims -> overlap
        claims -> geo
        claims -> hours
        claims -> outlier
        taxonomy -> temporal [style=dashed]
        cases -> search
        temporal -> sentinel [style=dashed]
        eidbi -> sentinel [style=dashed]
        overlap -> sentinel [style=dashed]
        geo -> sentinel [style=dashed]
        analyst -> sentinel
        search -> sentinel
    }
    """)

# --- Presenter Notes ---
with st.expander("Presenter Notes"):
    st.markdown("""
    **Presenter:** Solution Engineering — Snowflake

    **Key Message:** The SIU team currently relies on manual claims review to detect fraud, waste,
    and abuse across high-risk Health Plan Co.id services. SIU Nexus demonstrates how Snowflake's
    Dynamic Tables, Cortex AI, and real-time analytics can transform reactive pay-and-chase into
    proactive fraud prevention — surfacing anomalies within an hour of claims ingestion.

    **Technical Highlights:**
    - 6 anomaly detection engines running as Dynamic Tables (1-hour target lag)
    - 4,699 synthetic claims seeded with 5 intentional fraud patterns
    - SIU Sentinel agent powered by Cortex Analyst (semantic model) + Cortex Search (investigation notes)
    - 16 high-risk service categories mapped to standard procedure codes
    - Haversine geospatial distance, EIDBI 10% supervision ratio, temporal impossibility detection

    **Transition:** "Let's start with the Anomaly Triage view to see what the engines have flagged."
    """)

# --- Nav ---
st.markdown("---")
render_nav_buttons("       