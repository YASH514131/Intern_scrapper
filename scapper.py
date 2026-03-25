"""
NEXUS  —  Web3 Talent Intelligence Platform  v4.1.0
=====================================================
FIXES in v4.1.0 (CSS color / visibility):
  [A] .streamlit/config.toml injection via st.markdown meta-trick REPLACED by
      writing the file at startup — the dataframe canvas (glide-data-grid) reads
      only the Streamlit theme config, NOT CSS variables. Without this the table
      cells render with a white/light background regardless of your CSS.
  [B] Input text color: added `color` + `caret-color` with max-specificity selectors
      so Streamlit's own injected stylesheet cannot override them.
  [C] Selectbox / multiselect dropdown text made visible in dark mode.
  [D] st.dataframe host wrapper: explicit background + border via attribute selector.
  [E] Paragraph / markdown container text color set explicitly — CSS vars in
      :root don't reliably cascade into Streamlit's shadow components.
  [F] Tab panel content area text color fixed.
  [G] Progress label and metric text colors made explicit (not var() only).
  [H] LIGHT mode: all the above re-applied with light palette values.

Previous fixes (v4.0.0) retained:
  [1] CSS in plain triple-quoted strings
  [2] Selenium SmartWait
  [3] robots.txt robust check
  [4] Per-domain 429 backoff
  [5] 12 User-Agent strings
  [6] Levenshtein fuzzy matching
  [7] Complete media queries
  [8] block-container padding not zeroed; no border-radius on dataframe wrappers
  [9] st.dataframe with explicit height
"""

import os, re, time, random, threading, urllib.robotparser, json, io, logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import urljoin, urlparse
from datetime import datetime
from pathlib import Path

import streamlit as st
import pandas as pd
import requests
from bs4 import BeautifulSoup
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# ── FIX [A]: Write .streamlit/config.toml before Streamlit reads it ──────────
# The glide-data-grid canvas that powers st.dataframe reads ONLY the Streamlit
# theme config — it ignores CSS variables. Without this the table text is always
# rendered in the default light-theme colours (black on white).
def _ensure_theme_config(dark: bool) -> None:
    cfg_dir = Path(".streamlit")
    cfg_dir.mkdir(exist_ok=True)
    cfg_file = cfg_dir / "config.toml"
    if dark:
        content = (
            '[theme]\n'
            'base = "dark"\n'
            'backgroundColor = "#05070f"\n'
            'secondaryBackgroundColor = "#0b0e1a"\n'
            'textColor = "#a8b0cc"\n'
            'primaryColor = "#00c8f0"\n'
            'font = "sans serif"\n'
        )
    else:
        content = (
            '[theme]\n'
            'base = "light"\n'
            'backgroundColor = "#f2f5ff"\n'
            'secondaryBackgroundColor = "#eef1fb"\n'
            'textColor = "#363d5c"\n'
            'primaryColor = "#00c8f0"\n'
            'font = "sans serif"\n'
        )
    cfg_file.write_text(content)

# ── Optional Selenium ─────────────────────────────────────────────────────────
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

VERSION = "4.1.0"
log = logging.getLogger("nexus")

# ═══════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════════

CAREER_PATH_HINTS = [
    "/careers", "/jobs", "/join-us", "/work-with-us", "/opportunities",
    "/hiring", "/open-positions", "/positions", "/team/join", "/about/careers",
    "/company/careers", "/recruit", "/vacancies", "/en/careers", "/apply",
    "/work-here", "/come-work-with-us", "/life", "/people",
]

DURATION_PATTERNS = [
    r"(\d+)\s*[-–]\s*(\d+)\s*(month|week|mo\b)",
    r"(\d+)\s*(month|week|mo\b)",
    r"(summer|spring|fall|winter|q[1-4])\s*(intern)?",
]

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36 Edg/123.0.0.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.4; rv:124.0) Gecko/20100101 Firefox/124.0",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 OPR/109.0.0.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
]

JS_WAIT_SELECTORS = [
    "div.opening", "div.posting", "li.job-listing", "div.job-card",
    "[data-automation='job-list-item']", "[class*='JobCard']",
    "[class*='job-item']", "[class*='position-item']",
    "main", "article", "[role='main']",
]

# ═══════════════════════════════════════════════════════════════════════════════
# FUZZY MATCHING
# ═══════════════════════════════════════════════════════════════════════════════

def _levenshtein(a: str, b: str) -> int:
    if len(a) < len(b):
        return _levenshtein(b, a)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a):
        curr = [i + 1]
        for j, cb in enumerate(b):
            curr.append(min(prev[j + 1] + 1, curr[j] + 1, prev[j] + (ca != cb)))
        prev = curr
    return prev[-1]

def _fuzzy_match(text: str, keywords: list, threshold: int = 2) -> bool:
    text_lower = text.lower()
    if any(kw in text_lower for kw in keywords):
        return True
    words = re.split(r"\W+", text_lower)
    for word in words:
        if len(word) < 4:
            continue
        for kw in keywords:
            if abs(len(word) - len(kw)) <= threshold:
                if _levenshtein(word, kw) <= threshold:
                    return True
    return False

# ═══════════════════════════════════════════════════════════════════════════════
# PER-DOMAIN RATE LIMITER
# ═══════════════════════════════════════════════════════════════════════════════

class RateLimiter:
    def __init__(self, calls_per_second: float = 0.5):
        self._lock    = threading.Lock()
        self._last:    dict = {}
        self._backoff: dict = {}
        self._interval = 1.0 / calls_per_second

    def wait(self, domain: str) -> None:
        with self._lock:
            backoff  = self._backoff.get(domain, 0)
            elapsed  = time.time() - self._last.get(domain, 0)
            gap      = max(self._interval, backoff) - elapsed
        if gap > 0:
            time.sleep(gap + random.uniform(0.05, 0.2))
        with self._lock:
            self._last[domain] = time.time()

    def penalise(self, domain: str) -> None:
        with self._lock:
            current = self._backoff.get(domain, self._interval)
            self._backoff[domain] = min(current * 2, 60.0)

    def reset(self, domain: str) -> None:
        with self._lock:
            if domain in self._backoff:
                self._backoff[domain] = max(self._backoff[domain] * 0.75, self._interval)

_rl = RateLimiter(calls_per_second=0.5)

# ═══════════════════════════════════════════════════════════════════════════════
# HTTP SESSION
# ═══════════════════════════════════════════════════════════════════════════════

def _session() -> requests.Session:
    s = requests.Session()
    retry = Retry(
        total=2, backoff_factor=0.5,
        status_forcelist=[500, 502, 503, 504],
        allowed_methods=["GET", "HEAD"],
        respect_retry_after_header=True,
    )
    s.mount("https://", HTTPAdapter(max_retries=retry))
    s.mount("http://",  HTTPAdapter(max_retries=retry))
    s.headers.update({
        "User-Agent":      random.choice(USER_AGENTS),
        "Accept-Language": "en-US,en;q=0.9",
        "Accept":          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Encoding": "gzip, deflate, br",
        "DNT":             "1",
    })
    return s

# ═══════════════════════════════════════════════════════════════════════════════
# robots.txt CHECK
# ═══════════════════════════════════════════════════════════════════════════════

def _robots_ok(url: str, sess: requests.Session) -> bool:
    try:
        parsed     = urlparse(url)
        robots_url = f"{parsed.scheme}://{parsed.netloc}/robots.txt"
        resp = sess.get(robots_url, timeout=6, allow_redirects=True)
        if resp.status_code != 200:
            return True
        content_type = resp.headers.get("Content-Type", "")
        if "text" not in content_type and "plain" not in content_type:
            return True
        body = resp.text.strip()
        if body.lower().startswith("<!doctype") or body.lower().startswith("<html"):
            return True
        rp = urllib.robotparser.RobotFileParser()
        rp.parse(body.splitlines())
        return rp.can_fetch("*", url)
    except Exception:
        return True

# ═══════════════════════════════════════════════════════════════════════════════
# FETCHERS
# ═══════════════════════════════════════════════════════════════════════════════

def _static(url: str, sess: requests.Session, timeout: int = 8):
    domain = urlparse(url).netloc
    _rl.wait(domain)
    try:
        resp = sess.get(url, timeout=timeout)
        if resp.status_code == 429:
            _rl.penalise(domain)
            return None
        resp.raise_for_status()
        _rl.reset(domain)
        return BeautifulSoup(resp.text, "html.parser")
    except Exception as exc:
        log.debug("Static fetch failed %s: %s", url, exc)
        return None

def _js(url: str, timeout: int = 15):
    if not (SELENIUM_AVAILABLE and WDM_AVAILABLE):
        return None
    driver = None
    try:
        opts = Options()
        opts.add_argument("--headless=new")
        opts.add_argument("--no-sandbox")
        opts.add_argument("--disable-dev-shm-usage")
        opts.add_argument("--disable-blink-features=AutomationControlled")
        opts.add_argument("--window-size=1920,1080")
        opts.add_argument(f"user-agent={random.choice(USER_AGENTS)}")
        opts.add_experimental_option("excludeSwitches", ["enable-automation"])
        opts.add_experimental_option("useAutomationExtension", False)
        driver = webdriver.Chrome(
            service=Service(ChromeDriverManager().install()), options=opts
        )
        driver.set_page_load_timeout(25)
        driver.get(url)
        wait = WebDriverWait(driver, timeout)
        for selector in JS_WAIT_SELECTORS:
            try:
                wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, selector)))
                break
            except Exception:
                continue
        else:
            for _ in range(20):
                if driver.execute_script("return document.readyState") == "complete":
                    break
                time.sleep(0.2)
        time.sleep(0.8)
        return BeautifulSoup(driver.page_source, "html.parser")
    except Exception as exc:
        log.debug("JS fetch failed %s: %s", url, exc)
        return None
    finally:
        if driver:
            try: driver.quit()
            except Exception: pass

def _fetch(url: str, sess: requests.Session, use_js: bool = False):
    soup = _static(url, sess)
    if soup is None or (use_js and len(soup.get_text(strip=True)) < 300):
        soup = _js(url) or soup
    return soup

# ═══════════════════════════════════════════════════════════════════════════════
# CAREER URL DISCOVERY
# ═══════════════════════════════════════════════════════════════════════════════

def _career_url(base: str, sess: requests.Session) -> str:
    parsed = urlparse(base)
    root   = f"{parsed.scheme}://{parsed.netloc}"

    def probe(hint: str):
        candidate = urljoin(root, hint)
        try:
            resp = sess.head(candidate, timeout=3, allow_redirects=True)
            if resp.status_code < 400:
                return candidate
        except Exception:
            pass
        return None

    with ThreadPoolExecutor(max_workers=min(len(CAREER_PATH_HINTS), 10)) as pool:
        probe_futures = {pool.submit(probe, h): h for h in CAREER_PATH_HINTS}
        for fut in as_completed(probe_futures):
            result = fut.result()
            if result:
                for f in probe_futures: f.cancel()
                return result

    soup = _static(base, sess)
    if soup:
        for a in soup.find_all("a", href=True):
            href = a["href"].lower()
            text = a.get_text(strip=True).lower()
            if any(k in href or k in text for k in ["career", "job", "hiring", "join us", "work with"]):
                full = urljoin(root, a["href"])
                if urlparse(full).netloc == parsed.netloc:
                    return full
    return base

