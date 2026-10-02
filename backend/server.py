"""Network/API gateway for NSE Algo Signal live market workspace."""
import threading,time,datetime as dt
from typing import Optional
from fastapi import FastAPI,Header,HTTPException,Response
from pydantic import BaseModel
import uvicorn
import config as C
from angel_client import AngelClient
from signals import Engine
from nse_client import NSEClient
import nse_features
from strategy_registry import ALL_STRATEGIES
from nse_mcp import NSEMCP,result_to_csv
from ai_orchestrator import provider_status, validate_all
from diagnostics import build_audit, build_diagnostics

app=FastAPI(title="NSE Algo Signal API"); eng=Engine(); client=AngelClient(); nse=NSEClient(); nse_mcp=NSEMCP()
state={"error":None,"nse_error":None,"last_update":None,"angel_message":"Not connected","nse_mcp_error":None}
prev_chain={"c":None}; workers_started=False

class AIValidationRequest(BaseModel):
    payload:dict = {}

class AngelLoginRequest(BaseModel):
    clientId:str
    pin:str
    totp:str
    apiKey:Optional[str]=None


class LegacyAngelLoginRequest(BaseModel):
    clientId:Optional[str]=None
    client_id:Optional[str]=None
    clientCode:Optional[str]=None
    clientcode:Optional[str]=None
    pin:Optional[str]=None
    password:Optional[str]=None
    totp:Optional[str]=None
    apiKey:Optional[str]=None
    api_key:Optional[str]=None


def _legacy_value(body: LegacyAngelLoginRequest, *names: str) -> str:
    for name in names:
        value = getattr(body, name, None)
        if value:
            return str(value).strip()
    return ""

def market_open():
    now=dt.datetime.now(dt.timezone(dt.timedelta(hours=5,minutes=30)))
    return now.weekday()<5 and dt.time(9,15)<=now.time()<=dt.time(15,30)

@app.on_event("startup")
def start_workers():
    global workers_started
    if workers_started:
        return
    workers_started = True
    threading.Thread(target=loop, daemon=True, name="angel-data-loop").start()
    threading.Thread(target=nse_loop, daemon=True, name="nse-data-loop").start()

def _ensure_angel():
    # Manual APK login is the normal path; do not repeatedly call Angel when
    # no server credentials are configured.
    if client.api is None:
        if not (C.API_KEY and C.CLIENT and C.PIN):
            return
        client.login()
        state["angel_message"]="Connected using server credentials."
    else:
        client.ensure_session()

def loop():
    while True:
        try:
            _ensure_angel()
            if client.api is not None and market_open():
                eng.update(client.snapshot())
                state["last_update"]=time.time()
                state["error"]=None
                state["angel_message"]="Angel One connected."
        except Exception as e:
            state["error"]=str(e)[:500]
            state["angel_message"]="Angel connection failed: " + str(e)[:180]
            client.api=None
        time.sleep(C.POLL_SEC)

def nse_loop():
    while True:
        try:
            if market_open():
                ch=nse.fetch(C.SYMBOL); features=nse_features.compute(ch,prev_chain["c"]); prev_chain["c"]=ch
                eng.set_nse(features,ch["ts"]); state["nse_error"]=None
        except Exception as e: state["nse_error"]=str(e)
        time.sleep(C.NSE_POLL_SEC)

def auth(x_token:str):
    if x_token!=C.API_TOKEN: raise HTTPException(401,"bad token")

@app.get("/health")
def health():
    return {"ok":True,"market_open":market_open(),"angel_connected":client.api is not None,
            "angel_websocket":client.live_connected,"angel_last_tick":client.live_last_tick,
            "angel_message":state["angel_message"],"nse_mcp":"configured",
            "last_update":state["last_update"],"error":state["error"],
            "nse_error":state["nse_error"],"nse_mcp_error":state["nse_mcp_error"]}



