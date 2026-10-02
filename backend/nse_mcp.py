"""Small Streamable-HTTP MCP client for the official NSE MCP endpoint."""
import csv
import io
import json
import requests

NSE_MCP_URL = "https://mcp.nseindia.in/cmmkt/mcp"

class NSEMCP:
    def __init__(self, url=NSE_MCP_URL):
        self.url = url
        self.timeout = 12

    def _post(self, payload, session_id=None):
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if session_id:
            headers["Mcp-Session-Id"] = session_id
        r = requests.post(self.url, json=payload, headers=headers, timeout=self.timeout)
        r.raise_for_status()
        sid = r.headers.get("mcp-session-id") or session_id
        text = r.text.strip()
        if text.startswith("data:"):
            for line in text.splitlines():
                if line.startswith("data:"):
                    try:
                        return json.loads(line[5:].strip()), sid
                    except Exception:
                        continue
        return (r.json() if text else {}), sid

    def tools(self):
        init, sid = self._post({
            "jsonrpc":"2.0","id":1,"method":"initialize",
            "params":{
                "protocolVersion":"2025-06-18",
                "capabilities":{},
                "clientInfo":{"name":"NSE Algo Signal","version":"1.0"}
            }
        })
        self._post({"jsonrpc":"2.0","method":"notifications/initialized","params":{}}, sid)
        result, sid = self._post({"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}, sid)
        return result.get("result", {}).get("tools", [])

    def option_chain(self, symbol="NIFTY", expiry=None):
        tools = self.tools()
        candidates = [t for t in tools if "option" in t.get("name","").lower() and "chain" in t.get("name","").lower()]
        if not candidates:
            raise RuntimeError("Official NSE CM-MCP does not expose an option-chain tool in its current tool list.")
        tool = candidates[0]
        props = tool.get("inputSchema", {}).get("properties", {})
        args = {}
        if "symbol" in props: args["symbol"] = symbol
        elif "index" in props: args["index"] = symbol
        if expiry and "expiry" in props: args["expiry"] = expiry
        _, sid = self._post({
            "jsonrpc":"2.0","id":3,"method":"initialize",
            "params":{
                "protocolVersion":"2025-06-18","capabilities":{},
                "clientInfo":{"name":"NSE Algo Signal","version":"1.0"}
            }
        })
        self._post({"jsonrpc":"2.0","method":"notifications/initialized","params":{}}, sid)
        result, _ = self._post({
            "jsonrpc":"2.0","id":4,"method":"tools/call",
            "params":{"name":tool["name"],"arguments":args}
        }, sid)
        return tool["name"], result

def flatten(obj, prefix=""):
    rows=[]
    if isinstance(obj, dict):
        for k,v in obj.items():
            rows.extend(flatten(v, f"{prefix}.{k}" if prefix else k))
    elif isinstance(obj, list):
        for i,v in enumerate(obj):
            rows.extend(flatten(v, f"{prefix}[{i}]"))
    else:
        rows.append((prefix, obj))
    return rows

def result_to_csv(result):
    content = result.get("result", result) if isinstance(result, dict) else result
    if isinstance(content, dict) and "content" in content:
        blocks=content["content"]
        for b in blocks:
            if isinstance(b,dict) and b.get("type")=="text":
                try: content=json.loads(b.get("text",""))
                except Exception: content=b.get("text","")
                break
    if isinstance(content, list) and all(isinstance(x,dict) for x in content):
        keys=sorted({k for x in content for k in x.keys()})
        out=io.StringIO(); w=csv.DictWriter(out,fieldnames=keys); w.writeheader(); w.writerows(content)
        return out.getvalue()
    if isinstance(content, dict):
        for key in ("records","data","rows","optionChain","option_chain"):
            val=content.get(key)
            if isinstance(val,list) and all(isinstance(x,dict) for x in val):
                keys=sorted({k for x in val for k in x.keys()})
                out=io.StringIO(); w=csv.DictWriter(out,fieldnames=keys); w.writeheader(); w.writerows(val)
                return out.getvalue()
    out=io.StringIO(); w=csv.writer(out); w.writerow(["field","value"]); w.writerows(flatten(content))
    return out.getvalue()
