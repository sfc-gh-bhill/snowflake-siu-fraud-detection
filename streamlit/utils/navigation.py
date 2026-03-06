# ==============================================================================
# DST SIU NEXUS - Navigation System with Collapsible Sections & Back/Forward
# Adapted from DST HUB navigation patterns
# ==============================================================================
import streamlit as st
from utils.styles import SNOWFLAKE_LOGO_BYTES, CLIENT_LOGO_BYTES

# Page registry: (file_path, display_label, tooltip)
PAGE_SECTIONS = {
    "Anomaly Detection": [
        ("pages/01_Anomaly_Triage.py", "Anomaly Triage", "Unified view across all 6 detection engines"),
        ("pages/02_Temporal_Analysis.py", "Temporal Analysis", "Providers billing >24 hours/day"),
        ("pages/03_EIDBI_Ratios.py", "EIDBI Ratios", "97155/97153 supervision ratio monitoring"),
        ("pages/04_Service_Overlaps.py", "Service Overlaps", "Conflicting same-day services (ADC+PCA, dual IRTS)"),
    ],
    "Investigation": [
        ("pages/05_Geospatial.py", "Geospatial", "Same-day services >50 miles apart"),
        ("pages/06_Claims_Explorer.py", "Claims Explorer", "Drill into claims by category, provider, member"),
        ("pages/07_Case_Overview.py", "Case Overview", "SIU case management across all fraud domains"),
    ],
}

# Flat ordered list for back/forward navigation
ALL_PAGES = [("streamlit_app.py", "Home", "SIU Nexus command center")]
for _section_pages in PAGE_SECTIONS.values():
    ALL_PAGES.extend(_section_pages)


def get_current_page_index(current_label: str) -> int:
    """Get the index of the current page in the flat list."""
    for i, (_, label, *_) in enumerate(ALL_PAGES):
        if label == current_label:
            return i
    return 0


def render_sidebar(current_page: str = "Home"):
    """Render the full sidebar with branding, collapsible nav sections, and footer."""
    # Branding — dual logos
    sb_logo_cols = st.sidebar.columns([1, 1])
    with sb_logo_cols[0]:
        if SNOWFLAKE_LOGO_BYTES:
            st.image(SNOWFLAKE_LOGO_BYTES, width=40)
    with sb_logo_cols[1]:
        if CLIENT_LOGO_BYTES:
            st.image(CLIENT_LOGO_BYTES, width=120)

    st.sidebar.markdown("""
    <div style="padding: 0 0.75rem 0.75rem 0.75rem;">
        <div style="color: #FFFFFF; font-size: 1.1rem; font-weight: 700; letter-spacing: 3px;
                    text-transform: uppercase; margin: 0.25rem 0 0 0; line-height: 1.2;">
            SNOWFLAKE
        </div>
        <div style="color: #8892b0; font-size: 0.65rem; font-weight: 600; letter-spacing: 2px;
                    text-transform: uppercase; margin-top: 0.1rem; padding-bottom: 0.5rem;
                    border-bottom: 2px solid #29B5E8;">
            SOLUTION ENGINEERING
        </div>
        <div style="color: #FF6B6B; font-size: 1.05rem; font-weight: 700; margin-top: 0.75rem;">
            SIU NEXUS
        </div>
        <div style="color: #8892b0; font-size: 0.7rem; margin-top: 0.1rem;">
            Special Investigations Unit &mdash; Fraud Detection
        </div>
    </div>
    """, unsafe_allow_html=True)

    # Home link
    st.sidebar.page_link("streamlit_app.py", label="◈  Home", use_container_width=True)

    # Collapsible sections
    for section_name, pages in PAGE_SECTIONS.items():
        page_labels = [p[1] for p in pages]
        with st.sidebar.expander(f"**{section_name}**", expanded=(current_page in page_labels)):
            for page_path, page_label, tooltip in pages:
                st.page_link(
                    page_path,
                    label=f"  {page_label}",
                    help=tooltip,
                    use_container_width=True,
                )

    # Global severity filter (shared via session state)
    st.sidebar.markdown("---")
    st.sidebar.markdown(
        '<p style="color:#29B5E8;font-weight:600;font-size:0.85rem;letter-spacing:1px;">FILTERS</p>',
        unsafe_allow_html=True,
    )
    severity_filter = st.sidebar.multiselect(
        "Severity",
        ["CRITICAL", "HIGH", "MEDIUM", "LOW"],
        default=["CRITICAL", "HIGH"],
        label_visibility="collapsed",
    )
    st.session_state["severity_filter"] = severity_filter

    # Footer
    st.sidebar.markdown("---")
    try:
        from snowflake.snowpark.context import get_active_session
        get_active_session()
        status_color, status_text = "#4ECDC4", "Snowflake Connected"
    except Exception:
        status_color, status_text = "#FFB74D", "Running Locally"

    st.sidebar.markdown(f"""
    <div style="padding: 0.5rem 0.75rem;">
        <div style="display: flex; align-items: center; gap: 0.4rem;">
            <div style="width: 8px; height: 8px; border-radius: 50%; background: {status_color};"></div>
            <span style="color: {status_color}; font-size: 0.75rem; font-weight: 600;">{status_text}</span>
        </div>
        <div style="color: #8892b0; font-size: 0.6rem; margin-top: 0.5rem;">
            SIU Nexus v2.0 &bull; POWERED BY SNOWFLAKE CORTEX
        </div>
    </div>
    """, unsafe_allow_html=True)


def render_nav_buttons(current_page: str):
    """Render back/forward navigation buttons at the bottom of the page."""
    idx = get_current_page_index(current_page)
    prev_page = ALL_PAGES[idx - 1] if idx > 0 else None
    next_page = ALL_PAGES[idx + 1] if idx < len(ALL_PAGES) - 1 else None

    col1, col2, col3 = st.columns([1, 2, 1])
    with col1:
        if prev_page:
            st.page_link(prev_page[0], label=f"← {prev_page[1]}", use_container_width=True)
    with col2:
        st.markdown(
            f'<div style="text-align:center;color:#8892b0;font-size:0.75rem;padding-top:0.5rem;">'
            f'Page {idx + 1} of {len(ALL_PAGES)}</div>',
            unsafe_allow_html=True,
        )
    with col3:
        if next_page:
            st.page_link(next_page[0], label=f"{next_page[1]} →", use_container_width=True)


def get_snowflake_session():
    """Get Snowflake session with graceful fallback."""
    try:
        from snowflake.snowpark.context import get_active_session
        return get_active_session()
    except Exception:
        try:
            from snowflake.snowpark import Session
            import os
            creds_path = os.path.expanduser("~/.snowflake/connections.toml")
            if os.path.exists(creds_path):
                return Session.builder.configs({"connection_name": "DEMO"}).create()
        except Exception:
            pass
    return None


def get_severity_filter() -> list:
    """Get the current severity filter from session state."""
    return st.session_state.get("severity_filter", ["CRITICAL", "HIGH"])
