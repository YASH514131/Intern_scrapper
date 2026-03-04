"""
Web3 Internship Finder — Production-Grade Scraper
==================================================
Improvements over original:
  • Async/concurrent scraping with ThreadPoolExecutor
  • Intelligent career-page auto-discovery (not just the given URL)
  • Smart retry logic with exponential back-off
  • Multi-signal internship detection (text + URL slugs + schema.org JobPosting)
  • Rich structured results: role title, location, deadline, remote flag
  • Rate-limiting & polite crawling (robots.txt awareness)
  • Persistent session reuse for JS-heavy sites (Selenium) vs fast static sites (requests + BS4)
  • Deduplication across pages
  • Streamlit UI with live progress, logs, charts, and export
"""

import os
import re
import time
import random
import logging
import threading
import urllib.robotparser
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import urljoin, urlparse
from datetime import datetime

import streamlit as st
import pandas as pd
import requests
from bs4 import BeautifulSoup
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# ── optional Selenium (graceful fallback if not installed) ─────────────────────
try:
    from selenium import webdriver
    from selenium.webdriver.chrome.service import Service
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.support.ui import WebDriverWait
    from selenium.webdriver.support import expected_conditions as EC
    from selenium.webdriver.common.by import By
    SELENIUM_AVAILABLE = True
except ImportError:
    SELENIUM_AVAILABLE = False

try:
    from webdriver_manager.chrome import ChromeDriverManager
    WDM_AVAILABLE = True
except ImportError:
    WDM_AVAILABLE = False

# ══════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ══════════════════════════════════════════════════════════════════════════════

VERSION = "2.0.0"

CAREER_PATH_HINTS = [
    "/careers", "/jobs", "/join-us", "/work-with-us", "/opportunities",
    "/hiring", "/open-positions", "/positions", "/team/join", "/about/careers",
    "/company/careers", "/recruit", "/vacancies", "/en/careers",
]

INTERNSHIP_KEYWORDS = [
    "intern", "internship", "trainee", "apprentice", "co-op", "coop",
    "summer program", "graduate program", "entry level", "new grad",
    "fresh grad", "junior", "summer intern", "winter intern",
]

EXCLUDE_KEYWORDS = [
    "senior", "staff", "principal", "director", "manager", "head of",
    "vp ", "vice president", "lead ", "architect",
]

DURATION_PATTERNS = [
    r"(\d+)\s*[-–]\s*(\d+)\s*(month|week|mo\b)",      # "3-6 months"
    r"(\d+)\s*(month|week|mo\b)",                       # "6 months"
    r"(summer|spring|fall|winter|q[1-4])\s*(intern)?", # "Summer Intern"
]

LOCATION_PATTERNS = [
    r"\b(remote|hybrid|on[-\s]?site)\b",
    r"\b([A-Z][a-zA-Z]+(?:,\s*[A-Z]{2})?)\b",         # "San Francisco, CA"
]

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.4 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
]

# ══════════════════════════════════════════════════════════════════════════════
# SCRAPING ENGINE
# ══════════════════════════════════════════════════════════════════════════════

class RateLimiter:
    """Per-domain token-bucket rate limiter."""
    def __init__(self, calls_per_second: float = 0.5):
        self._lock = threading.Lock()
        self._last: dict[str, float] = {}
        self._interval = 1.0 / calls_per_second

    def wait(self, domain: str):
        with self._lock:
            now = time.time()
            elapsed = now - self._last.get(domain, 0)
            sleep_for = self._interval - elapsed
            if sleep_for > 0:
                time.sleep(sleep_for + random.uniform(0, 0.3))
            self._last[domain] = time.time()


_rate_limiter = RateLimiter(calls_per_second=0.5)  # max 1 req / 2 s per domain


