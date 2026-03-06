"""
SIU Nexus — Geospatial Distance Anomalies
Same-day services for the same member at locations >50 miles apart.
"""
import streamlit as st
import pandas as pd
import altair as alt

st.set_page_config(page_title="Geospatial | SIU Nexus", page_icon="🛡️", layout="wide")

from utils.styles import apply_styles, render_header, render_metric_card, SEVERITY_COLORS
from utils.navigation import render_sidebar, render_nav_buttons, get_snowflake_session, get_severity_filter

apply_styles()
render_sidebar("Geospatial")

render_header("📍 Geospatial Distance Anomalies", "Same-day services for the same member at locations >50 miles apart")


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
    SELECT * FROM DST_SIU_DB.ANALYTICS.DT_GEOSPATIAL_ANOMALIES
    ORDER BY DISTANCE_MILES DESC
""").to_pandas()

if df.empty:
    st.info("No geospatial anomalies detected.")
else:
    if severity_filter:
        df = df[df["SEVERITY"].isin(severity_filter)]

    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.markdown(render_metric_card(f"{len(df):,}", "Distance Anomalies", accent="#FF6B6B"), unsafe_allow_html=True)
    with col2:
        st.markdown(render_metric_card(f"{df['DISTANCE_MILES'].max():.0f} mi", "Max Distance", accent="#FF6B6B"), unsafe_allow_html=True)
    with col3:
        st.markdown(render_metric_card(f"{df['DISTANCE_MILES'].mean():.0f} mi", "Avg Distance", accent="#FFB74D"), unsafe_allow_html=True)
    with col4:
        st.markdown(render_metric_card(format_currency(df["COMBINED_PAID"].sum()), "Total $ at Risk", accent="#29B5E8"), unsafe_allow_html=True)

    st.markdown("---")

    # Distance histogram
    st.markdown("### Distance Distribution (miles between same-day services)")
    hist = alt.Chart(df).mark_bar(
        cornerRadiusTopRight=4, cornerRadiusTopLeft=4
    ).encode(
        x=alt.X("DISTANCE_MILES:Q", bin=alt.Bin(maxbins=15), title="Distance (miles)"),
        y=alt.Y("count()", title="Number of Anomalies"),
        color=alt.Color("SEVERITY:N",
            scale=alt.Scale(
                domain=list(SEVERITY_COLORS.keys()),
                range=list(SEVERITY_COLORS.values()),
            )),
    ).properties(height=300).configure_view(strokeWidth=0).configure_axis(
        gridColor="rgba(255,255,255,0.05)", labelColor="#8892b0", titleColor="#8892b0"
    )
    st.altair_chart(hist, use_container_width=True)

    # Map visualization
    st.markdown("### Service Location Map")
    map_data = []
    for _, row in df.iterrows():
        if pd.notna(row.get("LAT_A")) and pd.notna(row.get("LON_A")):
            map_data.append({"lat": row["LAT_A"], "lon": row["LON_A"]})
        if pd.notna(row.get("LAT_B")) and pd.notna(row.get("LON_B")):
            map_data.append({"lat": row["LAT_B"], "lon": row["LON_B"]})
    if map_data:
        map_df = pd.DataFrame(map_data)
        st.map(map_df, use_container_width=True)

    st.markdown("### Anomaly Detail")
    st.dataframe(df, use_container_width=True, height=400,
        column_config={
            "DISTANCE_MILES": st.column_config.NumberColumn(format="%.1f mi"),
            "COMBINED_PAID": st.column_config.NumberColumn(format="$%.2f"),
        })

st.markdown("---")
render_nav_buttons("Geospatial")