@app.post("/api/live/angel/login")
def legacy_angel_login(body:LegacyAngelLoginRequest,x_token:str=Header(None)):
    """Backward-compatible login route for older Vandana2 APK builds.

    It deliberately does not read or require TERMINAL_API_KEY. Credentials are
    forwarded only to the same server-side SmartAPI login used by /v1/angel/login.
    """
    auth(x_token)
    client_id=_legacy_value(body,"clientId","client_id","clientCode","clientcode")
    pin=_legacy_value(body,"pin","password")
    totp=_legacy_value(body,"totp")
    api_key=_legacy_value(body,"apiKey","api_key")
    if not client_id or not pin or not api_key or len(totp)!=6 or not totp.isdigit():
        raise HTTPException(400,"Client ID, PIN, SmartAPI API key and current 6-digit TOTP are required.")
    try:
        result=client.login(api_key=api_key,client_code=client_id,pin=pin,totp=totp)
        state["angel_message"]="Angel One connected."; state["error"]=None
        return {"ok":True,"connected":True,"message":"Angel One connected.","profile":result.get("data",{}).get("clientcode")}
    except Exception as e:
        client.api=None
        state["angel_message"]="Angel connection failed: " + str(e)[:180]
        state["error"]=str(e)[:500]
        raise HTTPException(401,detail=state["error"])

@app.post("/v1/angel/login")
def angel_login(body:AngelLoginRequest,x_token:str=Header(None)):
    auth(x_token)
    if len(body.totp)!=6 or not body.totp.isdigit(): raise HTTPException(400,"TOTP must be the current 6-digit code.")
    try:
        result=client.login(api_key=body.apiKey or C.API_KEY,client_code=body.clientId,pin=body.pin,totp=body.totp)
        state["angel_message"]="Angel One connected."; state["error"]=None
        return {"ok":True,"connected":True,"message":"Angel One connected.","profile":result.get("data",{}).get("clientcode")}
    except Exception as e:
        client.api=None
        state["angel_message"]="Angel connection failed: " + str(e)[:180]
        state["error"]=str(e)[:500]
        raise HTTPException(401,detail=state["error"])

@app.get("/v1/angel/status")
def angel_status(x_token:str=Header(None)):
    auth(x_token)
    return {"connected":client.api is not None,"websocket":client.live_connected,
            "last_tick":client.live_last_tick,"message":state["angel_message"],
            "last_update":state["last_update"],"error":state["error"] or client.last_error}

@app.get("/v1/angel/live")
def angel_live(x_token:str=Header(None)):
    auth(x_token)
    return {"connected":client.api is not None,"websocket":client.live_connected,
            "last_tick":client.live_last_tick,"error":client.live_error,
            "ticks":list(client.live_ticks.values())[-200:]}


def angel_required():
    if client.api is None:
        raise HTTPException(503,"Angel One is not connected. Connect from Angel API screen first.")

@app.get("/v1/angel/commodities")
def angel_commodities(x_token:str=Header(None)):
    auth(x_token); angel_required()
    try: return client.commodity_quotes()
    except Exception as e: raise HTTPException(502,str(e))

@app.get("/v1/angel/market")
def angel_market(x_token:str=Header(None)):
    auth(x_token); angel_required()
    try:
        return client.index_quote()
    except Exception as e:
        raise HTTPException(502,str(e))

@app.get("/v1/angel/candles")
def angel_candles(exchange:str="NSE",token:str="99926000",interval:str="FIVE_MINUTE",days:int=1,x_token:str=Header(None)):
    auth(x_token); angel_required()
    allowed={"ONE_MINUTE","TWO_MINUTE","THREE_MINUTE","FIVE_MINUTE","TEN_MINUTE","FIFTEEN_MINUTE","THIRTY_MINUTE","ONE_HOUR","ONE_DAY"}
    if interval not in allowed: raise HTTPException(400,"Unsupported interval")
    try: return client.candles(exchange,token,interval,days)
    except Exception as e: raise HTTPException(502,str(e))