# ═══════════════════════════════════════════════════════════════════════════════
# EXTRACTION HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

def _duration(text: str):
    for pat in DURATION_PATTERNS:
        m = re.search(pat, text.lower())
        if m:
            raw = m.group(0)
            g   = m.groups()
            if any(s in raw for s in ["summer", "spring", "fall", "winter"]):
                return raw.title(), 3.0
            if len(g) >= 2:
                val  = int(g[0])
                unit = g[-1]
                mos  = val if "month" in unit else round(val / 4.3, 1)
                return f"{val} {unit}", mos
    return "Not specified", 0.0

def _location(text: str) -> str:
    for pat in [r"\b(remote)\b", r"\b(hybrid)\b", r"\b(on[-\s]?site)\b"]:
        m = re.search(pat, text.lower())
        if m:
            return m.group(1).capitalize()
    m = re.search(r"\b([A-Z][a-z]+(?: [A-Z][a-z]+)?,\s*[A-Z]{2})\b", text)
    return m.group(1) if m else "Not specified"

# ═══════════════════════════════════════════════════════════════════════════════
# JOB EXTRACTION — 3 LAYERS
# ═══════════════════════════════════════════════════════════════════════════════

def _jobs(soup: BeautifulSoup, url: str, terms: list, excl: list, maxmo: float) -> list:
    found: list = []
    seen:  set  = set()

    def _passes(title: str) -> bool:
        tl = title.lower()
        if any(e in tl for e in excl): return False
        return _fuzzy_match(tl, terms, threshold=2)

    def _add(title, apply_url, loc, dt, mo, source):
        if maxmo > 0 and mo > maxmo and mo != 0: return
        key = title.lower()[:40]
        if key not in seen:
            seen.add(key)
            found.append({
                "Title": title, "Company URL": url, "Apply Link": apply_url,
                "Location": loc or "Not specified", "Duration": dt,
                "Deadline": "—", "Source": source,
            })

    # Layer 1: schema.org JSON-LD
    for script in soup.find_all("script", type="application/ld+json"):
        try:
            data = json.loads(script.string or "")
            jobs = data if isinstance(data, list) else [data]
            for job in jobs:
                if job.get("@type") != "JobPosting": continue
                title = job.get("title", "").strip()
                if not _passes(title): continue
                dt, mo = _duration(job.get("description", "") + " " + job.get("employmentType", ""))
                loc = (job.get("jobLocation", {}).get("address", {}).get("addressLocality", "")
                       or _location(job.get("description", "")))
                apply = job.get("url") or url
                _add(title, apply, loc, dt, mo, "schema.org")
                if found and job.get("validThrough"):
                    found[-1]["Deadline"] = job["validThrough"][:10]
        except Exception:
            continue
    if found: return found

    # Layer 2: ATS HTML selectors
    ATS_SELECTORS = [
        {"c": "div.opening",    "t": "a",           "l": "a"},
        {"c": "div.posting",    "t": "h5",          "l": "a.posting-title"},
        {"c": "li.job-listing", "t": "h2,h3,h4",    "l": "a"},
        {"c": "div.job-card",   "t": "h2,h3,h4",    "l": "a"},
        {"c": "tr.job-row",     "t": "td.job-title", "l": "a"},
        {"c": "[data-automation='job-list-item']", "t": "h3,h4", "l": "a"},
        {"c": "[class*='JobCard']",  "t": "h3,h4",  "l": "a"},
        {"c": "[class*='job-item']", "t": "h3,h4",  "l": "a"},
    ]
    for sel in ATS_SELECTORS:
        for container in soup.select(sel["c"]):
            te = container.select_one(sel["t"])
            le = container.select_one(sel["l"])
            if not te: continue
            title = te.get_text(strip=True)
            if not _passes(title): continue
            ctx    = container.get_text(" ")
            dt, mo = _duration(ctx)
            apply  = urljoin(url, le["href"]) if le and le.get("href") else url
            _add(title, apply, _location(ctx), dt, mo, "ATS HTML")
        if found: return found

    # Layer 3: Full-text scan
    lines = [ln.strip() for ln in soup.get_text("\n").splitlines() if ln.strip()]
    for i, line in enumerate(lines):
        if not _passes(line): continue
        ctx    = " ".join(lines[max(0, i - 2): i + 5])
        dt, mo = _duration(ctx)
        anchors = [a for a in soup.find_all("a", href=True)
                   if _fuzzy_match(a.get_text(strip=True).lower() + a["href"].lower(), terms)]
        apply = urljoin(url, anchors[0]["href"]) if anchors else url
        _add(line[:120], apply, _location(ctx), dt, mo, "Text scan")
        if len(found) >= 10: break

    return found

# ═══════════════════════════════════════════════════════════════════════════════
# PER-COMPANY ORCHESTRATOR
# ═══════════════════════════════════════════════════════════════════════════════

def _scrape_company_inner(row: dict, url_col: str, name_col: str,
                          terms: list, excl: list, maxmo: float, use_js: bool) -> list:
    base = str(row.get(url_col, "")).strip()
    name = str(row.get(name_col, "Unknown")).strip()
    if not base.startswith("http"):
        base = "https://" + base
    sess = _session()
    if not _robots_ok(base, sess):
        return [{"Company": name, "Error": "robots.txt disallowed",
                 "Title": "—", "Apply Link": base,
                 "Location": "—", "Duration": "—", "Deadline": "—", "Source": "—"}]
    career = _career_url(base, sess)
    soup   = _fetch(career, sess, use_js)
    if soup is None:
        return [{"Company": name, "Error": "Fetch failed",
                 "Title": "—", "Apply Link": career,
                 "Location": "—", "Duration": "—", "Deadline": "—", "Source": "—"}]
    jobs = _jobs(soup, career, terms, excl, maxmo)
    if not jobs:
        return [{"Company": name, "Title": "No internship found",
                 "Apply Link": career, "Location": "—",
                 "Duration": "—", "Deadline": "—", "Source": "—", "Error": ""}]
    for j in jobs:
        j["Company"] = name
        j.setdefault("Error", "")
    return jobs

def scrape_company(row: dict, url_col: str, name_col: str,
                   terms: list, excl: list, maxmo: float, use_js: bool,
                   hard_timeout: float = 40.0) -> list:
    name = str(row.get(name_col, "Unknown")).strip()
    with ThreadPoolExecutor(max_workers=1) as ex:
        fut = ex.submit(_scrape_company_inner, row, url_col, name_col,
                        terms, excl, maxmo, use_js)
        try:
            return fut.result(timeout=hard_timeout)
        except TimeoutError:
            fut.cancel()
            base = str(row.get(url_col, "")).strip()
            return [{"Company": name, "Error": f"Timeout >{hard_timeout:.0f}s",
                     "Title": "—", "Apply Link": base,
                     "Location": "—", "Duration": "—", "Deadline": "—", "Source": "—"}]

# ═══════════════════════════════════════════════════════════════════════════════
# CSS  ── v4.1.0 COLOUR FIXES
#
# KEY CHANGE: All colour values are now written as LITERAL hex/rgb values in
# addition to (or instead of) var() references. Streamlit's component iframes
# and shadow DOM elements cannot see :root CSS variables defined in the parent
# document. Writing literal values ensures every element is styled correctly.
#
# FIX [B]: Input fields — added explicit `color` and `background-color` with
#           ultra-high specificity selectors to beat Streamlit's own styles.
# FIX [C]: Selectbox list — explicit text/bg colour on dropdown items.
# FIX [E]: Markdown container paragraphs — explicit colour, not just var().
# FIX [F]: Tab panel text — explicit colour on [data-baseweb="tab-panel"].
# ═══════════════════════════════════════════════════════════════════════════════

DARK_CSS = """
<style>
@import url('https://fonts.googleapis.com/css2?family=Syne:wght@400;600;700;800&family=DM+Mono:wght@300;400;500&family=DM+Sans:wght@300;400;500;600&display=swap');
:root {
  --app-bg:     #05070f;
  --surface:    #0b0e1a;
  --panel:      #111527;
  --panel2:     #161b2e;
  --border:     #1d2236;
  --border2:    #252a40;
  --muted:      #3d4460;
  --dim:        #6b738f;
  --body:       #a8b0cc;
  --bright:     #dde3f5;
  --white:      #f0f4ff;
  --input-bg:   #111527;
  --sb-bg:      #0b0e1a;
  --term-bg:    #030508;
  --row-hover:  rgba(255,255,255,0.025);
}
</style>
"""

LIGHT_CSS = """
<style>
@import url('https://fonts.googleapis.com/css2?family=Syne:wght@400;600;700;800&family=DM+Mono:wght@300;400;500&family=DM+Sans:wght@300;400;500;600&display=swap');
:root {
  --app-bg:     #f2f5ff;
  --surface:    #ffffff;
  --panel:      #eef1fb;
  --panel2:     #e4e8f5;
  --border:     #d4daf0;
  --border2:    #bfc8e4;
  --muted:      #9aa3c0;
  --dim:        #606882;
  --body:       #363d5c;
  --bright:     #181e38;
  --white:      #0d1128;
  --input-bg:   #ffffff;
  --sb-bg:      #eef1fb;
  --term-bg:    #0d0f18;
  --row-hover:  rgba(0,0,0,0.03);
}
</style>
"""

