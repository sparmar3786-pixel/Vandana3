"""Angel One SmartAPI client for Vandana2.

Authentication is server-side:
Client ID + PIN/MPIN + current TOTP + SmartAPI API key
    -> loginByPassword
    -> JWT + refresh token + feed token
    -> SmartConnect for REST APIs
    -> SmartWebSocketV2 for live ticks

No order-placement method is exposed by this client.
"""
import datetime as dt
import json
import os
import threading
import time
import urllib.request
from typing import Callable, Optional

import pyotp
import requests
from SmartApi import SmartConnect
from SmartApi.smartWebSocketV2 import SmartWebSocketV2

import config as C

MASTER_URL = "https://margincalculator.angelone.in/OpenAPI_File/files/OpenAPIScripMaster.json"
LOGIN_URL = "https://apiconnect.angelone.in/rest/auth/angelbroking/user/v1/loginByPassword"
TOKEN_URL = "https://apiconnect.angelone.in/rest/auth/angelbroking/jwt/v1/generateTokens"

INDEX = {
    "NIFTY": ("NSE", "99926000"),
    "BANKNIFTY": ("NSE", "99926009"),
    "FINNIFTY": ("NSE", "99926037"),
    "MIDCPNIFTY": ("NSE", "99926074"),
    "SENSEX": ("BSE", "99919000"),
    "BANKEX": ("BSE", "99919012"),
}
EXCHANGE_TYPE = {"NSE": 1, "NFO": 2, "BSE": 3, "BFO": 4, "MCX": 5}
CACHE = "scrip_master.json"


