"""
SIU Nexus — Service Overlap Detection
Same member receiving conflicting services on the same day (ADC+PCA, dual IRTS, etc.).
"""
import streamlit as st
import pandas as pd
import altair as alt

st.set_page_config(page_title="Service Overlaps | SIU Nexus", page_icon="🛡️", layout="wide")

from utils.styles import apply_styles, render_header, render_metric_card, SEVERITY_COLORS
from utils.navigation import render_sidebar, render_nav_buttons, get_snowflake_session, get_severity_filter

apply_styles()
render_sidebar("Service Overlaps")

render_header("🔄 Service Overlap Detection", "Same member receiving conflicting services on the same day (ADC+PCA, dual IRTS)")


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
    SELECT * FROM DST_SIU_DB.ANALYTICS.DT_SERVICE_OVERLAPS
    ORDER BY COMBINED_PAID DESC
""").to_pandas()

if df.empty:
    st.info("No service overlaps detected.")
else:
    if severity_filter:
        df = df[df["SEVERITY"].isin(severity_filter)]

    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.markdown(render_metric_card(f"{len(df):,}", "Overlap Events", accent="#FF6B6B"), unsafe_allow_html=True)
    with col2:
        st.markdown(render_metric_card(f"{df['PERSON_ID'].nunique():,}", "Members Affected", accent="#FFB74D"), unsafe_allow_html=True)
    with col3:
        st.markdown(render_metric_card(format_currency(df["COMBINED_PAID"].sum()), "Combined $ at Risk", accent="#29B5E8"), unsafe_allow_html=True)
    with col4:
        st.markdown(render_metric_card(f"{df['COMBINED_HOURS'].max():.1f}h", "Max Combined Hours", accent="#FF6B6B"), unsafe_allow_html=True)

    st.markdown("---")

    # Category pair analysis
    st.markdown("### Overlap Pairs by Service Category")
    pair_counts = df.groupby(["CATEGORY_A", "CATEGORY_B"]).agg(
        COUNT=("PERSON_ID", "size"),
        TOTAL_PAID=("COMBINED_PAID", "sum"),
    ).reset_index().sort_values("COUNT", ascending=False)

    chart = alt.Chart(pair_counts).mark_bar(
        cornerRadiusTopRight=6, cornerRadiusTopLeft=6
    ).encode(
        x=alt.X("COUNT:Q", title="Number of Overlaps"),
        y=alt.Y("CATEGORY_A:N", title=None, sort="-x"),
        color=alt.Color("CATEGORY_B:N", title="Paired Category"),
        tooltip=["CATEGORY_A", "CATEGORY_B", "COUNT", "TOTAL_PAID"],
    ).properties(height=300).configure_view(strokeWidth=0).configure_axis(
        gridColor="rgba(255,255,255,0.05)", labelColor="#8892b0", titleColor="#8892b0"
    )
    st.altair_chart(chart, use_container_width=True)

    st.markdown("### Overlap Detail")
    st.dataframe(df, use_container_width=True, height=400,
        column_config={
            "COMBINED_PAID": st.column_config.NumberColumn(format="$%.2f"),
            "COMBINED_HOURS": st.column_config.NumberColumn(format="%.1f"),
        })

st.markdown("---")
render_nav_buttons("Service Overlaps")