# ── DARK layout CSS ────────────────────────────────────────────────────────────
LAYOUT_CSS_DARK = """
<style>
:root {
  --cyan:    #00c8f0;
  --cyan-d:  #008eaa;
  --violet:  #7c6cfa;
  --amber:   #ffb340;
  --rose:    #ff4f6e;
  --green:   #00dfa0;
  --fh: 'Syne', sans-serif;
  --fb: 'DM Sans', sans-serif;
  --fm: 'DM Mono', monospace;
  --r1: 6px; --r2: 12px; --r3: 18px; --r4: 24px;
}

*, *::before, *::after { box-sizing: border-box; }

html, body { background: #05070f !important; color: #a8b0cc !important; }
.stApp { background: #05070f !important; font-family: 'DM Sans', sans-serif; color: #a8b0cc !important; }
.stApp > header { display: none !important; }
[data-testid="stAppViewContainer"] { background: #05070f !important; }
[data-testid="stMain"] { background: #05070f !important; }
#MainMenu, footer, .stDeployButton { display: none !important; }
[data-testid="stDecoration"] { display: none !important; }

/* ── FIX [E]: Markdown / paragraph text — literal colour, not var() ── */
[data-testid="stMarkdownContainer"] p,
[data-testid="stMarkdownContainer"] li,
[data-testid="stMarkdownContainer"] span,
[data-testid="stMarkdownContainer"] { color: #a8b0cc !important; }

/* ── FIX [F]: Tab panel content text ── */
[data-baseweb="tab-panel"] { color: #a8b0cc !important; }
[data-baseweb="tab-panel"] p,
[data-baseweb="tab-panel"] span { color: #a8b0cc !important; }

/* ── Sidebar ── */
section[data-testid="stSidebar"] {
  background: #0b0e1a !important;
  border-right: 1px solid #1d2236 !important;
}
section[data-testid="stSidebar"] * { color: #a8b0cc !important; }

/* ── Text ── */
h1, h2, h3, h4 { font-family: 'Syne', sans-serif; font-weight: 700; color: #f0f4ff !important; letter-spacing: -0.02em; }
p, li { color: #a8b0cc !important; }
code, pre { font-family: 'DM Mono', monospace !important; color: #a8b0cc !important; }

/* ── Widget labels ── */
.stTextInput label, .stNumberInput label, .stSlider label,
.stFileUploader label, [data-testid="stWidgetLabel"] span,
.stCheckbox span, .stToggle span {
  color: #6b738f !important;
  font-family: 'DM Mono', monospace !important;
  font-size: 0.68rem !important;
  letter-spacing: 0.09em !important;
  text-transform: uppercase !important;
}
.stCheckbox span p, .stToggle span p { text-transform: none !important; letter-spacing: 0 !important; }

/* ── FIX [B]: Input text — maximum specificity to override Streamlit's own styles ── */
.stTextInput input,
.stTextInput input:focus,
.stTextInput input:active,
.stNumberInput input,
.stNumberInput input:focus,
div[data-baseweb="input"] input,
div[data-baseweb="base-input"] input {
  background: #111527 !important;
  background-color: #111527 !important;
  border: 1px solid #252a40 !important;
  color: #dde3f5 !important;
  -webkit-text-fill-color: #dde3f5 !important;
  caret-color: #00c8f0 !important;
  border-radius: 6px !important;
  font-family: 'DM Sans', sans-serif !important;
  font-size: 0.875rem !important;
  transition: border-color 0.2s, box-shadow 0.2s !important;
}
.stTextInput input:focus,
div[data-baseweb="input"]:focus-within {
  border-color: #00c8f0 !important;
  box-shadow: 0 0 0 3px rgba(0,200,240,0.12) !important;
  outline: none !important;
}
/* Autocomplete / browser-filled inputs stay readable */
.stTextInput input:-webkit-autofill,
.stTextInput input:-webkit-autofill:hover,
.stTextInput input:-webkit-autofill:focus {
  -webkit-box-shadow: 0 0 0 1000px #111527 inset !important;
  -webkit-text-fill-color: #dde3f5 !important;
  caret-color: #00c8f0 !important;
}

/* ── FIX [C]: Selectbox ── */
div[data-baseweb="select"] div,
div[data-baseweb="select"] span,
div[data-baseweb="select"] input {
  background: #111527 !important;
  color: #dde3f5 !important;
  -webkit-text-fill-color: #dde3f5 !important;
  border-color: #252a40 !important;
}
ul[data-baseweb="menu"],
li[data-baseweb="menu-item"] {
  background: #111527 !important;
  color: #dde3f5 !important;
}
li[data-baseweb="menu-item"]:hover {
  background: #161b2e !important;
}

/* ── Slider ── */
[data-testid="stSliderThumb"] {
  background: #00c8f0 !important;
  border: 2px solid #05070f !important;
}

/* ── Primary button ── */
.stButton > button {
  background: linear-gradient(135deg, #00c8f0 0%, #7c6cfa 100%) !important;
  color: #040c14 !important;
  border: none !important;
  border-radius: 12px !important;
  font-family: 'Syne', sans-serif !important;
  font-weight: 700 !important;
  font-size: 0.88rem !important;
  letter-spacing: 0.05em !important;
  padding: 0.62rem 1.5rem !important;
  text-transform: uppercase !important;
  box-shadow: 0 4px 20px rgba(0,200,240,0.22) !important;
  transition: transform 0.22s, box-shadow 0.22s !important;
}
.stButton > button:hover { transform: translateY(-2px) !important; box-shadow: 0 8px 28px rgba(0,200,240,0.32) !important; }
.stButton > button:active { transform: translateY(0) !important; }

/* ── Download button ── */
[data-testid="stDownloadButton"] > button {
  background: transparent !important;
  color: #00c8f0 !important;
  border: 1px solid #008eaa !important;
  border-radius: 12px !important;
  font-family: 'Syne', sans-serif !important;
  font-weight: 600 !important;
  font-size: 0.76rem !important;
  letter-spacing: 0.05em !important;
  text-transform: uppercase !important;
  padding: 0.5rem 1.1rem !important;
  transition: background 0.18s, box-shadow 0.18s !important;
}
[data-testid="stDownloadButton"] > button:hover {
  background: rgba(0,200,240,0.07) !important;
  box-shadow: 0 0 14px rgba(0,200,240,0.15) !important;
}

/* ── File uploader ── */
[data-testid="stFileUploader"] {
  background: #111527 !important;
  border: 1px dashed #252a40 !important;
  border-radius: 12px !important;
}
[data-testid="stFileUploader"] * { color: #a8b0cc !important; }
[data-testid="stFileUploader"]:hover { border-color: #008eaa !important; }

/* ── Tabs ── */
.stTabs [data-baseweb="tab-list"] {
  background: transparent !important;
  border-bottom: 1px solid #1d2236 !important;
  gap: 0 !important;
}
.stTabs [data-baseweb="tab"] {
  background: transparent !important;
  color: #6b738f !important;
  font-family: 'Syne', sans-serif !important;
  font-weight: 600 !important;
  font-size: 0.76rem !important;
  letter-spacing: 0.06em !important;
  text-transform: uppercase !important;
  border: none !important;
  border-bottom: 2px solid transparent !important;
  padding: 0.65rem 1.3rem !important;
  transition: color 0.2s !important;
}
.stTabs [aria-selected="true"] {
  color: #00c8f0 !important;
  border-bottom-color: #00c8f0 !important;
}

/* ── Progress ── */
.stProgress > div > div > div {
  background: linear-gradient(90deg, #00c8f0, #7c6cfa) !important;
  border-radius: 99px !important;
}
.stProgress > div > div {
  background: #161b2e !important;
  border-radius: 99px !important;
  height: 5px !important;
}

/* ── DataFrame / DataEditor — FIX [D]
   The canvas reads theme config; we style the HOST wrapper only.
   NO border-radius, NO overflow:hidden (would clip the canvas). ── */
[data-testid="stDataFrame"] { background: #111527 !important; }
[data-testid="stDataEditor"] { background: #111527 !important; }
.dvn-scroller { background: #111527 !important; }

/* ── Alerts ── */
.stAlert {
  background: #111527 !important;
  border: 1px solid #252a40 !important;
  border-radius: 12px !important;
  color: #a8b0cc !important;
}
.stAlert p, .stAlert span { color: #a8b0cc !important; }

/* ── Expander ── */
details > summary {
  background: #111527 !important;
  border: 1px solid #1d2236 !important;
  border-radius: 6px !important;
  color: #a8b0cc !important;
  padding: 0.6rem 1rem !important;
}
details[open] > summary { border-radius: 6px 6px 0 0 !important; }
details > div {
  background: #111527 !important;
  border: 1px solid #1d2236 !important;
  border-top: none !important;
  border-radius: 0 0 6px 6px !important;
  color: #a8b0cc !important;
}

/* ── Scrollbar ── */
::-webkit-scrollbar { width: 4px; height: 4px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: #3d4460; border-radius: 99px; }
::-webkit-scrollbar-thumb:hover { background: #6b738f; }

/* ═══ ANIMATIONS ══════════════════════════════════════════════════════════ */
@keyframes fadeUp {
  from { opacity: 0; transform: translateY(14px); }
  to   { opacity: 1; transform: translateY(0); }
}
@keyframes pulseDot {
  0%, 100% { box-shadow: 0 0 0 0   rgba(0,200,240,0.55); }
  60%       { box-shadow: 0 0 0 7px rgba(0,200,240,0);    }
}
@keyframes scanline {
  0%   { transform: translateY(-100%); }
  100% { transform: translateY(600%); }
}
@keyframes blink { 0%,100% { opacity:1; } 50% { opacity:0; } }

/* ═══ NEXUS COMPONENTS ════════════════════════════════════════════════════ */

.nx-nav {
  display: flex; align-items: center; justify-content: space-between;
  padding: 0.85rem 2.5rem;
  border-bottom: 1px solid #1d2236;
  background: #0b0e1a;
  position: sticky; top: 0; z-index: 999;
  animation: fadeUp 0.35s ease both;
}
.nx-logo {
  font-family: 'Syne', sans-serif; font-weight: 800; font-size: 1.15rem;
  letter-spacing: -0.03em; color: #f0f4ff;
  display: flex; align-items: center; gap: 0.45rem; user-select: none;
}
.nx-logo-dot {
  width: 7px; height: 7px; border-radius: 50%;
  background: #00c8f0; flex-shrink: 0;
  animation: pulseDot 2s ease-in-out infinite;
}
.nx-nav-pills { display: flex; gap: 0.2rem; }
.nx-pill {
  font-family: 'Syne', sans-serif; font-size: 0.68rem; font-weight: 600;
  letter-spacing: 0.08em; text-transform: uppercase;
  padding: 0.26rem 0.7rem; border-radius: 99px;
  color: #6b738f; border: 1px solid transparent;
}
.nx-pill-on {
  color: #00c8f0; border-color: rgba(0,200,240,0.3);
  background: rgba(0,200,240,0.07);
}
.nx-nav-right { display: flex; align-items: center; gap: 0.7rem; }
.nx-badge {
  font-family: 'DM Mono', monospace; font-size: 0.6rem;
  padding: 0.16rem 0.5rem; border-radius: 99px;
  background: rgba(0,200,240,0.08); color: #00c8f0;
  border: 1px solid rgba(0,200,240,0.2);
}
.nx-live {
  display: inline-flex; align-items: center; gap: 0.35rem;
  font-family: 'DM Mono', monospace; font-size: 0.63rem; letter-spacing: 0.06em;
  text-transform: uppercase; padding: 0.2rem 0.6rem; border-radius: 99px;
  color: #00dfa0; background: rgba(0,223,160,0.08);
  border: 1px solid rgba(0,223,160,0.25);
}
.nx-live::before {
  content: ""; width: 5px; height: 5px; border-radius: 50%;
  background: #00dfa0; animation: pulseDot 1.5s infinite;
}
.nx-idle {
  display: inline-flex; align-items: center; gap: 0.35rem;
  font-family: 'DM Mono', monospace; font-size: 0.63rem; letter-spacing: 0.06em;
  text-transform: uppercase; padding: 0.2rem 0.6rem; border-radius: 99px;
  color: #6b738f; background: rgba(107,115,143,0.08);
  border: 1px solid #1d2236;
}

.nx-hero {
  padding: 3.5rem 2.5rem 2.5rem;
  background-image:
    radial-gradient(ellipse 90% 70% at 50% -10%, rgba(0,200,240,0.07) 0%, transparent 65%),
    radial-gradient(ellipse 55% 45% at 85% 55%,  rgba(124,108,250,0.06) 0%, transparent 55%);
  animation: fadeUp 0.45s ease 0.06s both;
}
.nx-eyebrow {
  font-family: 'DM Mono', monospace; font-size: 0.67rem; color: #00c8f0;
  letter-spacing: 0.16em; text-transform: uppercase;
  margin-bottom: 1rem; display: flex; align-items: center; gap: 0.5rem;
}
.nx-eyebrow::before {
  content: ""; display: inline-block;
  width: 18px; height: 1px; background: #00c8f0; flex-shrink: 0;
}
.nx-h1 {
  font-family: 'Syne', sans-serif;
  font-size: clamp(1.9rem, 3.6vw, 3.1rem);
  font-weight: 800; line-height: 1.06; letter-spacing: -0.04em;
  color: #f0f4ff; margin-bottom: 1rem;
}
.nx-grad {
  background: linear-gradient(135deg, #00c8f0 0%, #7c6cfa 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}
.nx-sub { font-size: 0.93rem; color: #6b738f; line-height: 1.75; max-width: 500px; margin-bottom: 1.75rem; }
.nx-stats { display: flex; gap: 2.5rem; flex-wrap: wrap; }
.nx-stat  { display: flex; flex-direction: column; gap: 0.12rem; }
.nx-stat-n { font-family: 'Syne', sans-serif; font-size: 1.5rem; font-weight: 800; color: #f0f4ff; letter-spacing: -0.03em; line-height: 1; }
.nx-stat-l { font-family: 'DM Mono', monospace; font-size: 0.62rem; color: #6b738f; letter-spacing: 0.08em; text-transform: uppercase; }
.nx-divider { height: 1px; background: linear-gradient(90deg, transparent, #1d2236, transparent); }

.nx-sb-logo { padding: 1.1rem 1.1rem 0.9rem; border-bottom: 1px solid #1d2236; margin-bottom: 0.9rem; }
.nx-sb-logo-text { font-family: 'Syne', sans-serif; font-weight: 800; font-size: 0.92rem; color: #f0f4ff; display: flex; align-items: center; gap: 0.4rem; }
.nx-sb-sec {
  font-family: 'DM Mono', monospace; font-size: 0.59rem; color: #3d4460;
  letter-spacing: 0.14em; text-transform: uppercase;
  padding: 0.6rem 0 0.35rem; border-bottom: 1px solid #1d2236; margin-bottom: 0.5rem;
}

.nx-metrics { display: grid; grid-template-columns: repeat(4, 1fr); gap: 0.85rem; padding: 1.5rem 2.5rem 0; }
.nx-metric {
  background: #111527; border: 1px solid #1d2236;
  border-radius: 18px; padding: 1.1rem 1.25rem;
  position: relative; overflow: hidden;
  transition: transform 0.2s, border-color 0.25s;
  animation: fadeUp 0.4s ease both;
}
.nx-metric:hover { transform: translateY(-2px); border-color: #252a40; }
.nx-metric::after {
  content: ""; position: absolute; top: 0; left: 0; right: 0; height: 1px;
}
.nx-mc1::after { background: linear-gradient(90deg, transparent, #00c8f0, transparent); }
.nx-mc2::after { background: linear-gradient(90deg, transparent, #7c6cfa, transparent); }
.nx-mc3::after { background: linear-gradient(90deg, transparent, #ffb340, transparent); }
.nx-mc4::after { background: linear-gradient(90deg, transparent, #00dfa0, transparent); }
.nx-m-val { font-family: 'Syne', sans-serif; font-size: 1.9rem; font-weight: 800; letter-spacing: -0.04em; line-height: 1; margin-bottom: 0.28rem; }
.nx-mc1 .nx-m-val { color: #00c8f0; }
.nx-mc2 .nx-m-val { color: #7c6cfa; }
.nx-mc3 .nx-m-val { color: #ffb340; }
.nx-mc4 .nx-m-val { color: #00dfa0; }
.nx-m-lbl { font-family: 'DM Mono', monospace; font-size: 0.61rem; color: #6b738f; letter-spacing: 0.1em; text-transform: uppercase; }
.nx-m-icon { position: absolute; right: 1rem; bottom: 0.85rem; font-size: 1.25rem; opacity: 0.1; }

.nx-term-wrap { padding: 1rem 2.5rem 0; }
.nx-term {
  background: #030508; border: 1px solid #1d2236;
  border-radius: 12px; overflow: hidden; font-family: 'DM Mono', monospace;
  position: relative;
}
.nx-term::after {
  content: ""; position: absolute; left: 0; right: 0; height: 40px;
  background: linear-gradient(transparent, rgba(0,200,240,0.02), transparent);
  pointer-events: none; animation: scanline 3.5s linear infinite;
}
.nx-term-bar {
  background: #161b2e; border-bottom: 1px solid #1d2236;
  padding: 0.45rem 0.9rem; display: flex; align-items: center; gap: 0.35rem;
}
.nx-term-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.nx-term-title { font-size: 0.64rem; color: #6b738f; letter-spacing: 0.08em; text-transform: uppercase; margin-left: 0.4rem; }
.nx-term-body {
  padding: 0.85rem 1rem; font-size: 0.74rem;
  line-height: 1.75; max-height: 200px; overflow-y: auto; color: #3ddc84;
}
.t-hit  { color: #00dfa0; }
.t-miss { color: #4a5270; }
.t-err  { color: #ff4f6e; }
.t-info { color: #6b9cf5; }
.nx-cursor {
  display: inline-block; width: 7px; height: 13px;
  background: #00c8f0; vertical-align: middle;
  animation: blink 1s step-end infinite; margin-left: 2px;
}

.nx-prog { padding: 0.65rem 2.5rem 0.75rem; }
.nx-prog-lbl { font-family: 'DM Mono', monospace; font-size: 0.7rem; color: #6b738f; margin-bottom: 0.35rem; }

.nx-sec { padding: 1.4rem 2.5rem 0; }
.nx-sec-hd { display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.9rem; }
.nx-sec-title { font-family: 'Syne', sans-serif; font-weight: 700; font-size: 0.98rem; color: #f0f4ff; letter-spacing: -0.02em; }
.nx-sec-meta  { font-family: 'DM Mono', monospace; font-size: 0.66rem; color: #6b738f; }

.nx-tbl-hd {
  background: #161b2e; border: 1px solid #1d2236; border-bottom: none;
  border-radius: 18px 18px 0 0; padding: 0.6rem 1.1rem;
  display: flex; align-items: center; justify-content: space-between; margin-bottom: -1px;
}
.nx-tbl-hd-txt { font-family: 'DM Mono', monospace; font-size: 0.63rem; color: #6b738f; letter-spacing: 0.08em; text-transform: uppercase; }

.nx-empty {
  text-align: center; padding: 3.25rem 2rem;
  border: 1px dashed #1d2236; border-radius: 18px;
  background: #111527; animation: fadeUp 0.3s ease both;
}
.nx-empty-icon { font-size: 2rem; opacity: 0.28; margin-bottom: 0.7rem; }
.nx-empty-t { font-family: 'Syne', sans-serif; font-weight: 700; color: #dde3f5; margin-bottom: 0.3rem; font-size: 0.93rem; }
.nx-empty-s { font-size: 0.78rem; color: #6b738f; }

.nx-feats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 0.85rem; }
.nx-feat {
  background: #111527; border: 1px solid #1d2236;
  border-radius: 18px; padding: 1.25rem;
  transition: transform 0.2s, border-color 0.2s;
  animation: fadeUp 0.4s ease both;
}
.nx-feat:hover { transform: translateY(-3px); border-color: #252a40; }
.nx-feat-icon  { font-size: 1.25rem; margin-bottom: 0.55rem; }
.nx-feat-t     { font-family: 'Syne', sans-serif; font-weight: 700; font-size: 0.83rem; color: #f0f4ff; margin-bottom: 0.3rem; }
.nx-feat-d     { font-size: 0.77rem; color: #6b738f; line-height: 1.6; }

.nx-steps { display: flex; align-items: center; gap: 0; margin-bottom: 1.25rem; }
.nx-step  { display: flex; align-items: center; gap: 0.45rem; flex: 1; min-width: 0; }
.nx-step-n {
  width: 25px; height: 25px; border-radius: 50%; flex-shrink: 0;
  border: 1px solid #252a40;
  display: flex; align-items: center; justify-content: center;
  font-family: 'DM Mono', monospace; font-size: 0.68rem; color: #6b738f;
  transition: all 0.3s;
}
.nx-step-a .nx-step-n { background: #00c8f0; border-color: #00c8f0; color: #040c14; font-weight: 700; box-shadow: 0 0 10px rgba(0,200,240,0.4); }
.nx-step-d .nx-step-n { background: rgba(0,223,160,0.1); border-color: #00dfa0; color: #00dfa0; }
.nx-step-lbl { font-size: 0.77rem; color: #6b738f; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.nx-step-a .nx-step-lbl { color: #dde3f5; font-weight: 600; }
.nx-step-line { flex-shrink: 0; width: 28px; height: 1px; background: #1d2236; }

.nx-cta {
  background: linear-gradient(135deg, rgba(0,200,240,0.04) 0%, rgba(124,108,250,0.04) 100%);
  border: 1px solid #1d2236; border-radius: 24px;
  padding: 1.6rem 2rem; text-align: center; margin: 1.1rem 0;
}
.nx-cta-t { font-family: 'Syne', sans-serif; font-weight: 700; font-size: 1rem; color: #dde3f5; margin-bottom: 0.28rem; }
.nx-cta-s { font-size: 0.78rem; color: #6b738f; margin-bottom: 1rem; }

.nx-chart { background: #111527; border: 1px solid #1d2236; border-radius: 18px; padding: 1.05rem 1.25rem; }
.nx-chart-t { font-family: 'Syne', sans-serif; font-weight: 700; font-size: 0.8rem; color: #dde3f5; margin-bottom: 0.8rem; }

.nx-export { padding: 1.4rem 2.5rem; border-top: 1px solid #1d2236; margin-top: 0.75rem; }
.nx-export-t { font-family: 'DM Mono', monospace; font-size: 0.62rem; color: #3d4460; letter-spacing: 0.12em; text-transform: uppercase; margin-bottom: 0.8rem; }

.nx-info {
  background: rgba(0,200,240,0.05); border: 1px solid rgba(0,200,240,0.18);
  border-radius: 12px; padding: 0.75rem 0.9rem;
  font-size: 0.78rem; color: #a8b0cc; line-height: 1.6; margin-top: 0.7rem;
}
.nx-info strong { color: #00c8f0; }

.nx-footer {
  padding: 1.4rem 2.5rem; border-top: 1px solid #1d2236;
  display: flex; align-items: center; justify-content: space-between; margin-top: 1rem;
}
.nx-footer-t { font-family: 'DM Mono', monospace; font-size: 0.62rem; color: #3d4460; }

@media (max-width: 980px) {
  .nx-nav       { padding: 0.85rem 1.25rem; }
  .nx-hero      { padding: 2rem 1.25rem 1.75rem; }
  .nx-metrics   { grid-template-columns: repeat(2, 1fr); padding: 1rem 1.25rem 0; }
  .nx-feats     { grid-template-columns: 1fr 1fr; }
  .nx-sec       { padding: 1rem 1.25rem 0; }
  .nx-term-wrap { padding: 1rem 1.25rem 0; }
  .nx-prog      { padding: 0.65rem 1.25rem 0.75rem; }
  .nx-export    { padding: 1rem 1.25rem; }
  .nx-footer    { padding: 1rem 1.25rem; }
  .nx-cta       { padding: 1.25rem 1.25rem; }
}
@media (max-width: 620px) {
  .nx-feats     { grid-template-columns: 1fr; }
  .nx-metrics   { grid-template-columns: 1fr 1fr; }
  .nx-nav-pills { display: none; }
  .nx-hero      { padding: 1.5rem 1rem 1.25rem; }
  .nx-h1        { font-size: 1.7rem; }
  .nx-steps     { flex-wrap: wrap; gap: 0.5rem; }
  .nx-step-line { display: none; }
  .nx-step      { flex: 0 0 auto; }
}
</style>
"""