class AngelClient:
    def __init__(self):
        self.api = None
        self.api_key = C.API_KEY
        self.client_code = C.CLIENT
        self.pin = C.PIN
        self.totp_secret = C.TOTP_SECRET
        self.refresh_token = None
        self.feed_token = None
        self.login_at = None
        self.last_error = None
        self.chain = {}
        self.strikes = []
        self.expiry = None
        self.prev_oi = {}
        self.live_ticks = {}
        self.live_connected = False
        self.live_last_tick = None
        self.live_error = None
        self._ws = None
        self._ws_thread = None
        self._ws_stop = threading.Event()
        self._ws_lock = threading.Lock()

    # ---------- authentication ----------

    def _headers(self, api_key: str, public_ip: str = "127.0.0.1") -> dict:
        return {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-UserType": "USER",
            "X-SourceID": "WEB",
            "X-ClientLocalIP": "127.0.0.1",
            "X-ClientPublicIP": public_ip,
            "X-MACAddress": "00:00:00:00:00:00",
            "X-PrivateKey": api_key,
        }

    def _public_ip(self) -> str:
        try:
            return requests.get("https://api.ipify.org", timeout=3).text.strip() or "127.0.0.1"
        except Exception:
            return "127.0.0.1"

    def _set_session(self, api_key: str, client_code: str, data: dict) -> None:
        jwt = data.get("jwtToken")
        refresh = data.get("refreshToken")
        feed = data.get("feedToken")
        if not jwt or not refresh or not feed:
            raise RuntimeError("Angel One login succeeded without all required session tokens.")
        self.api_key = api_key
        self.client_code = client_code
        self.refresh_token = refresh
        self.feed_token = feed
        self.login_at = time.time()
        self.api = SmartConnect(
            api_key=api_key,
            access_token=jwt,
            refresh_token=refresh,
            feed_token=feed,
            userId=client_code,
        )

    def login(self, api_key=None, client_code=None, pin=None, totp=None):
        api_key = (api_key or self.api_key or C.API_KEY or "").strip()
        client_code = (client_code or self.client_code or C.CLIENT or "").strip()
        pin = (pin or self.pin or C.PIN or "").strip()
        totp = (totp or "").strip()
        if not totp and self.totp_secret:
            totp = pyotp.TOTP(self.totp_secret).now()
        if not api_key or not client_code or not pin or not totp:
            raise RuntimeError("Angel One API key, Client ID, PIN/MPIN and current TOTP are required.")
        if len(totp) != 6 or not totp.isdigit():
            raise RuntimeError("TOTP must be the current 6-digit code.")

        public_ip = self._public_ip()
        body = {"clientcode": client_code, "password": pin, "totp": totp}
        try:
            response = requests.post(
                LOGIN_URL,
                headers=self._headers(api_key, public_ip),
                json=body,
                timeout=12,
            )
        except requests.RequestException as exc:
            self.last_error = "Angel login network error: " + str(exc)
            raise RuntimeError(self.last_error)

        try:
            result = response.json()
        except ValueError:
            result = {}
        if response.status_code != 200 or not result.get("status"):
            message = result.get("message") or result.get("errorcode") or "Angel One login rejected"
            detail = f"{message} (HTTP {response.status_code})"
            self.last_error = detail
            self.api = None
            raise RuntimeError(detail)

        self._set_session(api_key, client_code, result["data"])

        # Authentication success must not depend on the instrument-master download.
        # If profile/master is temporarily unavailable, the session remains usable.
        try:
            self.build_chain()
        except Exception as exc:
            self.last_error = "Login OK; instrument master unavailable: " + str(exc)
        else:
            self.last_error = None

        self.start_live()
        return result

    def refresh_session(self):
        if not self.api or not self.refresh_token:
            return self.login()
        public_ip = self._public_ip()
        headers = self._headers(self.api_key, public_ip)
        headers["Authorization"] = "Bearer " + self.api.access_token
        try:
            r = requests.post(
                TOKEN_URL,
                headers=headers,
                json={"refreshToken": self.refresh_token},
                timeout=12,
            )
            data = r.json()
        except Exception as exc:
            raise RuntimeError("Angel token refresh failed: " + str(exc))
        if r.status_code != 200 or not data.get("status"):
            raise RuntimeError(data.get("message") or data.get("errorcode") or "Angel token refresh rejected")
        self._set_session(self.api_key, self.client_code, data["data"])
        self.start_live()
        return data

    def ensure_session(self):
        if self.api is None:
            return self.login()
        # SmartAPI documentation states the authenticated session is active until
        # midnight; refresh proactively after several hours during a long process.
        if self.login_at and time.time() - self.login_at > 3.5 * 3600:
            try:
                return self.refresh_session()
            except Exception:
                return self.login()
        return {"status": True, "data": {"feedToken": self.feed_token}}

    # ---------- live WebSocket 2.0 ----------

    def _live_tokens(self):
        wanted = []
        for name in ("NIFTY", "BANKNIFTY", "FINNIFTY", "MIDCPNIFTY"):
            ex, token = INDEX[name]
            wanted.append({"exchangeType": EXCHANGE_TYPE[ex], "tokens": [token]})
        # Add the currently selected option strikes after the master is loaded.
        option_tokens = [x["token"] for x in self.chain.values()]
        if option_tokens:
            wanted.append({"exchangeType": EXCHANGE_TYPE["NFO"], "tokens": option_tokens[:900]})
        return wanted

    def _on_live_open(self, wsapp):
        self.live_connected = True
        self.live_error = None
        tokens = self._live_tokens()
        try:
            # LTP for indices; SNAP_QUOTE for options so OI is available.
            index_groups = [x for x in tokens if x["exchangeType"] in (1, 3)]
            option_groups = [x for x in tokens if x["exchangeType"] in (2, 4, 5)]
            if index_groups:
                self._ws.subscribe("vandana2idx", 1, index_groups)
            for group in option_groups:
                for start in range(0, len(group["tokens"]), 50):
                    self._ws.subscribe(
                        "vandana2opt",
                        3,
                        [{"exchangeType": group["exchangeType"], "tokens": group["tokens"][start:start + 50]}],
                    )
        except Exception as exc:
            self.live_error = "Subscription failed: " + str(exc)

    def _on_live_data(self, wsapp, message):
        try:
            token = str(message.get("token"))
            mode = int(message.get("subscription_mode", 0))
            raw_ltp = message.get("last_traded_price")
            tick = {
                "token": token,
                "exchangeType": message.get("exchange_type"),
                "mode": mode,
                "ltp": (float(raw_ltp) / 100.0) if raw_ltp is not None else None,
                "timestamp": message.get("exchange_timestamp"),
            }
            if mode == 3:
                if message.get("open_interest") is not None:
                    tick["oi"] = int(message["open_interest"])
                if message.get("open_interest_change_percentage") is not None:
                    tick["oiChangePct"] = float(message["open_interest_change_percentage"]) / 100.0
            self.live_ticks[token] = tick
            self.live_last_tick = time.time()
        except Exception as exc:
            self.live_error = "Tick parse failed: " + str(exc)

    def _on_live_error(self, wsapp, error):
        self.live_connected = False
        self.live_error = str(error)

    def _on_live_close(self, wsapp):
        self.live_connected = False

    def _live_loop(self):
        while not self._ws_stop.is_set():
            if self.api is None or not self.feed_token:
                break
            try:
                with self._ws_lock:
                    self._ws = SmartWebSocketV2(
                        self.api.access_token,
                        self.api_key,
                        self.client_code,
                        self.feed_token,
                        max_retry_attempt=2,
                        retry_strategy=1,
                        retry_delay=5,
                        retry_multiplier=2,
                        retry_duration=30,
                    )
                    self._ws.on_open = self._on_live_open
                    self._ws.on_data = self._on_live_data
                    self._ws.on_error = self._on_live_error
                    self._ws.on_close = self._on_live_close
                    self._ws.connect()
            except Exception as exc:
                self.live_connected = False
                self.live_error = str(exc)
            finally:
                with self._ws_lock:
                    self._ws = None
            if not self._ws_stop.is_set():
                time.sleep(5)

    def start_live(self):
        if self.api is None or not self.feed_token:
            return
        with self._ws_lock:
            if self._ws_thread and self._ws_thread.is_alive():
                return
            self._ws_stop.clear()
            self._ws_thread = threading.Thread(target=self._live_loop, daemon=True, name="angel-websocket-v2")
            self._ws_thread.start()

    def stop_live(self):
        self._ws_stop.set()
        with self._ws_lock:
            try:
                if self._ws:
                    self._ws.close_connection()
            except Exception:
                pass
            self._ws = None
        self.live_connected = False

    # ---------- instrument master ----------

    def _master(self):
        fresh = os.path.exists(CACHE) and time.time() - os.path.getmtime(CACHE) < 43200
        if not fresh:
            urllib.request.urlretrieve(MASTER_URL, CACHE)
        with open(CACHE, encoding="utf-8") as f:
            return json.load(f)

    def build_chain(self):
        today = dt.date.today()
        rows = [
            r for r in self._master()
            if r.get("name") == C.SYMBOL
            and r.get("exch_seg") == "NFO"
            and r.get("instrumenttype") == "OPTIDX"
        ]
        def exp(r):
            return dt.datetime.strptime(r["expiry"], "%d%b%Y").date()
        expiries = sorted({exp(r) for r in rows if exp(r) >= today})
        if not expiries:
            raise RuntimeError(f"No active {C.SYMBOL} option expiry found.")
        self.expiry = expiries[0]
        self.chain = {}
        for r in rows:
            if exp(r) != self.expiry:
                continue
            strike = float(r["strike"]) / 100
            typ = r["symbol"][-2:]
            if typ in ("CE", "PE"):
                self.chain[(strike, typ)] = {"token": str(r["token"]), "symbol": r["symbol"]}
        self.strikes = sorted({k[0] for k in self.chain})
        if self.api is not None:
            self.start_live()

    # ---------- REST market data ----------

    def require_api(self):
        if self.api is None:
            raise RuntimeError("Angel One session is not connected.")
        return self.api

    def _rest_with_retry(self, fn):
        self.ensure_session()
        try:
            return fn(self.api)
        except Exception as first:
            try:
                self.refresh_session()
                return fn(self.api)
            except Exception:
                raise first

    def spot(self):
        def call(api):
            r = api.getMarketData("LTP", {"NSE": [INDEX[C.SYMBOL][1]]})
            return float(r["data"]["fetched"][0]["ltp"])
        return self._rest_with_retry(call)

    def index_quote(self, symbols=None):
        master = self._master()
        aliases = {
            "NIFTY": ["NIFTY", "NIFTY 50"],
            "BANKNIFTY": ["BANKNIFTY", "NIFTY BANK"],
            "FINNIFTY": ["FINNIFTY", "NIFTY FIN SERVICE"],
            "MIDCPNIFTY": ["MIDCPNIFTY", "NIFTY MIDCAP SELECT", "MIDCAP SELECT"],
            "SENSEX": ["SENSEX", "BSE SENSEX"],
            "BANKEX": ["BANKEX", "BSE BANKEX"],
        }
        selected = []
        for wanted_name, names in aliases.items():
            rows = [
                r for r in master
                if str(r.get("name", "")).upper() in {n.upper() for n in names}
                and str(r.get("exch_seg", "")).upper() in ("NSE", "BSE")
            ]
            if rows:
                rows.sort(key=lambda x: (0 if str(x.get("name", "")).upper() == wanted_name else 1, str(x.get("exch_seg", ""))))
                selected.append(rows[0])
        if not selected:
            raise RuntimeError("No supported index instruments found in Angel instrument master.")
        by_exchange = {}
        for r in selected:
            by_exchange.setdefault(str(r["exch_seg"]), []).append(str(r["token"]))
        result = self._rest_with_retry(lambda api: api.getMarketData("FULL", by_exchange))
        fetched = (result.get("data") or {}).get("fetched") or []
        meta = {str(r["token"]): r for r in selected}
        for q in fetched:
            m = meta.get(str(q.get("symbolToken")))
            if m:
                q["exchange"] = m.get("exch_seg")
                q["tradingSymbol"] = m.get("symbol") or m.get("name")
                q["indexName"] = m.get("name")
        return result

    def candles(self, exchange, token, interval="FIVE_MINUTE", days=1):
        now = dt.datetime.now(dt.timezone(dt.timedelta(hours=5, minutes=30)))
        start = now - dt.timedelta(days=max(1, min(int(days), 30)))
        api_interval = "ONE_MINUTE" if interval == "TWO_MINUTE" else interval
        p = {"exchange": exchange, "symboltoken": str(token), "interval": api_interval,
             "fromdate": start.strftime("%Y-%m-%d %H:%M"), "todate": now.strftime("%Y-%m-%d %H:%M")}
        result = self._rest_with_retry(lambda api: api.getCandleData(p))
        if interval != "TWO_MINUTE":
            return result
        bucket = {}
        for row in result.get("data") or []:
            if not isinstance(row, list) or len(row) < 6:
                continue
            try:
                t = dt.datetime.fromisoformat(str(row[0]))
                key = t.replace(minute=(t.minute // 2) * 2, second=0, microsecond=0).isoformat()
            except Exception:
                key = str(row[0])[:16]
            if key not in bucket:
                bucket[key] = [key, row[1], row[2], row[3], row[4], row[5]]
            else:
                b = bucket[key]
                b[2] = max(b[2], row[2])
                b[3] = min(b[3], row[3])
                b[4] = row[4]
                b[5] = (b[5] or 0) + (row[5] or 0)
        return {"status": True, "message": "SUCCESS", "data": [bucket[k] for k in sorted(bucket)]}

    def oi_history(self, token, interval="THREE_MINUTE", hours=6):
        now = dt.datetime.now(dt.timezone(dt.timedelta(hours=5, minutes=30)))
        start = now - dt.timedelta(hours=max(1, min(int(hours), 24)))
        p = {"exchange": "NFO", "symboltoken": str(token), "interval": interval,
             "fromdate": start.strftime("%Y-%m-%d %H:%M"), "todate": now.strftime("%Y-%m-%d %H:%M")}
        return self._rest_with_retry(lambda api: api.getOIData(p))

    def option_greeks(self, name, expiry):
        return self._rest_with_retry(lambda api: api._postRequest("api.optionGreek", {"name": name, "expirydate": expiry}))

    def gainers_losers(self, datatype="PercPriceGainers", expirytype="NEAR"):
        return self._rest_with_retry(lambda api: api._postRequest("api.gainersLosers", {"datatype": datatype, "expirytype": expirytype}))

    def oi_buildup(self, datatype="Long Built Up", expirytype="NEAR"):
        return self._rest_with_retry(lambda api: api._postRequest("api.oIBuildup", {"datatype": datatype, "expirytype": expirytype}))

    def put_call_ratio(self, expirytype="NEAR"):
        return self._rest_with_retry(lambda api: api._postRequest("api.putCallRatio", {"expirytype": expirytype}))

    def search(self, exchange, query):
        return self._rest_with_retry(lambda api: api.searchScrip(exchange, query))

    def portfolio(self):
        api = self.require_api()
        # Read-only endpoints only; no order placement/cancellation is exposed.
        return {"holdings": api.holding(), "positions": api.position(), "orders": api.orderBook(), "trades": api.tradeBook()}

    def commodity_quotes(self):
        master = self._master()
        wanted = ("CRUDEOIL", "NATURALGAS", "GOLD", "SILVER", "COPPER", "ALUMINIUM", "ZINC", "LEAD")
        today = dt.date.today()
        selected = []
        for name in wanted:
            candidates = []
            for r in master:
                if r.get("exch_seg") != "MCX" or not r.get("name", "").upper().startswith(name):
                    continue
                exp = r.get("expiry", "")
                if exp:
                    try:
                        ed = dt.datetime.strptime(exp, "%d%b%Y").date()
                        if ed >= today:
                            candidates.append((ed, r))
                    except Exception:
                        pass
            if candidates:
                candidates.sort(key=lambda x: x[0])
                selected.append(candidates[0][1])
        tokens = [str(r["token"]) for r in selected]
        if not tokens:
            return {"data": {"fetched": [], "unfetched": []}, "instruments": selected}
        result = self._rest_with_retry(lambda api: api.getMarketData("FULL", {"MCX": tokens}))
        by = {str(r["symbolToken"]): r for r in result.get("data", {}).get("fetched", [])}
        rows = []
        for r in selected:
            q = by.get(str(r["token"]))
            if q:
                rows.append({"name": r.get("name"), "tradingSymbol": r.get("symbol"), "token": str(r["token"]),
                             "expiry": r.get("expiry"), "ltp": q.get("ltp"), "open": q.get("open"),
                             "high": q.get("high"), "low": q.get("low"), "close": q.get("close"),
                             "volume": q.get("tradeVolume"), "oi": q.get("opnInterest")})
        return {"data": {"fetched": rows, "unfetched": []}, "instruments": selected}

    def option_chain_rows(self, symbol=None, around=None, count=10):
        self.require_api()
        symbol = (symbol or C.SYMBOL).upper()
        exchange = "BFO" if symbol in ("SENSEX", "BANKEX") else "NFO"
        master = self._master()
        aliases = {
            "NIFTY": {"NIFTY", "NIFTY 50"},
            "BANKNIFTY": {"BANKNIFTY", "NIFTY BANK"},
            "FINNIFTY": {"FINNIFTY", "NIFTY FIN SERVICE"},
            "MIDCPNIFTY": {"MIDCPNIFTY", "NIFTY MIDCAP SELECT", "MIDCAP SELECT"},
            "SENSEX": {"SENSEX", "BSE SENSEX"},
            "BANKEX": {"BANKEX", "BSE BANKEX"},
        }
        names = aliases.get(symbol, {symbol})
        rows = [r for r in master if str(r.get("name", "")).upper() in {n.upper() for n in names}
                and str(r.get("exch_seg", "")).upper() == exchange and r.get("instrumenttype") == "OPTIDX"]
        def exp(r): return dt.datetime.strptime(r["expiry"], "%d%b%Y").date()
        today = dt.date.today()
        expiries = sorted({exp(r) for r in rows if r.get("expiry") and exp(r) >= today})
        if not expiries:
            raise RuntimeError(f"No active {symbol} option expiry found.")
        expiry = expiries[0]
        chain = {}
        for r in rows:
            if exp(r) != expiry:
                continue
            try:
                strike = float(r["strike"]) / 100
            except Exception:
                continue
            typ = str(r.get("symbol", ""))[-2:]
            if typ in ("CE", "PE"):
                chain[(strike, typ)] = {"token": str(r["token"]), "symbol": r["symbol"]}
        strikes = sorted({k[0] for k in chain})
        index_rows = [r for r in master if str(r.get("name", "")).upper() in {n.upper() for n in names}
                      and str(r.get("exch_seg", "")).upper() in ("NSE", "BSE")]
        if not index_rows:
            raise RuntimeError(f"No live index token found for {symbol}.")
        idx = index_rows[0]
        q = self._rest_with_retry(lambda api: api.getMarketData("LTP", {str(idx["exch_seg"]): [str(idx["token"])]}))
        fetched = (q.get("data") or {}).get("fetched") or []
        if not fetched:
            raise RuntimeError(f"No spot quote returned for {symbol}.")
        spot = float(fetched[0]["ltp"])
        atm = around if around is not None else min(strikes, key=lambda s: abs(s - spot))
        idx_atm = min(range(len(strikes)), key=lambda i: abs(strikes[i] - atm))
        selected = strikes[max(0, idx_atm - int(count)):idx_atm + int(count) + 1]
        token_map = {}
        for s in selected:
            for typ in ("CE", "PE"):
                item = chain.get((s, typ))
                if item:
                    token_map[item["token"]] = (s, typ, item["symbol"])
        rows_out = []
        toks = list(token_map)
        for j in range(0, len(toks), 50):
            rr = self._rest_with_retry(lambda api, part=toks[j:j + 50]: api.getMarketData("FULL", {exchange: part}))
            for q in rr.get("data", {}).get("fetched", []):
                item = token_map.get(str(q.get("symbolToken")))
                if not item:
                    continue
                s, typ, sym = item
                row = {"strike": s, "type": typ, "symbol": sym, "token": str(q.get("symbolToken")),
                       "ltp": q.get("ltp"), "open": q.get("open"), "high": q.get("high"),
                       "low": q.get("low"), "close": q.get("close"), "oi": q.get("opnInterest"),
                       "volume": q.get("tradeVolume"), "buyQty": q.get("totalBuyQuantity"),
                       "sellQty": q.get("totalSellQuantity")}
                try:
                    cur = float(q.get("opnInterest", 0))
                    prev = self.prev_oi.get(str(q.get("symbolToken")))
                    row["oiChange"] = None if prev is None else cur - prev
                    self.prev_oi[str(q.get("symbolToken"))] = cur
                except Exception:
                    pass
                rows_out.append(row)
        return {"symbol": symbol, "spot": spot, "atm": atm, "expiry": str(expiry), "rows": rows_out}

    def snapshot(self):
        self.ensure_session()
        spot = self.spot()
        if not self.strikes:
            self.build_chain()
        atm = min(self.strikes, key=lambda s: abs(s - spot))
        i = self.strikes.index(atm)
        sel = self.strikes[max(0, i - C.N):i + C.N + 1]
        tok2key = {}
        for s in sel:
            for typ in ("CE", "PE"):
                if (s, typ) in self.chain:
                    tok2key[self.chain[(s, typ)]["token"]] = (s, typ)
        opts = {}
        # Prefer the WebSocket cache; REST is only the snapshot fallback.
        for token, key in tok2key.items():
            tick = self.live_ticks.get(str(token))
            if tick and tick.get("ltp") is not None:
                opts[key] = {"ltp": tick["ltp"], "oi": float(tick.get("oi") or 0), "vol": 0}
        missing = [t for t in tok2key if t not in self.live_ticks]
        for j in range(0, len(missing), 50):
            part = missing[j:j + 50]
            r = self._rest_with_retry(lambda api, p=part: api.getMarketData("FULL", {"NFO": p}))
            for q in r.get("data", {}).get("fetched", []):
                key = tok2key.get(str(q.get("symbolToken")))
                if key:
                    opts[key] = {"ltp": float(q.get("ltp", 0)), "oi": float(q.get("opnInterest", 0)), "vol": float(q.get("tradeVolume", 0))}
        return {"ts": time.time(), "spot": spot, "atm": atm, "opts": opts}