@app.get("/v1/option-chain")
def unified_option_chain(symbol:str="NIFTY",count:int=10,x_token:str=Header(None)):
    auth(x_token); angel_required()
    symbol=symbol.upper().replace(" ","")
    aliases={"MIDCAPSELECT":"MIDCPNIFTY","BANKNIFTY":"BANKNIFTY"}
    symbol=aliases.get(symbol,symbol)
    try:
        result=client.option_chain_rows(symbol=symbol,count=max(5,min(count,25)))
        rows=result.get("rows",[]) if isinstance(result,dict) else []
        if rows:
            return {**result,"source":"Angel One SmartAPI"}
    except Exception as angel_error:
        if symbol in {"SENSEX","BANKEX"}:
            raise HTTPException(502,str(angel_error))
        try:
            nse_symbol={"MIDCPNIFTY":"MIDCPNIFTY"}.get(symbol,symbol)
            n=nse.fetch(nse_symbol)
            flat=[]
            for item in n.get("rows",[]):
                for typ,key in (("CE","ce"),("PE","pe")):
                    leg=item.get(key) or {}
                    flat.append({
                        "strike":item.get("strike"),"type":typ,
                        "symbol":leg.get("symbol"),
                        "token":leg.get("symbolToken"),
                        "ltp":leg.get("ltp"),"open":leg.get("open"),
                        "high":leg.get("high"),"low":leg.get("low"),
                        "close":leg.get("close"),"oi":leg.get("oi"),
                        "oiChange":leg.get("chg_oi"),"volume":leg.get("vol"),
                    })
            if flat:
                return {"symbol":symbol,"spot":n.get("spot"),"atm":min((x["strike"] for x in flat),key=lambda x:abs(x-float(n.get("spot",x)))),"expiry":n.get("expiry"),"rows":flat,"source":"NSE"}
        except Exception as nse_error:
            raise HTTPException(502,f"Option chain unavailable: Angel={angel_error}; NSE={nse_error}")
        raise HTTPException(502,str(angel_error))


@app.get("/v1/angel/option-chain")
def angel_option_chain(symbol:str="NIFTY",count:int=200,x_token:str=Header(None)):
    auth(x_token); angel_required()
    allowed={"NIFTY","BANKNIFTY","FINNIFTY","MIDCPNIFTY","MIDCAPSELECT","SENSEX","BANKEX"}
    symbol=symbol.upper().replace(" ","")
    if symbol=="MIDCAPSELECT": symbol="MIDCPNIFTY"
    if symbol not in allowed: raise HTTPException(400,"Unsupported index")
    try: return client.option_chain_rows(symbol=symbol,count=max(10,min(count,250)))
    except Exception as e: raise HTTPException(502,str(e))

@app.get("/v1/index-components")
def index_components(index:str="NIFTY",x_token:str=Header(None)):
    auth(x_token)
    allowed={"NIFTY","NIFTY 50","BANKNIFTY","BANK NIFTY","FINNIFTY","MIDCPNIFTY"}
    if index.upper() not in allowed: raise HTTPException(400,"Unsupported index")
    try:
        return nse.index_components(index)
    except Exception as e:
        raise HTTPException(502,"Index constituents unavailable: "+str(e))


@app.get("/v1/angel/oi")
def angel_oi(token:str,interval:str="THREE_MINUTE",hours:int=6,x_token:str=Header(None)):
    auth(x_token); angel_required()
    try: return client.oi_history(token,interval,hours)
    except Exception as e: raise HTTPException(502,str(e))

@app.get("/v1/angel/search")
def angel_search(exchange:str="NSE",q:str="",x_token:str=Header(None)):
    auth(x_token); angel_required()
    if not q.strip(): raise HTTPException(400,"Search query is required")
    try: return client.search(exchange,q.strip())
    except Exception as e: raise HTTPException(502,str(e))