# ── LIGHT layout CSS ─────────────────────────────────────────────────────────
LAYOUT_CSS_LIGHT = """
<style>
:root {
  --cyan:    #00c8f0;
  --cyan-d:  #008eaa;
  --violet:  #7c6cfa;
  --amber:   #ffb340;
  --rose:    #ff4f6e;
  --green:   #00a870;
  --fh: 'Syne', sans-serif;
  --fb: 'DM Sans', sans-serif;
  --fm: 'DM Mono', monospace;
}

*, *::before, *::after { box-sizing: border-box; }

html, body { background: #f2f5ff !important; color: #363d5c !important; }
.stApp { background: #f2f5ff !important; font-family: 'DM Sans', sans-serif; color: #363d5c !important; }
.stApp > header { display: none !important; }
[data-testid="stAppViewContainer"] { background: #f2f5ff !important; }
[data-testid="stMain"] { background: #f2f5ff !important; }
#MainMenu, footer, .stDeployButton { display: none !important; }
[data-testid="stDecoration"] { display: none !important; }

[data-testid="stMarkdownContainer"] p,
[data-testid="stMarkdownContainer"] li,
[data-testid="stMarkdownContainer"] span,
[data-testid="stMarkdownContainer"] { color: #363d5c !important; }

[data-baseweb="tab-panel"] { color: #363d5c !important; }
[data-baseweb="tab-panel"] p,
[data-baseweb="tab-panel"] span { color: #363d5c !important; }

section[data-testid="stSidebar"] {
  background: #eef1fb !important;
  border-right: 1px solid #d4daf0 !important;
}
section[data-testid="stSidebar"] * { color: #363d5c !important; }

h1, h2, h3, h4 { font-family: 'Syne', sans-serif; font-weight: 700; color: #0d1128 !important; letter-spacing: -0.02em; }
p, li { color: #363d5c !important; }

.stTextInput label, .stNumberInput label, .stSlider label,
.stFileUploader label, [data-testid="stWidgetLabel"] span {
  color: #606882 !important;
  font-family: 'DM Mono', monospace !important;
  font-size: 0.68rem !important;
  letter-spacing: 0.09em !important;
  text-transform: uppercase !important;
}

.stTextInput input,
.stTextInput input:focus,
.stTextInput input:active,
.stNumberInput input,
div[data-baseweb="input"] input,
div[data-baseweb="base-input"] input {
  background: #ffffff !important;
  background-color: #ffffff !important;
  border: 1px solid #bfc8e4 !important;
  color: #181e38 !important;
  -webkit-text-fill-color: #181e38 !important;
  caret-color: #008eaa !important;
  border-radius: 6px !important;
  font-family: 'DM Sans', sans-serif !important;
  font-size: 0.875rem !important;
}
.stTextInput input:focus { border-color: #00c8f0 !important; box-shadow: 0 0 0 3px rgba(0,200,240,0.1) !important; }

div[data-baseweb="select"] div,
div[data-baseweb="select"] span,
div[data-baseweb="select"] input {
  background: #ffffff !important;
  color: #181e38 !important;
  -webkit-text-fill-color: #181e38 !important;
  border-color: #bfc8e4 !important;
}
ul[data-baseweb="menu"], li[data-baseweb="menu-item"] {
  background: #ffffff !important; color: #181e38 !important;
}
li[data-baseweb="menu-item"]:hover { background: #eef1fb !important; }

.stButton > button {
  background: linear-gradient(135deg, #00c8f0 0%, #7c6cfa 100%) !important;
  color: #040c14 !important; border: none !important; border-radius: 12px !important;
  font-family: 'Syne', sans-serif !important; font-weight: 700 !important;
  font-size: 0.88rem !important; letter-spacing: 0.05em !important;
  padding: 0.62rem 1.5rem !important; text-transform: uppercase !important;
  box-shadow: 0 4px 20px rgba(0,200,240,0.22) !important;
  transition: transform 0.22s, box-shadow 0.22s !important;
}
.stButton > button:hover { transform: translateY(-2px) !important; }

[data-testid="stDownloadButton"] > button {
  background: transparent !important; color: #008eaa !important;
  border: 1px solid #008eaa !important; border-radius: 12px !important;
  font-family: 'Syne', sans-serif !important; font-weight: 600 !important;
  font-size: 0.76rem !important; text-transform: uppercase !important;
  padding: 0.5rem 1.1rem !important;
}

[data-testid="stFileUploader"] {
  background: #eef1fb !important; border: 1px dashed #bfc8e4 !important; border-radius: 12px !important;
}
[data-testid="stFileUploader"] * { color: #363d5c !important; }

.stTabs [data-baseweb="tab-list"] { background: transparent !important; border-bottom: 1px solid #d4daf0 !important; }
.stTabs [data-baseweb="tab"] {
  background: transparent !important; color: #606882 !important;
  font-family: 'Syne', sans-serif !important; font-weight: 600 !important;
  font-size: 0.76rem !important; letter-spacing: 0.06em !important;
  text-transform: uppercase !important; border: none !important;
  border-bottom: 2px solid transparent !important; padding: 0.65rem 1.3rem !important;
}
.stTabs [aria-selected="true"] { color: #00c8f0 !important; border-bottom-color: #00c8f0 !important; }

.stProgress > div > div > div { background: linear-gradient(90deg, #00c8f0, #7c6cfa) !important; border-radius: 99px !important; }
.stProgress > div > div { background: #e4e8f5 !important; border-radius: 99px !important; height: 5px !important; }

[data-testid="stDataFrame"] { background: #eef1fb !important; }
[data-testid="stDataEditor"] { background: #eef1fb !important; }

.stAlert { background: #eef1fb !important; border: 1px solid #bfc8e4 !important; border-radius: 12px !important; }
.stAlert p, .stAlert span { color: #363d5c !important; }

@keyframes fadeUp { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: translateY(0); } }
@keyframes pulseDot { 0%, 100% { box-shadow: 0 0 0 0 rgba(0,200,240,0.55); } 60% { box-shadow: 0 0 0 7px rgba(0,200,240,0); } }
@keyframes scanline { 0% { transform: translateY(-100%); } 100% { transform: translateY(600%); } }
@keyframes blink { 0%,100% { opacity:1; } 50% { opacity:0; } }

.nx-nav { display: flex; align-items: center; justify-content: space-between; padding: 0.85rem 2.5rem; border-bottom: 1px solid #d4daf0; background: #ffffff; position: sticky; top: 0; z-index: 999; animation: fadeUp 0.35s ease both; }
.nx-logo { font-family: 'Syne', sans-serif; font-weight: 800; font-size: 1.15rem; letter-spacing: -0.03em; color: #0d1128; display: flex; align-items: center; gap: 0.45rem; user-select: none; }
.nx-logo-dot { width: 7px; height: 7px; border-radius: 50%; background: #00c8f0; flex-shrink: 0; animation: pulseDot 2s ease-in-out infinite; }
.nx-nav-pills { display: flex; gap: 0.2rem; }
.nx-pill { font-family: 'Syne', sans-serif; font-size: 0.68rem; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; padding: 0.26rem 0.7rem; border-radius: 99px; color: #606882; border: 1px solid transparent; }
.nx-pill-on { color: #00c8f0; border-color: rgba(0,200,240,0.3); background: rgba(0,200,240,0.07); }
.nx-nav-right { display: flex; align-items: center; gap: 0.7rem; }
.nx-badge { font-family: 'DM Mono', monospace; font-size: 0.6rem; padding: 0.16rem 0.5rem; border-radius: 99px; background: rgba(0,200,240,0.08); color: #008eaa; border: 1px solid rgba(0,200,240,0.2); }
.nx-live { display: inline-flex; align-items: center; gap: 0.35rem; font-family: 'DM Mono', monospace; font-size: 0.63rem; letter-spacing: 0.06em; text-transform: uppercase; padding: 0.2rem 0.6rem; border-radius: 99px; color: #00a870; background: rgba(0,168,112,0.08); border: 1px solid rgba(0,168,112,0.25); }
.nx-live::before { content: ""; width: 5px; height: 5px; border-radius: 50%; background: #00a870; animation: pulseDot 1.5s infinite; }
.nx-idle { display: inline-flex; align-items: center; gap: 0.35rem; font-family: 'DM Mono', monospace; font-size: 0.63rem; letter-spacing: 0.06em; text-transform: uppercase; padding: 0.2rem 0.6rem; border-radius: 99px; color: #606882; background: rgba(96,104,130,0.08); border: 1px solid #d4daf0; }

.nx-hero { padding: 3.5rem 2.5rem 2.5rem; background-image: radial-gradient(ellipse 90% 70% at 50% -10%, rgba(0,200,240,0.05) 0%, transparent 65%), radial-gradient(ellipse 55% 45% at 85% 55%, rgba(124,108,250,0.04) 0%, transparent 55%); animation: fadeUp 0.45s ease 0.06s both; }
.nx-eyebrow { font-family: 'DM Mono', monospace; font-size: 0.67rem; color: #008eaa; letter-spacing: 0.16em; text-transform: uppercase; margin-bottom: 1rem; display: flex; align-items: center; gap: 0.5rem; }
.nx-eyebrow::before { content: ""; display: inline-block; width: 18px; height: 1px; background: #008eaa; flex-shrink: 0; }
.nx-h1 { font-family: 'Syne', sans-serif; font-size: clamp(1.9rem, 3.6vw, 3.1rem); font-weight: 800; line-height: 1.06; letter-spacing: -0.04em; color: #0d1128; margin-bottom: 1rem; }
.nx-grad { background: linear-gradient(135deg, #008eaa 0%, #7c6cfa 100%); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
.nx-sub { font-size: 0.93rem; color: #606882; line-height: 1.75; max-width: 500px; margin-bottom: 1.75rem; }
.nx-stats { display: flex; gap: 2.5rem; flex-wrap: wrap; }
.nx-stat { display: flex; flex-direction: column; gap: 0.12rem; }
.nx-stat-n { font-family: 'Syne', sans-serif; font-size: 1.5rem; font-weight: 800; color: #0d1128; letter-spacing: -0.03em; line-height: 1; }
.nx-stat-l { font-family: 'DM Mono', monospace; font-size: 0.62rem; color: #606882; letter-spacing: 0.08em; text-transform: uppercase; }
.nx-divider { height: 1px; background: linear-gradient(90deg, transparent, #d4daf0, transparent); }

.nx-sb-logo { padding: 1.1rem 1.1rem 0.9rem; border-bottom: 1px solid #d4daf0; margin-bottom: 0.9rem; }
.nx-sb-logo-text { font-family: 'Syne', sans-serif; font-weight: 800; font-size: 0.92rem; color: #0d1128; display: flex; align-items: center; gap: 0.4rem; }
.nx-sb-sec { font-family: 'DM Mono', monospace; font-size: 0.59rem; color: #9aa3c0; letter-spacing: 0.14em; text-transform: uppercase; padding: 0.6rem 0 0.35rem; border-bottom: 1px solid #d4daf0; margin-bottom: 0.5rem; }

.nx-metrics { display: grid; grid-template-columns: repeat(4, 1fr); gap: 0.85rem; padding: 1.5rem 2.5rem 0; }
.nx-metric { background: #eef1fb; border: 1px solid #d4daf0; border-radius: 18px; padding: 1.1rem 1.25rem; position: relative; overflow: hidden; transition: transform 0.2s, border-color 0.25s; animation: fadeUp 0.4s ease both; }
.nx-metric:hover { transform: translateY(-2px); border-color: #bfc8e4; }
.nx-metric::after { content: ""; position: absolute; top: 0; left: 0; right: 0; height: 1px; }
.nx-mc1::after { background: linear-gradient(90deg, transparent, #00c8f0, transparent); }
.nx-mc2::after { background: linear-gradient(90deg, transparent, #7c6cfa, transparent); }
.nx-mc3::after { background: linear-gradient(90deg, transparent, #ffb340, transparent); }
.nx-mc4::after { background: linear-gradient(90deg, transparent, #00a870, transparent); }
.nx-m-val { font-family: 'Syne', sans-serif; font-size: 1.9rem; font-weight: 800; letter-spacing: -0.04em; line-height: 1; margin-bottom: 0.28rem; }
.nx-mc1 .nx-m-val { color: #008eaa; }
.nx-mc2 .nx-m-val { color: #7c6cfa; }
.nx-mc3 .nx-m-val { color: #e09a30; }
.nx-mc4 .nx-m-val { color: #00a870; }
.nx-m-lbl { font-family: 'DM Mono', monospace; font-size: 0.61rem; color: #606882; letter-spacing: 0.1em; text-transform: uppercase; }
.nx-m-icon { position: absolute; right: 1rem; bottom: 0.85rem; font-size: 1.25rem; opacity: 0.1; }

.nx-term-wrap { padding: 1rem 2.5rem 0; }
.nx-term { background: #0d0f18; border: 1px solid #d4daf0; border-radius: 12px; overflow: hidden; font-family: 'DM Mono', monospace; position: relative; }
.nx-term::after { content: ""; position: absolute; left: 0; right: 0; height: 40px; background: linear-gradient(transparent, rgba(0,200,240,0.02), transparent); pointer-events: none; animation: scanline 3.5s linear infinite; }
.nx-term-bar { background: #161b2e; border-bottom: 1px solid #252a40; padding: 0.45rem 0.9rem; display: flex; align-items: center; gap: 0.35rem; }
.nx-term-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.nx-term-title { font-size: 0.64rem; color: #6b738f; letter-spacing: 0.08em; text-transform: uppercase; margin-left: 0.4rem; }
.nx-term-body { padding: 0.85rem 1rem; font-size: 0.74rem; line-height: 1.75; max-height: 200px; overflow-y: auto; color: #3ddc84; }
.t-hit { color: #00dfa0; } .t-miss { color: #4a5270; } .t-err { color: #ff4f6e; } .t-info { color: #6b9cf5; }
.nx-cursor { display: inline-block; width: 7px; height: 13px; background: #00c8f0; vertical-align: middle; animation: blink 1s step-end infinite; margin-left: 2px; }

.nx-prog { padding: 0.65rem 2.5rem 0.75rem; }
.nx-prog-lbl { font-family: 'DM Mono', monospace; font-size: 0.7rem; color: #606882; margin-bottom: 0.35rem; }

.nx-sec { padding: 1.4rem 2.5rem 0; }
.nx-sec-hd { display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.9rem; }
.nx-sec-title { font-family: 'Syne', sans-serif; font-weight: 700; font-size: 0.98rem; color: #0d1128; letter-spacing: -0.02em; }
.nx-sec-meta  { font-family: 'DM Mono', monospace; font-size: 0.66rem; color: #606882; }

.nx-tbl-hd { background: #e4e8f5; border: 1px solid #d4daf0; border-bottom: none; border-radius: 18px 18px 0 0; padding: 0.6rem 1.1rem; display: flex; align-items: center; justify-content: space-between; margin-bottom: -1px; }
.nx-tbl-hd-txt { font-family: 'DM Mono', monospace; font-size: 0.63rem; color: #606882; letter-spacing: 0.08em; text-transform: uppercase; }

.nx-empty { text-align: center; padding: 3.25rem 2rem; border: 1px dashed #d4daf0; border-radius: 18px; background: #eef1fb; animation: fadeUp 0.3s ease both; }
.nx-empty-icon { font-size: 2rem; opacity: 0.28; margin-bottom: 0.7rem; }
.nx-empty-t { font-family: 'Syne', sans-serif; font-weight: 700; color: #181e38; margin-bottom: 0.3rem; font-size: 0.93rem; }
.nx-empty-s { font-size: 0.78rem; color: #606882; }

.nx-feats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 0.85rem; }
.nx-feat { background: #eef1fb; border: 1px solid #d4daf0; border-radius: 18px; padding: 1.25rem; transition: transform 0.2s, border-color 0.2s; animation: fadeUp 0.4s ease both; }
.nx-feat:hover { transform: translateY(-3px); border-color: #bfc8e4; }
.nx-feat-icon { font-size: 1.25rem; margin-bottom: 0.55rem; }
.nx-feat-t { font-family: 'Syne', sans-serif; font-weight: 700; font-size: 0.83rem; color: #0d1128; margin-bottom: 0.3rem; }
.nx-feat-d { font-size: 0.77rem; color: #606882; line-height: 1.6; }

.nx-steps { display: flex; align-items: center; gap: 0; margin-bottom: 1.25rem; }
.nx-step { display: flex; align-items: center; gap: 0.45rem; flex: 1; min-width: 0; }
.nx-step-n { width: 25px; height: 25px; border-radius: 50%; flex-shrink: 0; border: 1px solid #bfc8e4; display: flex; align-items: center; justify-content: center; font-family: 'DM Mono', monospace; font-size: 0.68rem; color: #606882; transition: all 0.3s; }
.nx-step-a .nx-step-n { background: #00c8f0; border-color: #00c8f0; color: #040c14; font-weight: 700; box-shadow: 0 0 10px rgba(0,200,240,0.4); }
.nx-step-d .nx-step-n { background: rgba(0,168,112,0.1); border-color: #00a870; color: #00a870; }
.nx-step-lbl { font-size: 0.77rem; color: #606882; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.nx-step-a .nx-step-lbl { color: #181e38; font-weight: 600; }
.nx-step-line { flex-shrink: 0; width: 28px; height: 1px; background: #d4daf0; }

.nx-cta { background: linear-gradient(135deg, rgba(0,200,240,0.04) 0%, rgba(124,108,250,0.04) 100%); border: 1px solid #d4daf0; border-radius: 24px; padding: 1.6rem 2rem; text-align: center; margin: 1.1rem 0; }
.nx-cta-t { font-family: 'Syne', sans-serif; font-weight: 700; font-size: 1rem; color: #181e38; margin-bottom: 0.28rem; }
.nx-cta-s { font-size: 0.78rem; color: #606882; margin-bottom: 1rem; }

.nx-chart { background: #eef1fb; border: 1px solid #d4daf0; border-radius: 18px; padding: 1.05rem 1.25rem; }
.nx-chart-t { font-family: 'Syne', sans-serif; font-weight: 700; font-size: 0.8rem; color: #181e38; margin-bottom: 0.8rem; }

.nx-export { padding: 1.4rem 2.5rem; border-top: 1px solid #d4daf0; margin-top: 0.75rem; }
.nx-export-t { font-family: 'DM Mono', monospace; font-size: 0.62rem; color: #9aa3c0; letter-spacing: 0.12em; text-transform: uppercase; margin-bottom: 0.8rem; }

.nx-info { background: rgba(0,200,240,0.05); border: 1px solid rgba(0,200,240,0.18); border-radius: 12px; padding: 0.75rem 0.9rem; font-size: 0.78rem; color: #363d5c; line-height: 1.6; margin-top: 0.7rem; }
.nx-info strong { color: #008eaa; }

.nx-footer { padding: 1.4rem 2.5rem; border-top: 1px solid #d4daf0; display: flex; align-items: center; justify-content: space-between; margin-top: 1rem; }
.nx-footer-t { font-family: 'DM Mono', monospace; font-size: 0.62rem; color: #9aa3c0; }

@media (max-width: 980px) {
  .nx-nav { padding: 0.85rem 1.25rem; }
  .nx-hero { padding: 2rem 1.25rem 1.75rem; }
  .nx-metrics { grid-template-columns: repeat(2, 1fr); padding: 1rem 1.25rem 0; }
  .nx-feats { grid-template-columns: 1fr 1fr; }
  .nx-sec { padding: 1rem 1.25rem 0; }
  .nx-term-wrap { padding: 1rem 1.25rem 0; }
  .nx-prog { padding: 0.65rem 1.25rem 0.75rem; }
  .nx-export { padding: 1rem 1.25rem; }
  .nx-footer { padding: 1rem 1.25rem; }
}
@media (max-width: 620px) {
  .nx-feats { grid-template-columns: 1fr; }
  .nx-metrics { grid-template-columns: 1fr 1fr; }
  .nx-nav-pills { display: none; }
  .nx-hero { padding: 1.5rem 1rem 1.25rem; }
  .nx-h1 { font-size: 1.7rem; }
  .nx-steps { flex-wrap: wrap; gap: 0.5rem; }
  .nx-step-line { display: none; }
  .nx-step { flex: 0 0 auto; }
}
</style>
"""