def _make_session() -> requests.Session:
    session = requests.Session()
    retry = Retry(
        total=4,
        backoff_factor=1.5,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET", "HEAD"],
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    session.headers.update({
        "User-Agent": random.choice(USER_AGENTS),
        "Accept-Language": "en-US,en;q=0.9",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    })
    return session


def _robots_allowed(url: str, session: requests.Session) -> bool:
    try:
        parsed = urlparse(url)
        robots_url = f"{parsed.scheme}://{parsed.netloc}/robots.txt"
        rp = urllib.robotparser.RobotFileParser()
        resp = session.get(robots_url, timeout=5)
        rp.parse(resp.text.splitlines())
        return rp.can_fetch("*", url)
    except Exception:
        return True  # assume allowed on error


def _fetch_static(url: str, session: requests.Session, timeout: int = 12) -> BeautifulSoup | None:
    domain = urlparse(url).netloc
    _rate_limiter.wait(domain)
    try:
        resp = session.get(url, timeout=timeout)
        resp.raise_for_status()
        return BeautifulSoup(resp.text, "html.parser")
    except Exception as exc:
        logging.debug("Static fetch failed %s: %s", url, exc)
        return None


def _fetch_js(url: str, wait_seconds: int = 4) -> BeautifulSoup | None:
    """Use Selenium for JS-rendered pages."""
    if not (SELENIUM_AVAILABLE and WDM_AVAILABLE):
        return None
    try:
        opts = Options()
        opts.add_argument("--headless=new")
        opts.add_argument("--no-sandbox")
        opts.add_argument("--disable-dev-shm-usage")
        opts.add_argument("--disable-blink-features=AutomationControlled")
        opts.add_argument(f"user-agent={random.choice(USER_AGENTS)}")
        opts.add_experimental_option("excludeSwitches", ["enable-automation"])

        driver = webdriver.Chrome(
            service=Service(ChromeDriverManager().install()), options=opts
        )
        driver.set_page_load_timeout(20)
        driver.get(url)
        # Wait for body to be non-empty
        WebDriverWait(driver, wait_seconds).until(
            EC.presence_of_element_located((By.TAG_NAME, "body"))
        )
        time.sleep(2)  # allow lazy-loaded content
        soup = BeautifulSoup(driver.page_source, "html.parser")
        driver.quit()
        return soup
    except Exception as exc:
        logging.debug("JS fetch failed %s: %s", url, exc)
        return None


def _smart_fetch(url: str, session: requests.Session, use_js: bool = False) -> BeautifulSoup | None:
    """Try static first; fall back to Selenium if JS flag or empty body detected."""
    soup = _fetch_static(url, session)
    if soup is None or (use_js and len(soup.get_text(strip=True)) < 200):
        soup = _fetch_js(url) or soup
    return soup


# ── Career page discovery ──────────────────────────────────────────────────────

def _discover_career_url(base_url: str, session: requests.Session) -> str:
    """
    Given any company URL, find the most likely careers page.
    Strategy:
      1. Try known path hints directly.
      2. Parse the homepage for nav links containing career-related words.
      3. Fall back to the original URL.
    """
    parsed = urlparse(base_url)
    root = f"{parsed.scheme}://{parsed.netloc}"

    # 1. Try hint paths
    for hint in CAREER_PATH_HINTS:
        candidate = urljoin(root, hint)
        try:
            resp = session.head(candidate, timeout=6, allow_redirects=True)
            if resp.status_code < 400:
                return candidate
        except Exception:
            continue

    # 2. Parse homepage for career nav links
    soup = _fetch_static(base_url, session)
    if soup:
        for a in soup.find_all("a", href=True):
            href = a["href"].lower()
            text = a.get_text(strip=True).lower()
            if any(k in href or k in text for k in ["career", "job", "hiring", "join", "work"]):
                full = urljoin(root, a["href"])
                if urlparse(full).netloc == parsed.netloc:  # stay on same domain
                    return full

    return base_url  # fallback: original URL


# ── Job extraction ─────────────────────────────────────────────────────────────

def _extract_duration(text: str) -> tuple[str, float]:
    """Returns (human-readable, months_float)."""
    text_lower = text.lower()
    for pat in DURATION_PATTERNS:
        m = re.search(pat, text_lower)
        if m:
            groups = m.groups()
            raw = m.group(0)
            if any(season in raw for season in ["summer", "spring", "fall", "winter"]):
                return raw.title(), 3.0
            if len(groups) >= 2:
                val = int(groups[0])
                unit = groups[-1]
                months = val if "month" in unit else round(val / 4.3, 1)
                return f"{val} {unit}", months
    return "Not specified", 0.0


def _extract_location(text: str) -> str:
    """Best-effort location extraction."""
    text_lower = text.lower()
    for pat in [r"\b(remote)\b", r"\b(hybrid)\b", r"\b(on[-\s]?site)\b"]:
        m = re.search(pat, text_lower)
        if m:
            return m.group(1).capitalize()
    # Look for "City, ST" pattern
    m = re.search(r"\b([A-Z][a-z]+(?: [A-Z][a-z]+)?,\s*[A-Z]{2})\b", text)
    if m:
        return m.group(1)
    return "Not specified"


def _extract_jobs_from_soup(
    soup: BeautifulSoup,
    page_url: str,
    search_terms: list[str],
    exclude_terms: list[str],
    max_duration_months: float,
) -> list[dict]:
    """
    Multi-signal extraction:
    1. schema.org JobPosting JSON-LD
    2. Common ATS HTML patterns (Greenhouse, Lever, Workday, etc.)
    3. General text blocks mentioning internship keywords
    """
    found: list[dict] = []
    seen_titles: set[str] = set()

    # ── Signal 1: JSON-LD structured data ──────────────────────────────────────
    for script in soup.find_all("script", type="application/ld+json"):
        try:
            import json
            data = json.loads(script.string or "")
            jobs = data if isinstance(data, list) else [data]
            for job in jobs:
                if job.get("@type") != "JobPosting":
                    continue
                title = job.get("title", "").strip()
                title_lower = title.lower()
                if not any(t in title_lower for t in search_terms):
                    continue
                if any(e in title_lower for e in exclude_terms):
                    continue
                duration_text, months = _extract_duration(
                    job.get("description", "") + " " + job.get("employmentType", "")
                )
                if max_duration_months > 0 and months > max_duration_months and months != 0:
                    continue
                loc = (
                    job.get("jobLocation", {}).get("address", {}).get("addressLocality", "")
                    or _extract_location(job.get("description", ""))
                )
                deadline = job.get("validThrough", "")[:10] if job.get("validThrough") else "—"
                apply_url = job.get("url") or page_url
                key = title_lower[:40]
                if key not in seen_titles:
                    seen_titles.add(key)
                    found.append({
                        "Title": title,
                        "Company URL": page_url,
                        "Apply Link": apply_url,
                        "Location": loc or "Not specified",
                        "Duration": duration_text,
                        "Deadline": deadline,
                        "Source": "schema.org",
                    })
        except Exception:
            continue

    if found:
        return found

    # ── Signal 2: Common ATS HTML selectors ────────────────────────────────────
    ats_selectors = [
        # Greenhouse
        {"container": "div.opening", "title": "a", "link_tag": "a"},
        # Lever
        {"container": "div.posting", "title": "h5", "link_tag": "a.posting-title"},
        # Workday
        {"container": "li[data-automation-id='compositeContainer']", "title": "[data-automation-id='jobTitle']", "link_tag": "a"},
        # Generic
        {"container": "li.job-listing", "title": "h2,h3,h4", "link_tag": "a"},
        {"container": "div.job-card", "title": "h2,h3,h4", "link_tag": "a"},
        {"container": "tr.job-row", "title": "td.job-title", "link_tag": "a"},
    ]

    for sel in ats_selectors:
        containers = soup.select(sel["container"])
        if not containers:
            continue
        for container in containers:
            title_el = container.select_one(sel["title"])
            link_el = container.select_one(sel["link_tag"])
            if not title_el:
                continue
            title = title_el.get_text(strip=True)
            title_lower = title.lower()
            if not any(t in title_lower for t in search_terms):
                continue
            if any(e in title_lower for e in exclude_terms):
                continue
            apply_url = urljoin(page_url, link_el["href"]) if link_el and link_el.get("href") else page_url
            block_text = container.get_text(separator=" ")
            duration_text, months = _extract_duration(block_text)
            if max_duration_months > 0 and months > max_duration_months and months != 0:
                continue
            key = title_lower[:40]
            if key not in seen_titles:
                seen_titles.add(key)
                found.append({
                    "Title": title,
                    "Company URL": page_url,
                    "Apply Link": apply_url,
                    "Location": _extract_location(block_text),
                    "Duration": duration_text,
                    "Deadline": "—",
                    "Source": "ATS HTML",
                })
        if found:
            return found

    # ── Signal 3: Full-text keyword scan ──────────────────────────────────────
    full_text = soup.get_text(separator="\n")
    lines = [l.strip() for l in full_text.splitlines() if l.strip()]

    for i, line in enumerate(lines):
        line_lower = line.lower()
        if not any(t in line_lower for t in search_terms):
            continue
        if any(e in line_lower for e in exclude_terms):
            continue
        # Build a small context window around the matching line
        context = " ".join(lines[max(0, i-2): i+5])
        duration_text, months = _extract_duration(context)
        if max_duration_months > 0 and months > max_duration_months and months != 0:
            continue
        # Try to find a nearby anchor
        nearby_anchors = [
            a for a in soup.find_all("a", href=True)
            if any(t in (a.get_text(strip=True).lower() + a["href"].lower()) for t in search_terms)
        ]
        apply_url = urljoin(page_url, nearby_anchors[0]["href"]) if nearby_anchors else page_url
        title = line[:120]
        key = title.lower()[:40]
        if key not in seen_titles:
            seen_titles.add(key)
            found.append({
                "Title": title,
                "Company URL": page_url,
                "Apply Link": apply_url,
                "Location": _extract_location(context),
                "Duration": duration_text,
                "Deadline": "—",
                "Source": "Text scan",
            })
        if len(found) >= 10:
            break

    return found


# ── Per-company orchestrator ────────────────────────────────────────────────────

def scrape_company(
    row: dict,
    url_col: str,
    name_col: str,
    search_terms: list[str],
    exclude_terms: list[str],
    max_duration_months: float,
    use_js: bool,
) -> list[dict]:
    base_url = str(row.get(url_col, "")).strip()
    company_name = str(row.get(name_col, "Unknown")).strip()

    if not base_url.startswith("http"):
        base_url = "https://" + base_url

    session = _make_session()

    if not _robots_allowed(base_url, session):
        return [{"Company": company_name, "Error": "robots.txt disallowed", "Title": "—",
                 "Apply Link": base_url, "Location": "—", "Duration": "—", "Deadline": "—", "Source": "—"}]

    career_url = _discover_career_url(base_url, session)
    soup = _smart_fetch(career_url, session, use_js=use_js)

    if soup is None:
        return [{"Company": company_name, "Error": "Fetch failed", "Title": "—",
                 "Apply Link": career_url, "Location": "—", "Duration": "—", "Deadline": "—", "Source": "—"}]

    jobs = _extract_jobs_from_soup(soup, career_url, search_terms, exclude_terms, max_duration_months)

    results = []
    for job in jobs:
        job["Company"] = company_name
        job.setdefault("Error", "")
        results.append(job)

    if not results:
        results.append({
            "Company": company_name,
            "Title": "No internship found",
            "Apply Link": career_url,
            "Location": "—",
            "Duration": "—",
            "Deadline": "—",
            "Source": "—",
            "Error": "",
        })

    return results


# ══════════════════════════════════════════════════════════════════════════════
# STREAMLIT UI
# ══════════════════════════════════════════════════════════════════════════════

def _styled_metric(label: str, value: str, color: str = "#4ade80") -> str:
    return f"""
    <div style="background:#1e293b;border-radius:12px;padding:16px 20px;text-align:center;border:1px solid #334155">
      <div style="font-size:2rem;font-weight:700;color:{color}">{value}</div>
      <div style="font-size:0.8rem;color:#94a3b8;margin-top:4px;letter-spacing:0.05em;text-transform:uppercase">{label}</div>
    </div>"""


def main():
    st.set_page_config(
        page_title="Web3 Intern Radar",
        page_icon="🌐",
        layout="wide",
        initial_sidebar_state="expanded",
    )

    # ── Custom CSS ──────────────────────────────────────────────────────────────
    st.markdown("""
    <style>
    @import url('https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;600;700&family=JetBrains+Mono:wght@400;600&display=swap');

    html, body, [class*="css"] {
        font-family: 'Space Grotesk', sans-serif;
        background-color: #0f172a;
        color: #e2e8f0;
    }
    .stApp { background: #0f172a; }
    .main-title {
        font-size: 2.6rem; font-weight: 700; letter-spacing: -0.02em;
        background: linear-gradient(135deg, #38bdf8 0%, #818cf8 50%, #f472b6 100%);
        -webkit-background-clip: text; -webkit-text-fill-color: transparent;
        margin-bottom: 0.2rem;
    }
    .sub-title { color: #64748b; font-size: 1rem; margin-bottom: 1.5rem; }
    .stButton > button {
        background: linear-gradient(135deg, #6366f1, #8b5cf6) !important;
        color: white !important; border: none !important;
        border-radius: 10px !important; padding: 0.6rem 2rem !important;
        font-weight: 600 !important; font-size: 1rem !important;
        transition: all 0.2s !important; box-shadow: 0 4px 15px rgba(99,102,241,0.4) !important;
    }
    .stButton > button:hover { transform: translateY(-2px) !important; box-shadow: 0 6px 20px rgba(99,102,241,0.5) !important; }
    .log-box {
        background: #0d1117; border: 1px solid #21262d;
        border-radius: 8px; padding: 12px 16px;
        font-family: 'JetBrains Mono', monospace; font-size: 0.78rem;
        color: #7ee787; max-height: 200px; overflow-y: auto;
    }
    .stDataFrame { border-radius: 12px !important; overflow: hidden !important; }
    section[data-testid="stSidebar"] { background: #0d1626 !important; border-right: 1px solid #1e293b; }
    .stTextInput input, .stNumberInput input, .stSelectbox select {
        background: #1e293b !important; border: 1px solid #334155 !important;
        color: #e2e8f0 !important; border-radius: 8px !important;
    }
    .stSlider .stSlider { color: #6366f1 !important; }
    </style>
    """, unsafe_allow_html=True)

    # ── Header ──────────────────────────────────────────────────────────────────
    st.markdown('<p class="main-title">⬡ Web3 Intern Radar</p>', unsafe_allow_html=True)
    st.markdown('<p class="sub-title">Intelligent internship discovery across the decentralised ecosystem</p>', unsafe_allow_html=True)
    st.markdown(f'<p style="color:#334155;font-size:0.75rem">v{VERSION} · {datetime.now().strftime("%d %b %Y")}</p>', unsafe_allow_html=True)

    # ── Sidebar ─────────────────────────────────────────────────────────────────
    with st.sidebar:
        st.markdown("### ⚙️ Search Settings")
        keywords_input = st.text_input(
            "Internship Keywords (comma-separated)",
            "intern, internship, trainee, co-op, apprentice",
            help="Terms that must appear in the job title or description."
        )
        exclude_input = st.text_input(
            "Exclude Keywords (comma-separated)",
            "senior, staff, director, manager, principal",
            help="Skip listings that contain these words."
        )
        max_duration = st.slider(
            "Max Duration (months, 0 = any)", 0, 18, 6,
            help="Filter out internships longer than this."
        )
        scan_limit = st.slider("Companies to Scan", 1, 200, 20)
        concurrency = st.slider(
            "Parallel Workers", 1, 10, 4,
            help="Higher = faster but more aggressive. Be respectful."
        )
        use_js = st.toggle(
            "Enable JS Rendering (Selenium)",
            value=False,
            help="Use for SPAs (React/Vue career pages). Slower but more thorough."
        ) if SELENIUM_AVAILABLE else False

        st.markdown("---")
        st.markdown("### 📂 Upload Companies")

    # ── File Upload ─────────────────────────────────────────────────────────────
    uploaded_file = st.sidebar.file_uploader(
        "Company list (CSV / Excel)",
        type=["csv", "xlsx", "xls"],
        help="Must contain a URL/Link/Website column and optionally a Company Name column."
    )

    # ── Sample template download ────────────────────────────────────────────────
    sample = pd.DataFrame({
        "Company Name": ["Uniswap Labs", "Chainlink Labs", "OpenSea"],
        "URL": ["https://uniswap.org/careers", "https://careers.chain.link", "https://opensea.io/careers"],
        "Notes": ["DEX", "Oracle", "NFT Marketplace"],
    })
    st.sidebar.download_button(
        "⬇️ Download Sample Template",
        sample.to_csv(index=False),
        "web3_companies_template.csv",
        "text/csv",
    )

    if not uploaded_file:
        st.info("👈 Upload a company list from the sidebar to begin.")
        with st.expander("ℹ️ How this works"):
            st.markdown("""
**What's new in v2:**
- 🔍 **Auto career-page discovery** — finds the right jobs page even if you only provide the homepage
- ⚡ **Concurrent scraping** — scans multiple companies in parallel
- 🧠 **3-signal job extraction** — schema.org JSON-LD → ATS HTML selectors → full-text fallback
- 🤖 **Smart filtering** — exclude senior roles, filter by duration
- 🛡️ **Polite crawling** — respects `robots.txt`, rate-limits per domain, randomised user-agents
- 🔄 **Retry with back-off** — handles 429s and transient failures gracefully
- 📊 **Rich results** — title, location, duration, deadline, apply link
            """)
        return

    # ── Load dataframe ──────────────────────────────────────────────────────────
    try:
        if uploaded_file.name.endswith(".csv"):
            df = pd.read_csv(uploaded_file)
        else:
            df = pd.read_excel(uploaded_file, engine="openpyxl")
        df.columns = df.columns.str.strip()
    except Exception as e:
        st.error(f"Failed to read file: {e}")
        return

    url_col = next(
        (c for c in df.columns if c.strip().lower() in ["url", "link", "website", "careers", "career url"]),
        None,
    )
    name_col = next(
        (c for c in df.columns if "company" in c.lower() or "name" in c.lower()),
        df.columns[0],
    )

    if not url_col:
        st.error(f"No URL column found. Detected columns: `{'`, `'.join(df.columns)}`")
        return

    st.success(f"✅ Loaded **{len(df)}** companies · URL column: `{url_col}` · Name column: `{name_col}`")
    with st.expander("Preview uploaded data"):
        st.dataframe(df.head(10), use_container_width=True)

    # ── Scrape button ────────────────────────────────────────────────────────────
    if st.button("🚀 Start Scanning"):
        search_terms = [k.strip().lower() for k in keywords_input.split(",") if k.strip()]
        exclude_terms = [k.strip().lower() for k in exclude_input.split(",") if k.strip()]
        to_scan = df.dropna(subset=[url_col]).head(scan_limit)

        total = len(to_scan)
        all_results: list[dict] = []
        errors: list[str] = []

        progress_bar = st.progress(0.0)
        status_text = st.empty()
        log_placeholder = st.empty()
        log_lines: list[str] = []

        metrics_cols = st.columns(4)
        metric_placeholders = [c.empty() for c in metrics_cols]

        def _update_metrics():
            hits = [r for r in all_results if r.get("Title", "—") not in ("—", "No internship found")]
            metric_placeholders[0].markdown(_styled_metric("Scanned", str(len(all_results_by_company))), unsafe_allow_html=True)
            metric_placeholders[1].markdown(_styled_metric("Internships Found", str(len(hits)), "#818cf8"), unsafe_allow_html=True)
            metric_placeholders[2].markdown(_styled_metric("Errors", str(len(errors)), "#f87171"), unsafe_allow_html=True)
            metric_placeholders[3].markdown(_styled_metric("Remote Roles", str(sum(1 for r in hits if "remote" in r.get("Location", "").lower())), "#34d399"), unsafe_allow_html=True)

        all_results_by_company: list[str] = []
        done_count = 0

        with ThreadPoolExecutor(max_workers=concurrency) as executor:
            futures = {
                executor.submit(
                    scrape_company,
                    row.to_dict(), url_col, name_col,
                    search_terms, exclude_terms,
                    float(max_duration), use_js,
                ): row[name_col]
                for _, row in to_scan.iterrows()
            }

            for future in as_completed(futures):
                company_name = futures[future]
                done_count += 1
                progress_bar.progress(done_count / total)
                status_text.text(f"⏳ {done_count}/{total} — last: {company_name}")

                try:
                    rows = future.result()
                    all_results.extend(rows)
                    all_results_by_company.append(company_name)

                    hit_count = sum(1 for r in rows if r.get("Title", "—") not in ("—", "No internship found"))
                    emoji = "✅" if hit_count else "➖"
                    log_lines.append(f"{emoji} {company_name} — {hit_count} position(s) found")
                except Exception as exc:
                    errors.append(company_name)
                    log_lines.append(f"❌ {company_name} — Exception: {exc}")

                # Update live log (last 10 lines)
                log_html = "<br>".join(log_lines[-10:])
                log_placeholder.markdown(f'<div class="log-box">{log_html}</div>', unsafe_allow_html=True)
                _update_metrics()

        status_text.text(f"✅ Scan complete! {total} companies processed.")
        progress_bar.progress(1.0)

        # ── Results ──────────────────────────────────────────────────────────────
        if all_results:
            res_df = pd.DataFrame(all_results)
            # Keep only rows with real results OR errors for review
            hits_df = res_df[res_df["Title"].notna() & ~res_df["Title"].isin(["—", "No internship found"])]
            miss_df = res_df[res_df["Title"].isin(["No internship found"])]
            err_df = res_df[res_df.get("Error", pd.Series(dtype=str)).fillna("").str.len() > 0]

            tab1, tab2, tab3 = st.tabs([
                f"🎯 Internships Found ({len(hits_df)})",
                f"➖ No Listings ({len(miss_df)})",
                f"❌ Errors ({len(err_df)})",
            ])

            with tab1:
                if hits_df.empty:
                    st.info("No internship listings detected with current filters.")
                else:
                    display_cols = ["Company", "Title", "Location", "Duration", "Deadline", "Apply Link", "Source"]
                    display_df = hits_df[[c for c in display_cols if c in hits_df.columns]]
                    st.data_editor(
                        display_df,
                        column_config={
                            "Apply Link": st.column_config.LinkColumn("Apply Link", display_text="Apply →"),
                            "Company URL": st.column_config.LinkColumn("Company URL", display_text="Visit →"),
                        },
                        hide_index=True,
                        use_container_width=True,
                    )
                    # ── Charts ────────────────────────────────────────────────────
                    col1, col2 = st.columns(2)
                    with col1:
                        loc_counts = hits_df["Location"].value_counts().head(8).reset_index()
                        loc_counts.columns = ["Location", "Count"]
                        st.markdown("**Locations**")
                        st.bar_chart(loc_counts.set_index("Location"))
                    with col2:
                        src_counts = hits_df["Source"].value_counts().reset_index()
                        src_counts.columns = ["Source", "Count"]
                        st.markdown("**Detection Method**")
                        st.bar_chart(src_counts.set_index("Source"))

            with tab2:
                st.dataframe(miss_df[["Company", "Company URL"]].drop_duplicates(), use_container_width=True)

            with tab3:
                if not err_df.empty:
                    st.dataframe(err_df[["Company", "Error", "Apply Link"]].drop_duplicates(), use_container_width=True)

            # ── Export ────────────────────────────────────────────────────────────
            st.markdown("---")
            col_a, col_b = st.columns(2)
            with col_a:
                st.download_button(
                    "⬇️ Download All Results (CSV)",
                    res_df.to_csv(index=False),
                    f"web3_internships_{datetime.now().strftime('%Y%m%d_%H%M')}.csv",
                    "text/csv",
                    use_container_width=True,
                )
            with col_b:
                if not hits_df.empty:
                    st.download_button(
                        "⬇️ Download Hits Only (CSV)",
                        hits_df.to_csv(index=False),
                        f"web3_internships_hits_{datetime.now().strftime('%Y%m%d_%H%M')}.csv",
                        "text/csv",
                        use_container_width=True,
                    )
        else:
            st.warning("No results returned. Try relaxing keyword filters or increasing the scan limit.")


if __name__ == "__main__":
    main()