@app.get("/v1/angel/portfolio")
def angel_portfolio(x_token:str=Header(None)):
    auth(x_token); angel_required()
    try: return client.portfolio()
    except Exception as e: raise HTTPException(502,str(e))

@app.get("/v1/angel/gainers-losers")
def angel_gainers_losers(datatype:str="PercPriceGainers",expirytype:str="NEAR",x_token:str=Header(None)):
    auth(x_token); angel_required()
    try: return client.gainers_losers(datatype,expirytype)
    except Exception as e: raise HTTPException(502,str(e))

@app.get("/v1/angel/oi-buildup")
def angel_oi_buildup(datatype:str="Long Built Up",expirytype:str="NEAR",x_token:str=Header(None)):
    auth(x_token); angel_required()
    try: return client.oi_buildup(datatype,expirytype)
    except Exception as e: raise HTTPException(502,str(e))

@app.get("/v1/angel/greeks")
def angel_greeks(name:str="NIFTY",expiry:str="",x_token:str=Header(None)):
    auth(x_token); angel_required()
    if not expiry: raise HTTPException(400,"Expiry is required")
    try: return client.option_greeks(name,expiry)
    except Exception as e: raise HTTPException(502,str(e))

@app.get("/v1/nse/mcp/tools")
def nse_mcp_tools(x_token:str=Header(None)):
    auth(x_token)
    try:
        tools=nse_mcp.tools()
        state["nse_mcp_error"]=None
        return {"connected":True,"endpoint":nse_mcp.url,"tools":[{"name":t.get("name"),"description":t.get("description")} for t in tools]}
    except Exception as e:
        state["nse_mcp_error"]=str(e)
        raise HTTPException(502,"NSE MCP unavailable")

@app.get("/v1/nse/option-chain.csv")
def nse_option_chain_csv(symbol:str="NIFTY",expiry:Optional[str]=None,x_token:str=Header(None)):
    auth(x_token)
    try:
        tool,result=nse_mcp.option_chain(symbol.upper(),expiry)
        state["nse_mcp_error"]=None
        csv=result_to_csv(result)
        return Response(
            content=csv,
            media_type="text/csv",
            headers={"Content-Disposition":f'attachment; filename="{symbol.upper()}_NSE_option_chain.csv"',"X-NSE-MCP-Tool":tool}
        )
    except Exception as e:
        state["nse_mcp_error"]=str(e)
        raise HTTPException(502,str(e))

@app.get("/v1/ai/status")
def ai_status(x_token:str=Header(None)):
    auth(x_token)
    return {"providers":provider_status(),"configured":sum(1 for x in provider_status() if x["configured"])}

@app.post("/v1/ai/validate")
def ai_validate(body:AIValidationRequest,x_token:str=Header(None)):
    auth(x_token)
    payload=dict(body.payload or {})
    try:
        snap=terminal_snapshot()
    except Exception:
        snap={}
    if not payload:
        payload=snap
    payload["engine_decision"]=snap.get("signals",{}) if isinstance(snap,dict) else {}
    payload["strategy_evidence"]=getattr(eng,"strategy_evidence",[])[:120]
    try:
        return validate_all(payload)
    except Exception as e:
        providers=provider_status()
        for p in providers:
            p["status"]="unavailable"
            p["error"]="AI validation service unavailable: "+str(e)[:180]
        return {"final":"NO QUALIFYING TRADE","providers":providers,"configured":0,"total":len(providers),"error":"AI validation service unavailable"}

@app.get("/v1/diagnostics")
def diagnostics(x_token:str=Header(None)):
    auth(x_token)
    snapshot_state = dict(state)
    snapshot_state["market_open"] = market_open()
    return build_diagnostics(
        state=snapshot_state,
        engine=eng,
        registry_count=len(ALL_STRATEGIES),
        angel_connected=client.api is not None,
        nse_mcp_connected=state["nse_mcp_error"] is None,
        ai_providers=provider_status(),
    )