# ═══════════════════════════════════════════════════════════════════════════════
# HTML COMPONENT BUILDERS
# ═══════════════════════════════════════════════════════════════════════════════

def _navbar(scanning: bool, dark: bool) -> str:
    status = '<span class="nx-live">● Scanning</span>' if scanning else '<span class="nx-idle">● Idle</span>'
    icon   = "☀" if dark else "☾"
    return (
        '<div class="nx-nav">'
        '  <div class="nx-logo"><span class="nx-logo-dot"></span>NEXUS'
        '    <span style="font-weight:400;font-size:0.68rem;margin-left:0.2rem;opacity:0.5">/ Web3 Radar</span>'
        '  </div>'
        '  <div class="nx-nav-pills">'
        '    <span class="nx-pill nx-pill-on">Scanner</span>'
        '    <span class="nx-pill">Analytics</span>'
        '    <span class="nx-pill">Pipeline</span>'
        '  </div>'
        '  <div class="nx-nav-right">'
        f'    {status}'
        f'    <span class="nx-badge">v{VERSION}</span>'
        f'    <span style="font-family:\'DM Mono\',monospace;font-size:0.78rem;opacity:0.5">{icon}</span>'
        '  </div>'
        '</div>'
    )

def _hero() -> str:
    return (
        '<div class="nx-hero">'
        '  <div class="nx-eyebrow">Talent Radar — Web3 Edition</div>'
        '  <h1 class="nx-h1">Find every<br><span class="nx-grad">open internship</span><br>in Web3.</h1>'
        '  <p class="nx-sub">Upload your company list. NEXUS auto-discovers career pages,'
        '  parses ATS systems, and extracts structured job data — all in parallel.</p>'
        '  <div class="nx-stats">'
        '    <div class="nx-stat"><span class="nx-stat-n">3×</span><span class="nx-stat-l">Detection layers</span></div>'
        '    <div class="nx-stat"><span class="nx-stat-n">12</span><span class="nx-stat-l">User-Agent strings</span></div>'
        '    <div class="nx-stat"><span class="nx-stat-n">∞</span><span class="nx-stat-l">Companies</span></div>'
        '  </div>'
        '</div>'
        '<div class="nx-divider"></div>'
    )

