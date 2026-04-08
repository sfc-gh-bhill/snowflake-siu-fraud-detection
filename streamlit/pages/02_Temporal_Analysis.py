# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Braedon Hill

"""
SIU Nexus — Temporal Analysis
Providers billing more than 24 hours of services in a single calendar day.
"""
import streamlit as st
import pandas as pd
import altair as alt

st.set_page_config(page_title="Temporal Analysis | SIU Nexus", page_icon="🛡️", layout="wide")

from utils.styles import apply_styles, render_header, render_metric_card, SEVERITY_COLORS
from utils.navigation import render_sidebar, render_nav_buttons, get_snowflake_session, get_severity_filter

apply_styles()
render_sidebar("Temporal Analysis")

render_header("⏱️ Temporal Impossibility Detection", "Providers billing more than 24 hours of services in a single calendar day")


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

severity_filter = get_severity_filter()

df = session.sql("""
    SELECT * FROM DST_SIU_DB.ANALYTICS.DT_TEMPORAL_IMPOSSIBILITY
    ORDER BY TOTAL_HOURS DESC
""").to_pandas()

if df.empty:
    st.info("No temporal impossibilities detected.")
else:
    if severity_filter:
        df = df[df["SEVERITY"].isin(severity_filter)]

    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.markdown(render_metric_card(f"{len(df):,}", "Impossible Days", accent="#FF6B6B"), unsafe_allow_html=True)
    with col2:
        st.markdown(render_metric_card(f"{df['TOTAL_HOURS'].max():.1f}h", "Max Hours/Day", accent="#FF6B6B"), unsafe_allow_html=True)
    with col3:
        st.markdown(render_metric_card(f"{df['NPI'].nunique():,}", "Flagged Providers", accent="#FFB74D"), unsafe_allow_html=True)
    with col4:
        st.markdown(render_metric_card(format_currency(df["TOTAL_PAID"].sum()), "Total $ at Risk", accent="#29B5E8"), unsafe_allow_html=True)

    st.markdown("---")

    # Histogram
    st.markdown("### Distribution of Daily Hours Billed (Flagged Days)")
    hist = alt.Chart(df).mark_bar(
        cornerRadiusTopRight=4, cornerRadiusTopLeft=4
    ).encode(
        x=alt.X("TOTAL_HOURS:Q", bin=alt.Bin(maxbins=20), title="Total Hours Billed in Day"),
        y=alt.Y("count()", title="Number of Provider-Days"),
        color=alt.value("#FFB74D"),
    ).properties(height=300).configure_view(strokeWidth=0).configure_axis(
        gridColor="rgba(255,255,255,0.05)", labelColor="#8892b0", titleColor="#8892b0"
    )
    st.altair_chart(hist, use_container_width=True)

    # Top offenders
    st.markdown("### Top Offending Providers")
    top = df.groupby(["NPI", "NPI_NAME"]).agg(
        IMPOSSIBLE_DAYS=("SERVICE_DATE", "nunique"),
        MAX_HOURS=("TOTAL_HOURS", "max"),
        TOTAL_PAID=("TOTAL_PAID", "sum"),
    ).reset_index().sort_values("IMPOSSIBLE_DAYS", ascending=False).head(20)

    st.dataframe(
        top, use_container_width=True,
        column_config={
            "TOTAL_PAID": st.column_config.NumberColumn(format="$%.2f"),
            "MAX_HOURS": st.column_config.NumberColumn(format="%.1f hrs"),
        },
    )

    st.markdown("### Full Detail")
    st.dataframe(df, use_container_width=True, height=400,
        column_config={
            "TOTAL_PAID": st.column_config.NumberColumn(format="$%.2f"),
            "TOTAL_HOURS": st.column_config.NumberColumn(format="%.1f"),
        })

st.markdown("---")
render_nav_buttons("Temporal Analysis")
