"""
SIU Nexus — Case Overview
SIU case management summary across all fraud domains.
"""
import streamlit as st
import pandas as pd
import altair as alt

st.set_page_config(page_title="Case Overview | SIU Nexus", page_icon="🛡️", layout="wide")

from utils.styles import apply_styles, render_header, render_metric_card
from utils.navigation import render_sidebar, render_nav_buttons, get_snowflake_session

apply_styles()
render_sidebar("Case Overview")

render_header("📋 Investigation Case Overview", "SIU case management summary across all fraud domains")


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

case_df = session.sql("""
    SELECT CASE_TYPE, SUM(TOTAL_CASES) AS TOTAL_CASES,
           SUM(TOTAL_EXPOSURE) AS TOTAL_EXPOSURE,
           SUM(TOTAL_RECOVERED) AS TOTAL_RECOVERED,
           SUM(OPEN_CASES) AS OPEN_CASES,
           SUM(HIGH_PRIORITY_CASES) AS HIGH_PRIORITY_CASES
    FROM DST_SIU_DB.ANALYTICS.SIU_CASE_SUMMARY
    GROUP BY CASE_TYPE
""").to_pandas()

fwa_df = session.sql(
    "SELECT * FROM DST_SIU_DB.ANALYTICS.FWA_FINANCIAL_SUMMARY"
).to_pandas()

if case_df.empty:
    st.info("No case data available.")
else:
    total_cases = case_df["TOTAL_CASES"].sum()
    total_exposure = case_df["TOTAL_EXPOSURE"].sum()
    total_recovered = case_df["TOTAL_RECOVERED"].sum()
    open_cases = case_df["OPEN_CASES"].sum()
    recovery_rate = (total_recovered / total_exposure * 100) if total_exposure > 0 else 0

    col1, col2, col3, col4, col5 = st.columns(5)
    with col1:
        st.markdown(render_metric_card(f"{total_cases:,.0f}", "Total Cases", accent="#29B5E8"), unsafe_allow_html=True)
    with col2:
        st.markdown(render_metric_card(f"{open_cases:,.0f}", "Open Cases", accent="#FFB74D"), unsafe_allow_html=True)
    with col3:
        st.markdown(render_metric_card(format_currency(total_exposure), "Total Exposure", accent="#FF6B6B"), unsafe_allow_html=True)
    with col4:
        st.markdown(render_metric_card(format_currency(total_recovered), "Recovered", accent="#00D4AA"), unsafe_allow_html=True)
    with col5:
        st.markdown(render_metric_card(f"{recovery_rate:.1f}%", "Recovery Rate", accent="#00D4AA"), unsafe_allow_html=True)

    st.markdown("---")

    col_a, col_b = st.columns(2)

    with col_a:
        st.markdown("### Cases by Domain")
        bar = alt.Chart(case_df).mark_bar(
            cornerRadiusTopRight=6, cornerRadiusTopLeft=6
        ).encode(
            x=alt.X("CASE_TYPE:N", title=None, axis=alt.Axis(labelAngle=-20)),
            y=alt.Y("TOTAL_CASES:Q", title="Cases"),
            color=alt.value("#29B5E8"),
            tooltip=["CASE_TYPE", "TOTAL_CASES", "TOTAL_EXPOSURE"],
        ).properties(height=300).configure_view(strokeWidth=0).configure_axis(
            gridColor="rgba(255,255,255,0.05)", labelColor="#8892b0", titleColor="#8892b0"
        )
        st.altair_chart(bar, use_container_width=True)

    with col_b:
        st.markdown("### Exposure by Domain")
        if not fwa_df.empty:
            bar2 = alt.Chart(fwa_df).mark_bar(
                cornerRadiusTopRight=6, cornerRadiusTopLeft=6
            ).encode(
                x=alt.X("DOMAIN:N", title=None, axis=alt.Axis(labelAngle=-20)),
                y=alt.Y("TOTAL_EXPOSURE:Q", title="Exposure ($)"),
                color=alt.value("#FFB74D"),
                tooltip=["DOMAIN", "TOTAL_EXPOSURE", "TOTAL_RECOVERED",
                         "RECOVERY_RATE_PCT"],
            ).properties(height=300).configure_view(strokeWidth=0).configure_axis(
                gridColor="rgba(255,255,255,0.05)", labelColor="#8892b0", titleColor="#8892b0"
            )
            st.altair_chart(bar2, use_container_width=True)

    st.markdown("### Financial Detail by Domain")
    if not fwa_df.empty:
        st.dataframe(fwa_df, use_container_width=True,
            column_config={
                "TOTAL_EXPOSURE": st.column_config.NumberColumn(format="$%.2f"),
                "TOTAL_RECOVERED": st.column_config.NumberColumn(format="$%.2f"),
                "OUTSTANDING_EXPOSURE": st.column_config.NumberColumn(format="$%.2f"),
                "AVG_EXPOSURE_PER_CASE": st.column_config.NumberColumn(format="$%.2f"),
                "CRITICAL_EXPOSURE": st.column_config.NumberColumn(format="$%.2f"),
                "RECOVERY_RATE_PCT": st.column_config.NumberColumn(format="%.1f%%"),
            })

st.markdown("---")
render_nav_buttons("Case Overview")