def _metrics(scanned: int, found: int, errors: int, remote: int) -> str:
    def card(v, l, cls, icon):
        return (f'<div class="nx-metric {cls}">'
                f'<div class="nx-m-val">{v}</div>'
                f'<div class="nx-m-lbl">{l}</div>'
                f'<div class="nx-m-icon">{icon}</div>'
                f'</div>')
    return (
        '<div class="nx-metrics">'
        + card(scanned, "Scanned",  "nx-mc1", "⬡")
        + card(found,   "Found",    "nx-mc2", "◈")
        + card(errors,  "Errors",   "nx-mc3", "◎")
        + card(remote,  "Remote",   "nx-mc4", "⊕")
        + '</div>'
    )

def _terminal(lines: list) -> str:
    body = ""
    for ln in lines[-24:]:
        if "✅" in ln:           body += f'<div class="t-hit">{ln}</div>'
        elif "❌" in ln:         body += f'<div class="t-err">{ln}</div>'
        elif "➖" in ln:         body += f'<div class="t-miss">{ln}</div>'
        elif ln.startswith("$"): body += f'<div class="t-info">{ln}</div>'
        else:                    body += f'<div>{ln}</div>'
    return (
        '<div class="nx-term-wrap"><div class="nx-term">'
        '  <div class="nx-term-bar">'
        '    <div class="nx-term-dot" style="background:#ff5f57"></div>'
        '    <div class="nx-term-dot" style="background:#ffbd2e"></div>'
        '    <div class="nx-term-dot" style="background:#28c940"></div>'
        '    <span class="nx-term-title">nexus-scanner // stdout</span>'
        '  </div>'
        f'  <div class="nx-term-body" id="nxt">{body}'
        '    <span class="nx-cursor"></span>'
        '  </div>'
        '</div></div>'
        '<script>var e=document.getElementById("nxt");if(e)e.scrollTop=e.scrollHeight;</script>'
    )

