"""Unofficial NSE option-chain fetcher (same JSON that nseindia.com/option-chain page uses).
NSE needs browser-like headers + cookies. Endpoints can change or block; keep poll >= 30-60s."""
import time, requests

BASE = "https://www.nseindia.com"
HEAD = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": BASE + "/option-chain",
}


class NSEClient:
    def __init__(self):
        self.s = requests.Session(); self.s.headers.update(HEAD); self.warm_t = 0

    def _warm(self):
        self.s.get(BASE + "/", timeout=15)
        self.s.get(BASE + "/option-chain", timeout=15)
        self.warm_t = time.time()

    def _get(self, url):
        if time.time() - self.warm_t > 240:
            self._warm()
        r = self.s.get(url, timeout=15)
        if r.status_code in (401, 403) or not r.text.lstrip().startswith(("{", "[")):
            self._warm(); r = self.s.get(url, timeout=15)
        r.raise_for_status()
        return r.json()

    def fetch(self, symbol="NIFTY"):
        """Returns {'spot','expiry','rows':[{strike,ce:{},pe:{}}]} for the nearest expiry."""
        info = self._get(f"{BASE}/api/option-chain-contract-info?symbol={symbol}")
        expiry = info["expiryDates"][0]
        try:
            j = self._get(f"{BASE}/api/option-chain-v3?type=Indices&symbol={symbol}&expiry={expiry}")
        except Exception:
            j = self._get(f"{BASE}/api/option-chain-indices?symbol={symbol}")
        rec = j["records"]
        rows = []
        for d in rec["data"]:
            if d.get("expiryDate", expiry) != expiry:
                continue
            rows.append({"strike": float(d["strikePrice"]),
                         "ce": self._leg(d.get("CE")), "pe": self._leg(d.get("PE"))})
        rows.sort(key=lambda r: r["strike"])
        spot = float(rec.get("underlyingValue") or next(
            (d["CE"]["underlyingValue"] for d in rec["data"] if d.get("CE")), 0))
        return {"ts": time.time(), "spot": spot, "expiry": expiry, "rows": rows}

    def index_components(self, index="NIFTY 50"):
        aliases={
            "NIFTY":"NIFTY 50",
            "NIFTY 50":"NIFTY 50",
            "BANK NIFTY":"NIFTY BANK",
            "BANKNIFTY":"NIFTY BANK",
            "FINNIFTY":"NIFTY FIN SERVICE",
            "MIDCPNIFTY":"NIFTY MIDCAP SELECT",
        }
        name=aliases.get(index.upper(), index.upper())
        j=self._get(BASE + "/api/equity-stockIndices?index=" + requests.utils.quote(name))
        data=j.get("data",[]) if isinstance(j,dict) else []
        rows=[]
        for x in data:
            if not isinstance(x,dict): continue
            rows.append({
                "symbol":x.get("symbol"),
                "name":x.get("meta",{}).get("companyName") if isinstance(x.get("meta"),dict) else x.get("symbol"),
                "lastPrice":x.get("lastPrice"),
                "change":x.get("change"),
                "pChange":x.get("pChange"),
                "previousClose":x.get("previousClose"),
                "open":x.get("open"),
                "dayHigh":x.get("dayHigh"),
                "dayLow":x.get("dayLow"),
                "totalTradedVolume":x.get("totalTradedVolume"),
                "isFnoSec":x.get("isFnoSec"),
            })
        return {"index":name,"rows":rows,"ts":time.time()}

    @staticmethod
    def _leg(x):
        x = x or {}
        return {"oi": float(x.get("openInterest", 0)), "chg_oi": float(x.get("changeinOpenInterest", 0)),
                "ltp": float(x.get("lastPrice", 0)), "chg": float(x.get("change", 0)),
                "iv": float(x.get("impliedVolatility", 0)), "vol": float(x.get("totalTradedVolume", 0))}
