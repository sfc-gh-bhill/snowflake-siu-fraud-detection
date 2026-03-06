"""
SIU Nexus — EIDBI Supervision Ratio Monitoring
State regulations require 97155 supervision hours <= 10% of 97153 direct service hours.
"""
import streamlit as st
import pandas as pd
import altair as alt

st.set_page_config(page_title="EIDBI Ratios | SIU Nexus", page_icon="🛡️", layout="wide")

from utils.styles import apply_styles, render_header, render_metric_card, SEVERITY_COLORS
from utils.navigation import render_sidebar, render_nav_buttons, get_snowflake_session, get_severity_filter

apply_styles()
render_sidebar("EIDBI Ratios")

render_header("📊 EIDBI Supervision Ratio Monitoring", "State regulations require 97155 supervision hours ≤ 10% of 97153 direct service hours")


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
    SELECT * FROM DST_SIU_DB.ANALYTICS.DT_EIDBI_RATIO_VIOLATIONS
    ORDER BY SUPERVISION_RATIO_PCT DESC NULLS LAST
""").to_pandas()

if df.empty:
    st.info("No EIDBI ratio violations detected.")
else:
    if severity_filter:
        df = df[df["SEVERITY"].isin(severity_filter)]

    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.markdown(render_metric_card(f"{len(df):,}", "Violations", accent="#FF6B6B"), unsafe_allow_html=True)
    with col2:
        max_ratio = df["SUPERVISION_RATIO_PCT"].max()
        val = f"{max_ratio:.1f}%" if pd.notna(max_ratio) else "N/A"
        st.markdown(render_metric_card(val, "Max Ratio", accent="#FF6B6B"), unsafe_allow_html=True)
    with col3:
        st.markdown(render_metric_card(f"{df['NPI'].nunique():,}", "Providers", accent="#FFB74D"), unsafe_allow_html=True)
    with col4:
        st.markdown(render_metric_card(format_currency(df["SUPERVISION_PAID_97155"].sum()), "Supervision $", accent="#29B5E8"), unsafe_allow_html=True)

    st.markdown("---")

    # Scatter plot
    st.markdown("### Supervision Ratio by Provider-Month")
    valid = df[df["SUPERVISION_RATIO_PCT"].notna()].copy()
    if not valid.empty:
        scatter = alt.Chart(valid).mark_circle(size=80).encode(
            x=alt.X("DIRECT_HOURS_97153:Q", title="Direct Service Hours (97153)"),
            y=alt.Y("SUPERVISION_HOURS_97155:Q", title="Supervision Hours (97155)"),
            color=alt.Color("SEVERITY:N",
                scale=alt.Scale(
                    domain=list(SEVERITY_COLORS.keys()),
                    range=list(SEVERITY_COLORS.values()),
                )),
            size=alt.Size("SUPERVISION_RATIO_PCT:Q", title="Ratio %"),
            tooltip=["NPI_NAME", "SERVICE_MONTH", "SUPERVISION_RATIO_PCT",
                     "DIRECT_HOURS_97153", "SUPERVISION_HOURS_97155"],
        ).properties(height=400)

        # 10% rule line
        max_direct = valid["DIRECT_HOURS_97153"].max()
        rule_df = pd.DataFrame({"x": [0, max_direct], "y": [0, max_direct * 0.10]})
        rule_line = alt.Chart(rule_df).mark_line(
            strokeDash=[5, 5], color="#FF6B6B", strokeWidth=2
        ).encode(x="x:Q", y="y:Q")

        combined = (scatter + rule_line).configure_view(strokeWidth=0).configure_axis(
            gridColor="rgba(255,255,255,0.05)", labelColor="#8892b0", titleColor="#8892b0"
        )
        st.altair_chart(combined, use_container_width=True)

    st.markdown("### Violation Detail")
    st.dataframe(df, use_container_width=True, height=400,
        column_config={
            "SUPERVISION_RATIO_PCT": st.column_config.NumberColumn(format="%.1f%%"),
            "DIRECT_PAID_97153": st.column_config.NumberColumn(format="$%.2f"),
            "SUPERVISION_PAID_97155": st.column_config.NumberColumn(format="$%.2f"),
        })

st.markdown("---")
render_nav_buttons("EIDBI Ratios")