def _feature_grid() -> str:
    feats = [
        ("⬡", "Career Page Discovery",  "Probes 18+ URL patterns and parses nav links to find the real careers page."),
        ("◈", "3-Layer Extraction",      "schema.org JSON-LD → ATS HTML selectors → full-text fallback."),
        ("⚡", "Parallel Scanning",       "ThreadPoolExecutor with up to 10 workers. 50 companies in under 2 minutes."),
        ("🛡", "Polite Crawling",         "Robust robots.txt parsing, per-domain 429 backoff, 12 rotating user-agents."),
        ("⊕", "Smart JS Rendering",      "Selenium waits for actual job content selectors — not a blind sleep(2)."),
        ("◎", "Fuzzy Matching",          "Levenshtein-distance catch for typos: 'Internshhip', 'Internhip', 'Traineee'."),
    ]
    cards = "".join(
        f'<div class="nx-feat" style="animation-delay:{i*0.06}s">'
        f'<div class="nx-feat-icon">{f[0]}</div>'
        f'<div class="nx-feat-t">{f[1]}</div>'
        f'<div class="nx-feat-d">{f[2]}</div>'
        f'</div>'
        for i, f in enumerate(feats)
    )
    return f'<div class="nx-feats">{cards}</div>'

def _steps(active: int = 1) -> str:
    labels = ["Upload list", "Configure", "Launch scan", "Export"]
    out    = '<div class="nx-steps">'
    for i, lbl in enumerate(labels, 1):
        cls = "nx-step-a" if i == active else ("nx-step-d" if i < active else "")
        num = "✓" if i < active else str(i)
        out += (f'<div class="nx-step {cls}">'
                f'<div class="nx-step-n">{num}</div>'
                f'<span class="nx-step-lbl">{lbl}</span>'
                f'</div>')
        if i < len(labels):
            out += '<div class="nx-step-line"></div>'
    out += '</div>'
    return out

def _sb_logo() -> str:
    return (
        '<div class="nx-sb-logo">'
        '  <div class="nx-sb-logo-text">'
        '    <span style="color:#00c8f0">⬡</span> NEXUS'
        '  </div>'
        '  <div style="font-size:0.65rem;opacity:0.5;margin-top:0.12rem;font-family:\'DM Mono\',monospace">'
        '    Talent Intelligence Platform'
        '  </div>'
        '</div>'
    )

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN APP
# ═══════════════════════════════════════════════════════════════════════════════

def _html_table(df, max_rows: int = 500) -> None:
    """Render a DataFrame as a plain HTML table — no canvas, no iframe, full CSS control."""
    subset = df.head(max_rows)
    rows_html = ""
    for _, row in subset.iterrows():
        cells = ""
        for val in row:
            s = str(val)
            if s.startswith("http"):
                cells += f'<td><a href="{s}" target="_blank" style="color:#00c8f0;text-decoration:none">{s[:50]}…</a></td>'
            else:
                cells += f"<td>{s}</td>"
        rows_html += f"<tr>{cells}</tr>"

    headers = "".join(f"<th>{c}</th>" for c in subset.columns)

    html = f"""
    <div style="overflow-x:auto;overflow-y:auto;max-height:520px;border:1px solid #1d2236;border-radius:10px;margin-bottom:1rem">
    <table style="width:100%;border-collapse:collapse;font-family:'DM Sans',sans-serif;font-size:0.82rem">
      <thead>
        <tr style="background:#161b2e;position:sticky;top:0">
          {headers}
        </tr>
      </thead>
      <tbody>
        {rows_html}
      </tbody>
    </table>
    </div>
    <style>
    table th {{
      padding:0.55rem 0.85rem;
      text-align:left;
      color:#6b738f;
      font-family:'DM Mono',monospace;
      font-size:0.65rem;
      letter-spacing:0.08em;
      text-transform:uppercase;
      border-bottom:1px solid #1d2236;
      white-space:nowrap;
    }}
    table td {{
      padding:0.5rem 0.85rem;
      color:#a8b0cc;
      border-bottom:1px solid #111527;
      vertical-align:top;
      max-width:280px;
      overflow:hidden;
      text-overflow:ellipsis;
      white-space:nowrap;
    }}
    table tr:hover td {{ background:#111e2e; }}
    </style>
    """
    st.markdown(html, unsafe_allow_html=True)
    if len(df) > max_rows:
        st.caption(f"Showing {max_rows} of {len(df)} rows")


