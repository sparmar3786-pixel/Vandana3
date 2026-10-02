import os
from dotenv import load_dotenv
load_dotenv()
g = os.getenv
API_KEY = g("ANGEL_API_KEY"); CLIENT = g("ANGEL_CLIENT_CODE")
PIN = g("ANGEL_PIN"); TOTP_SECRET = g("ANGEL_TOTP_SECRET")
SYMBOL = g("SYMBOL", "NIFTY")
N = int(g("STRIKES_EACH_SIDE", 5))
POLL_SEC = int(g("POLL_SEC", 5))
LOOKBACK_SEC = int(g("LOOKBACK_SEC", 300))
SL_PCT = float(g("SL_PCT", 0.20))
RR = float(g("RR", 1.5))
THRESH = float(g("SIGNAL_THRESHOLD", 0.35))
API_TOKEN = g("API_TOKEN", "").strip()
NSE_POLL_SEC = int(g("NSE_POLL_SEC", 60))

# --- Vandana2 Build 14 six-layer AI configuration ---
AI_ENABLED = g("AI_ENABLED", "on").strip().lower() in {"1","on","true","yes"}
AI_TRANSPORT = g("AI_TRANSPORT", "direct").strip().lower()
AI_WEB_SEARCH = g("AI_WEB_SEARCH", "off").strip().lower() in {"1","on","true","yes"}
AI_MODEL_L1 = g("AI_MODEL_L1", "gpt-5.6-luna")
AI_MODEL_L2 = g("AI_MODEL_L2", "claude-sonnet-4.6")
AI_MODEL_L3 = g("AI_MODEL_L3", "gpt-5.6-sol")
AI_MODEL_L4 = g("AI_MODEL_L4", "deepseek-chat")
AI_MODEL_L5 = g("AI_MODEL_L5", "gemini-2.5-flash")
AI_MODEL_L6 = g("AI_MODEL_L6", "grok-4")
OPENAI_API_KEY = g("OPENAI_API_KEY")
ANTHROPIC_API_KEY = g("ANTHROPIC_API_KEY")
DEEPSEEK_API_KEY = g("DEEPSEEK_API_KEY")
GOOGLE_API_KEY = g("GOOGLE_API_KEY")
XAI_API_KEY = g("XAI_API_KEY")
PUTER_AUTH_TOKEN = g("PUTER_AUTH_TOKEN")
PUTER_API_BASE = g("PUTER_API_BASE", "https://api.puter.com")
