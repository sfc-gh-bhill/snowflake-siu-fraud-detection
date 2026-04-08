# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Braedon Hill

"""
SIU Nexus — Anomaly Triage
Unified view across all 6 detection engines, sorted by severity and financial impact.
"""
import streamlit as st
import pandas as pd
import altair as alt

st.set_page_config(page_title="Anomaly Triage | SIU Nexus", page_icon="🛡️", layout="wide")

from utils.styles import apply_styles, render_header, render_metric_card, SEVERITY_COLORS
from utils.navigation import render_sidebar, render_nav_buttons, get_snowflake_session, get_severity_filter

apply_styles()
render_sidebar("Anomaly Triage")

render_header("Anomaly Detection Triage", "Unified view across all 6 detection engines — sorted by severity and financial impact")


def format_currency(val) -> str:
    if pd.isna(val) or val is None:
        return "$0"
    if abs(val) >= 1_000_000:
        return f"${val / 1_000_000:,.1f}M"
    if abs(val) >= 1_000:
        return f"${val / 1_000:,.0f}K"
    return f"${val:,.0f}"


session = get_snowflake_session()
if not session:
    st.warning("No Snowflake session available. Connect to view live data.")
    st.stop()

severity_filter = get_severity_filter()

df = session.sql("""
    SELECT ANOMALY_TYPE, NPI, NPI_NAME, TIN, DETAIL_DATE, SEVERITY,
           FINANCIAL_IMPACT, DETECTED_AT
    FROM DST_SIU_DB.ANALYTICS.ANOMALY_SUMMARY
    ORDER BY
        CASE SEVERITY WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2
                     WHEN 'MEDIUM' THEN 3 ELSE 4 END,
        FINANCIAL_IMPACT DESC NULLS LAST
""").to_pandas()

if df.empty:
    st.info("No anomalies detected. Dynamic Tables may still be initializing.")
else:
    if severity_filter:
        df = df[df["SEVERITY"].isin(severity_filter)]

    # Summary metrics
    col1, col2, col3, col4, col5 = st.columns(5)
    with col1:
        st.markdown(render_metric_card(f"{len(df):,}", "Total Anomalies", accent="#29B5E8"), unsafe_allow_html=True)
    with col2:
        crit = len(df[df["SEVERITY"] == "CRITICAL"])
        st.markdown(render_metric_card(f"{crit:,}", "Critical", accent="#FF6B6B"), unsafe_allow_html=True)
    with col3:
        high = len(df[df["SEVERITY"] == "HIGH"])
        st.markdown(render_metric_card(f"{high:,}", "High", accent="#FFB74D"), unsafe_allow_html=True)
    with col4:
        total_impact = df["FINANCIAL_IMPACT"].sum()
        st.markdown(render_metric_card(format_currency(total_impact), "Financial Impact", accent="#FF6B6B"), unsafe_allow_html=True)
    with col5:
        unique_npi = df["NPI"].nunique()
        st.markdown(render_metric_card(f"{unique_npi:,}", "Flagged Providers", accent="#29B5E8"), unsafe_allow_html=True)

    st.markdown("---")

    # Distribution by anomaly type
    col_a, col_b = st.columns([3, 2])

    with col_a:
        st.markdown("### Anomalies by Detection Engine")
        type_counts = df.groupby("ANOMALY_TYPE").agg(
            COUNT=("ANOMALY_TYPE", "size"),
            FINANCIAL_IMPACT=("FINANCIAL_IMPACT", "sum"),
        ).reset_index().sort_values("COUNT", ascending=False)

        chart = alt.Chart(type_counts).mark_bar(
            cornerRadiusTopRight=6, cornerRadiusTopLeft=6
        ).encode(
            x=alt.X("ANOMALY_TYPE:N", sort="-y", title=None,
                     axis=alt.Axis(labelAngle=-30, labelFontSize=11)),
            y=alt.Y("COUNT:Q", title="Count"),
            color=alt.value("#29B5E8"),
            tooltip=["ANOMALY_TYPE", "COUNT", "FINANCIAL_IMPACT"],
        ).properties(height=350).configure_view(strokeWidth=0).configure_axis(
            gridColor="rgba(255,255,255,0.05)", labelColor="#8892b0", titleColor="#8892b0"
        )
        st.altair_chart(chart, use_container_width=True)

    with col_b:
        st.markdown("### Severity Distribution")
        sev_counts = df["SEVERITY"].value_counts().reset_index()
        sev_counts.columns = ["SEVERITY", "COUNT"]

        donut = alt.Chart(sev_counts).mark_arc(innerRadius=60, outerRadius=120).encode(
            theta=alt.Theta("COUNT:Q"),
            color=alt.Color("SEVERITY:N",
                scale=alt.Scale(
                    domain=list(SEVERITY_COLORS.keys()),
                    range=list(SEVERITY_COLORS.values()),
                ),
                legend=alt.Legend(title="Severity"),
            ),
            tooltip=["SEVERITY", "COUNT"],
        ).properties(height=350).configure_view(strokeWidth=0)
        st.altair_chart(donut, use_container_width=True)

    # Detail table
    st.markdown("### Anomaly Detail")
    st.dataframe(
        df,
        use_container_width=True,
        height=400,
        column_config={
            "FINANCIAL_IMPACT": st.column_config.NumberColumn(format="$%.2f"),
            "DETECTED_AT": st.column_config.DatetimeColumn(format="YYYY-MM-DD HH:mm"),
        },
    )

st.markdown("---")
render_nav_buttons("Anomaly Triage")