def main():
    st.set_page_config(
        page_title="NEXUS — Web3 Talent Intelligence",
        page_icon="⬡",
        layout="wide",
        initial_sidebar_state="expanded",
    )

    if "dark" not in st.session_state:
        st.session_state.dark = True

    # FIX [A]: Write config.toml before injecting CSS.
    # This ensures st.dataframe's canvas renderer uses the correct theme colours.
    _ensure_theme_config(st.session_state.dark)

    # Inject theme vars, then the full layout CSS for the current mode
    st.markdown(DARK_CSS if st.session_state.dark else LIGHT_CSS, unsafe_allow_html=True)
    st.markdown(LAYOUT_CSS_DARK if st.session_state.dark else LAYOUT_CSS_LIGHT, unsafe_allow_html=True)

    # ── Sidebar ───────────────────────────────────────────────────────────────
    with st.sidebar:
        st.markdown(_sb_logo(), unsafe_allow_html=True)

        st.markdown('<div class="nx-sb-sec">Appearance</div>', unsafe_allow_html=True)
        btn_lbl = "Switch to ☀️ Light Mode" if st.session_state.dark else "Switch to 🌙 Dark Mode"
        if st.button(btn_lbl, use_container_width=True, key="theme_btn"):
            st.session_state.dark = not st.session_state.dark
            st.rerun()

        st.markdown('<div class="nx-sb-sec">Search Parameters</div>', unsafe_allow_html=True)
        keywords_input = st.text_input(
            "Internship Keywords",
            "intern, internship, trainee, co-op, apprentice",
            key="kw",
        )
        exclude_input = st.text_input(
            "Exclude Keywords",
            "senior, staff, director, manager, principal",
            key="ex",
        )

        st.markdown('<div class="nx-sb-sec">Scan Configuration</div>', unsafe_allow_html=True)
        max_duration = st.slider("Max Duration (months, 0 = any)", 0, 18, 6, key="dur")
        scan_limit   = st.slider("Companies to Scan", 1, 200, 20, key="lim")
        concurrency  = st.slider("Parallel Workers",  1,  10,  4, key="con")
        use_js = (
            st.toggle("JS Rendering (Selenium)", False, key="js")
            if SELENIUM_AVAILABLE else False
        )

        st.markdown('<div class="nx-sb-sec">Data</div>', unsafe_allow_html=True)
        uploaded_file = st.file_uploader(
            "Upload Company List", type=["csv", "xlsx", "xls"],
            label_visibility="collapsed", key="upload",
        )
        sample_df = pd.DataFrame({
            "Company Name": ["Uniswap Labs", "Chainlink Labs", "OpenSea", "Alchemy", "Coinbase"],
            "URL": ["https://uniswap.org/careers", "https://careers.chain.link",
                    "https://opensea.io/careers", "https://www.alchemy.com/careers",
                    "https://www.coinbase.com/careers"],
            "Category": ["DEX", "Oracle", "NFT", "Infrastructure", "Exchange"],
        })
        st.download_button("⬇ Sample Template", sample_df.to_csv(index=False),
                           "nexus_template.csv", "text/csv",
                           use_container_width=True, key="dl_tmpl")
        if not SELENIUM_AVAILABLE:
            st.markdown(
                '<div class="nx-info"><strong>Tip:</strong> '
                'Install <code>selenium</code> + <code>webdriver-manager</code> '
                'to enable smart JS rendering.</div>',
                unsafe_allow_html=True,
            )

    # ── Navbar + Hero ─────────────────────────────────────────────────────────
    st.markdown(_navbar(False, st.session_state.dark), unsafe_allow_html=True)
    st.markdown(_hero(), unsafe_allow_html=True)

    if not uploaded_file:
        st.markdown(
            '<div class="nx-sec">' + _steps(1) + _feature_grid() + '</div>',
            unsafe_allow_html=True,
        )
        return

    # ── Load file ─────────────────────────────────────────────────────────────
    try:
        df = (pd.read_csv(uploaded_file)
              if uploaded_file.name.endswith(".csv")
              else pd.read_excel(uploaded_file, engine="openpyxl"))
        df.columns = df.columns.str.strip()
    except Exception as e:
        st.error(f"Failed to read file: {e}")
        return

    url_col = next(
        (c for c in df.columns
         if c.strip().lower() in ["url", "link", "website", "careers", "career url", "career_url"]),
        None,
    )
    name_col = next(
        (c for c in df.columns if "company" in c.lower() or "name" in c.lower()),
        df.columns[0],
    )

    if not url_col:
        st.error(f"No URL column found. Columns detected: {list(df.columns)}")
        return

    st.markdown(
        '<div class="nx-sec">'
        f'<div class="nx-sec-hd">'
        f'  <span class="nx-sec-title">Loaded Dataset</span>'
        f'  <span class="nx-sec-meta">{len(df)} companies · '
        f'url_col = <code style="color:#00c8f0">{url_col}</code></span>'
        f'</div></div>',
        unsafe_allow_html=True,
    )
    _html_table(df.head(10))

    to_scan_count = min(scan_limit, int(df[url_col].notna().sum()))
    st.markdown(
        '<div class="nx-sec">'
        + _steps(2)
        + f'<div class="nx-cta">'
          f'  <div class="nx-cta-t">Ready to Scan {to_scan_count} Companies</div>'
          f'  <div class="nx-cta-s">NEXUS will auto-discover career pages, run 3-layer'
          f'  extraction with fuzzy matching, and return structured data.</div>'
          f'</div></div>',
        unsafe_allow_html=True,
    )

    col_btn, _, _ = st.columns([1, 2, 2])
    with col_btn:
        launch = st.button("⬡  LAUNCH SCAN", use_container_width=True, key="launch")

    if not launch:
        return

    # ═══════════════════════════════════════════════════════════════════════════
    # SCAN
    # ═══════════════════════════════════════════════════════════════════════════
    search_terms  = [k.strip().lower() for k in keywords_input.split(",") if k.strip()]
    exclude_terms = [k.strip().lower() for k in exclude_input.split(",") if k.strip()]
    to_scan = df.dropna(subset=[url_col]).head(scan_limit).reset_index(drop=True)
    total   = len(to_scan)

    st.markdown(_navbar(True, st.session_state.dark), unsafe_allow_html=True)
    st.markdown('<div class="nx-sec">' + _steps(3) + '</div>', unsafe_allow_html=True)

    all_results: list = []
    log_lines:   list = []
    errors_list: list = []
    done_list:   list = []

    metrics_ph  = st.empty()
    prog_ph     = st.empty()
    prog_bar    = st.progress(0.0)
    terminal_ph = st.empty()

    metrics_ph.markdown(_metrics(0, 0, 0, 0), unsafe_allow_html=True)
    log_lines += [
        f"$ nexus-scanner v{VERSION} — {datetime.now().strftime('%H:%M:%S')}",
        f"$ {total} targets queued  ·  workers={concurrency}  ·  js={'on' if use_js else 'off'}",
        "$ starting ...",
    ]
    terminal_ph.markdown(_terminal(log_lines), unsafe_allow_html=True)

    def refresh():
        hits   = [r for r in all_results if r.get("Title", "—") not in ("—", "No internship found")]
        remote = sum(1 for r in hits if "remote" in r.get("Location", "").lower())
        metrics_ph.markdown(_metrics(len(done_list), len(hits), len(errors_list), remote),
                            unsafe_allow_html=True)
        terminal_ph.markdown(_terminal(log_lines), unsafe_allow_html=True)

    with ThreadPoolExecutor(max_workers=concurrency) as ex:
        futures = {
            ex.submit(
                scrape_company,
                row.to_dict(), url_col, name_col,
                search_terms, exclude_terms,
                float(max_duration), use_js,
            ): str(row[name_col])
            for _, row in to_scan.iterrows()
        }
        for fut in as_completed(futures):
            company = futures[fut]
            try:
                rows = fut.result()
                all_results.extend(rows)
                done_list.append(company)
                n = sum(1 for r in rows if r.get("Title", "—") not in ("—", "No internship found"))
                log_lines.append(
                    f"✅ [{company}] — {n} position(s)" if n
                    else f"➖ [{company}] — no listings"
                )
            except Exception as exc:
                errors_list.append(company)
                log_lines.append(f"❌ [{company}] — {type(exc).__name__}: {exc}")

            prog_bar.progress(min(len(done_list) / total, 1.0))
            prog_ph.markdown(
                f'<div class="nx-prog">'
                f'<div class="nx-prog-lbl">Scanning '
                f'<span style="color:#00c8f0">{company}</span>'
                f' — {len(done_list)}/{total}</div></div>',
                unsafe_allow_html=True,
            )
            refresh()

    prog_bar.progress(1.0)
    ts_done = datetime.now().strftime("%H:%M:%S")
    log_lines.append(f"$ ✓ complete — {total} companies processed — {ts_done}")
    prog_ph.markdown(
        f'<div class="nx-prog"><div class="nx-prog-lbl" style="color:#00dfa0">'
        f'✓ Scan complete — {total} companies — {ts_done}</div></div>',
        unsafe_allow_html=True,
    )
    terminal_ph.markdown(_terminal(log_lines), unsafe_allow_html=True)

    # ═══════════════════════════════════════════════════════════════════════════
    # RESULTS
    # ═══════════════════════════════════════════════════════════════════════════
    if not all_results:
        st.markdown(
            '<div class="nx-sec"><div class="nx-empty">'
            '<div class="nx-empty-icon">◎</div>'
            '<div class="nx-empty-t">No results returned</div>'
            '<div class="nx-empty-s">Relax keyword filters or increase scan limit.</div>'
            '</div></div>',
            unsafe_allow_html=True,
        )
        return

    res_df = pd.DataFrame(all_results)
    for col in ["Title", "Company", "Location", "Duration", "Deadline",
                "Apply Link", "Company URL", "Source", "Error"]:
        if col not in res_df.columns:
            res_df[col] = "—"
    res_df["Error"] = res_df["Error"].fillna("")

    NO_HIT  = {"—", "No internship found"}
    hits_df = res_df[res_df["Title"].notna() & ~res_df["Title"].isin(NO_HIT)].reset_index(drop=True)
    miss_df = res_df[res_df["Title"] == "No internship found"].reset_index(drop=True)
    err_df  = res_df[res_df["Error"].str.len() > 0].reset_index(drop=True)

    st.markdown(
        '<div class="nx-sec" style="margin-top:1rem">'
        + _steps(4)
        + f'<div class="nx-sec-hd">'
          f'  <span class="nx-sec-title">Scan Results</span>'
          f'  <span class="nx-sec-meta">'
          f'    {len(hits_df)} internships &nbsp;·&nbsp;'
          f'    {len(miss_df)} no listings &nbsp;·&nbsp;'
          f'    {len(err_df)} errors'
          f'  </span>'
          f'</div></div>',
        unsafe_allow_html=True,
    )

    tab1, tab2, tab3 = st.tabs([
        f"⬡  Internships  ({len(hits_df)})",
        f"◎  No Listings  ({len(miss_df)})",
        f"✕  Errors  ({len(err_df)})",
    ])

    with tab1:
        if hits_df.empty:
            st.markdown(
                '<div class="nx-empty">'
                '<div class="nx-empty-icon">◈</div>'
                '<div class="nx-empty-t">No internship listings detected</div>'
                '<div class="nx-empty-s">Try adjusting keywords or enable JS rendering for SPAs.</div>'
                '</div>',
                unsafe_allow_html=True,
            )
        else:
            display_cols = [c for c in
                ["Company", "Title", "Location", "Duration", "Deadline", "Apply Link", "Source"]
                if c in hits_df.columns]
            st.markdown(
                '<div class="nx-tbl-hd">'
                '  <span class="nx-tbl-hd-txt">Internship Opportunities</span>'
                f' <span class="nx-tbl-hd-txt" style="color:#00c8f0">{len(hits_df)} listings</span>'
                '</div>',
                unsafe_allow_html=True,
            )
            _html_table(hits_df[display_cols])

            st.markdown("<br>", unsafe_allow_html=True)
            c1, c2 = st.columns(2)
            with c1:
                st.markdown('<div class="nx-chart"><div class="nx-chart-t">Location Distribution</div>',
                            unsafe_allow_html=True)
                loc_df = hits_df["Location"].value_counts().head(8).reset_index()
                loc_df.columns = ["Location", "Count"]
                st.bar_chart(loc_df.set_index("Location"), color="#00c8f0")
                st.markdown("</div>", unsafe_allow_html=True)
            with c2:
                st.markdown('<div class="nx-chart"><div class="nx-chart-t">Detection Method</div>',
                            unsafe_allow_html=True)
                src_df = hits_df["Source"].value_counts().reset_index()
                src_df.columns = ["Source", "Count"]
                st.bar_chart(src_df.set_index("Source"), color="#7c6cfa")
                st.markdown("</div>", unsafe_allow_html=True)

    with tab2:
        if miss_df.empty:
            st.markdown('<div class="nx-empty"><div class="nx-empty-icon">◎</div>'
                        '<div class="nx-empty-t">All companies returned listings</div></div>',
                        unsafe_allow_html=True)
        else:
            cols = [c for c in ["Company", "Apply Link"] if c in miss_df.columns]
            _html_table(miss_df[cols].drop_duplicates())

    with tab3:
        if err_df.empty:
            st.markdown('<div class="nx-empty"><div class="nx-empty-icon">⊕</div>'
                        '<div class="nx-empty-t">Zero errors — clean run</div></div>',
                        unsafe_allow_html=True)
        else:
            cols = [c for c in ["Company", "Error", "Apply Link"] if c in err_df.columns]
            _html_table(err_df[cols].drop_duplicates())

    # ── Export ────────────────────────────────────────────────────────────────
    ts = datetime.now().strftime("%Y%m%d_%H%M")
    st.markdown('<div class="nx-export"><div class="nx-export-t">Export Results</div>',
                unsafe_allow_html=True)
    ea, eb, ec = st.columns(3)
    with ea:
        st.download_button("⬇ All Results (CSV)", res_df.to_csv(index=False),
                           f"nexus_all_{ts}.csv", "text/csv", use_container_width=True)
    with eb:
        if not hits_df.empty:
            st.download_button("⬇ Hits Only (CSV)", hits_df.to_csv(index=False),
                               f"nexus_hits_{ts}.csv", "text/csv", use_container_width=True)
    with ec:
        if not hits_df.empty:
            try:
                buf = io.BytesIO()
                with pd.ExcelWriter(buf, engine="openpyxl") as w:
                    hits_df.to_excel(w, sheet_name="Internships", index=False)
                    res_df.to_excel(w,  sheet_name="All Results", index=False)
                    miss_df.to_excel(w, sheet_name="No Listings", index=False)
                st.download_button(
                    "⬇ Full Report (XLSX)", buf.getvalue(),
                    f"nexus_report_{ts}.xlsx",
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    use_container_width=True,
                )
            except Exception:
                pass
    st.markdown("</div>", unsafe_allow_html=True)

    # ── Footer ────────────────────────────────────────────────────────────────
    st.markdown(
        f'<div class="nx-footer">'
        f'  <span class="nx-footer-t">NEXUS v{VERSION} — Web3 Talent Intelligence</span>'
        f'  <span class="nx-footer-t">{datetime.now().strftime("%d %b %Y, %H:%M")}</span>'
        f'</div>',
        unsafe_allow_html=True,
    )


if __name__ == "__main__":
    main()
