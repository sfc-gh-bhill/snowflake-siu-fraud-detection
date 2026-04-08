# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Braedon Hill

"""
SIU Nexus — Claims Explorer
Drill into claims-level data by high-risk category, provider, or member.
"""
import streamlit as st
import pandas as pd
import altair as alt

st.set_page_config(page_title="Claims Explorer | SIU Nexus", page_icon="🛡️", layout="wide")

from utils.styles import apply_styles, render_header, render_metric_card
from utils.navigation import render_sidebar, render_nav_buttons, get_snowflake_session

apply_styles()
render_sidebar("Claims Explorer")

render_header("🔍 Claims Explorer", "Drill into claims-level data by high-risk category, provider, or member")


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
    st.warning("No Snowflake session available.")
    st.stop()

cat_df = session.sql("""
    SELECT HIGH_RISK_CATEGORY, COUNT(*) AS CLAIM_COUNT,
           SUM(AMOUNT_PAID) AS TOTAL_PAID,
           COUNT(DISTINCT NPI) AS PROVIDER_COUNT,
           COUNT(DISTINCT PERSON_ID) AS MEMBER_COUNT,
           AVG(TIME_IN_MINUTES) AS AVG_MINUTES
    FROM DST_SIU_DB.RAW_DATA.SIU_CLAIMS
    WHERE HIGH_RISK_CATEGORY IS NOT NULL
    GROUP BY HIGH_RISK_CATEGORY
    ORDER BY TOTAL_PAID DESC
""").to_pandas()

col_a, col_b = st.columns([3, 2])

with col_a:
    st.markdown("### Claims Volume by High-Risk Category")
    if not cat_df.empty:
        chart = alt.Chart(cat_df).mark_bar(
            cornerRadiusTopRight=6, cornerRadiusTopLeft=6
        ).encode(
            x=alt.X("HIGH_RISK_CATEGORY:N", sort="-y", title=None,
                     axis=alt.Axis(labelAngle=-35, labelFontSize=11)),
            y=alt.Y("CLAIM_COUNT:Q", title="Claim Lines"),
            color=alt.value("#29B5E8"),
            tooltip=["HIGH_RISK_CATEGORY", "CLAIM_COUNT", "TOTAL_PAID",
                     "PROVIDER_COUNT", "MEMBER_COUNT"],
        ).properties(height=350).configure_view(strokeWidth=0).configure_axis(
            gridColor="rgba(255,255,255,0.05)", labelColor="#8892b0", titleColor="#8892b0"
        )
        st.altair_chart(chart, use_container_width=True)

with col_b:
    st.markdown("### Financial Exposure by Category")
    if not cat_df.empty:
        pie = alt.Chart(cat_df).mark_arc(innerRadius=50, outerRadius=120).encode(
            theta=alt.Theta("TOTAL_PAID:Q"),
            color=alt.Color("HIGH_RISK_CATEGORY:N",
                legend=alt.Legend(title="Category")),
            tooltip=["HIGH_RISK_CATEGORY", "TOTAL_PAID"],
        ).properties(height=350).configure_view(strokeWidth=0)
        st.altair_chart(pie, use_container_width=True)

# Timeline
st.markdown("### Claims Trend Over Time")
timeline_df = session.sql("""
    SELECT DATE_TRUNC('week', SERVICE_DATE) AS WEEK,
           HIGH_RISK_CATEGORY,
           COUNT(*) AS CLAIM_COUNT,
           SUM(AMOUNT_PAID) AS TOTAL_PAID
    FROM DST_SIU_DB.RAW_DATA.SIU_CLAIMS
    WHERE HIGH_RISK_CATEGORY IS NOT NULL
    GROUP BY DATE_TRUNC('week', SERVICE_DATE), HIGH_RISK_CATEGORY
    ORDER BY WEEK
""").to_pandas()

if not timeline_df.empty:
    line = alt.Chart(timeline_df).mark_area(
        opacity=0.7, interpolate="monotone"
    ).encode(
        x=alt.X("WEEK:T", title="Week"),
        y=alt.Y("TOTAL_PAID:Q", title="Total Paid ($)", stack=True),
        color=alt.Color("HIGH_RISK_CATEGORY:N", title="Category"),
        tooltip=["WEEK", "HIGH_RISK_CATEGORY", "CLAIM_COUNT", "TOTAL_PAID"],
    ).properties(height=350).configure_view(strokeWidth=0).configure_axis(
        gridColor="rgba(255,255,255,0.05)", labelColor="#8892b0", titleColor="#8892b0"
    )
    st.altair_chart(line, use_container_width=True)

# Category detail table
st.markdown("### Category Summary Table")
if not cat_df.empty:
    st.dataframe(cat_df, use_container_width=True,
        column_config={
            "TOTAL_PAID": st.column_config.NumberColumn(format="$%.2f"),
            "AVG_MINUTES": st.column_config.NumberColumn(format="%.0f min"),
        })

st.markdown("---")
render_nav_buttons("Claims Explorer")