@app.get("/v1/audit/latest")
def latest_audit(x_token:str=Header(None)):
    auth(x_token)
    return build_audit(eng, len(ALL_STRATEGIES))


@app.get("/v1/strategies")
def strategies(x_token:str=Header(None)):
    auth(x_token)
    evidence = eng.strategy_evidence if isinstance(getattr(eng, "strategy_evidence", None), list) else []
    active = sum(1 for x in evidence if x.get("state") == "active")
    unavailable = sum(1 for x in evidence if x.get("state") == "unavailable")
    return {"count": len(ALL_STRATEGIES), "active": active, "inactive": len(ALL_STRATEGIES)-active-unavailable, "unavailable": unavailable, "registry": ALL_STRATEGIES, "evidence": evidence, "health": build_diagnostics(state={**state, "market_open": market_open()}, engine=eng, registry_count=len(ALL_STRATEGIES), angel_connected=client.api is not None, nse_mcp_connected=state["nse_mcp_error"] is None, ai_providers=provider_status())["strategies"]}

@app.get("/signal")
def signal(x_token:str=Header(None)): auth(x_token); return terminal_snapshot()

@app.get("/v1/terminal")
def terminal_snapshot_endpoint(x_token:str=Header(None)): auth(x_token); return terminal_snapshot()

def terminal_snapshot():
    last=eng.last if isinstance(eng.last,dict) else {}; nse_view=eng.nse_view if isinstance(eng.nse_view,dict) else {}
    return {"ts":time.time(),"market_open":market_open(),"connection":{"angel":client.api is not None,"nse":state["nse_error"] is None,"server":True,"last_update":state["last_update"],"error":state["error"],"nse_error":state["nse_error"],"angel_message":state["angel_message"]},"market":{"symbol":C.SYMBOL,"spot":last.get("spot"),"atm":last.get("strike"),"action":last.get("action","WAIT"),"ltp":last.get("ltp")},"signals":last,"oi_lab":nse_view,"option_chain":last.get("chain",last.get("opts")),"charts":{"spot":last.get("spot"),"ltp":last.get("ltp"),"timestamp":state["last_update"],"source":"Angel One SmartAPI","endpoint":"/v1/angel/candles"},"nse":nse_view,"angel_data":{"market_endpoint":"/v1/angel/market","candles_endpoint":"/v1/angel/candles","option_chain_endpoint":"/v1/angel/option-chain","oi_endpoint":"/v1/angel/oi","search_endpoint":"/v1/angel/search","portfolio_endpoint":"/v1/angel/portfolio","gainers_losers_endpoint":"/v1/angel/gainers-losers","oi_buildup_endpoint":"/v1/angel/oi-buildup","greeks_endpoint":"/v1/angel/greeks"},"nse_mcp":{"status":"official NSE Streamable HTTP MCP","endpoint":nse_mcp.url,"connected":state["nse_mcp_error"] is None,"error":state["nse_mcp_error"],"csv_endpoint":"/v1/nse/option-chain.csv"},"angel_api":{"connected":client.api is not None,"message":state["angel_message"]},"data":last,"instruments":{"source":"Angel One SmartAPI instrument master","loaded":bool(client.chain),"expiry":str(client.expiry) if client.expiry else None,"strike_count":len(client.strikes)},"watchlist":{"source":"Angel One SmartAPI","items":[]},"search":{"source":"Angel One SmartAPI","items":[]},"commodity":{"source":"Angel One SmartAPI","items":[]},"market_details":nse_view,"news":{"source":"server-side news adapter","items":[]},"settings":{"symbol":C.SYMBOL,"poll_sec":C.POLL_SEC,"nse_poll_sec":C.NSE_POLL_SEC},"ai":{"providers":provider_status(),"configured":sum(1 for x in provider_status() if x["configured"])},"more":{"paper_only":False,"orders_enabled":False},"error":state["error"],"nse_error":state["nse_error"]}

if __name__=="__main__":
    uvicorn.run(app,host="0.0.0.0",port=8000)
