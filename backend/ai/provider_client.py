"""Direct provider transport using an OpenAI-compatible client."""
from __future__ import annotations
from typing import Any, Dict, List, Optional
from loguru import logger
from backend.config import Settings

def _infer_provider(model:str)->str:
    m=model.lower()
    if "claude" in m or m.startswith("anthropic/"): return "anthropic"
    if "deepseek" in m:return "deepseek"
    if "gemini" in m or "google" in m:return "google"
    if "grok" in m or m.startswith("xai/"):return "xai"
    return "openai"

class ProviderClient:
    def __init__(self,settings:Settings)->None:
        self.s=settings
        self._bases={"openai":settings.openai_base_url or "https://api.openai.com/v1","anthropic":"https://api.anthropic.com/v1","deepseek":"https://api.deepseek.com/v1","google":"https://generativelanguage.googleapis.com/v1beta/openai","xai":"https://api.x.ai/v1"}
        self._keys={"openai":settings.openai_api_key,"anthropic":settings.anthropic_api_key,"deepseek":settings.deepseek_api_key,"google":settings.google_api_key,"xai":settings.xai_api_key}
    def available(self)->bool:return any(bool(k) for k in self._keys.values())
    def _client(self,provider:str):
        from openai import AsyncOpenAI
        key=self._keys.get(provider)
        return AsyncOpenAI(api_key=key,base_url=self._bases.get(provider)) if key else None
    async def chat(self,model:str,messages:List[Dict[str,str]],*,tools:Optional[List[dict]]=None,temperature:float=0.1,max_tokens:int=1200)->Optional[Dict[str,Any]]:
        provider=_infer_provider(model); client=self._client(provider)
        if client is None:
            logger.debug("provider {} has no key; skipping",provider); return None
        kwargs={"model":model,"messages":messages,"temperature":temperature,"max_tokens":max_tokens}
        if tools: kwargs["tools"]=tools
        try:
            resp=await client.chat.completions.create(**kwargs)
            return {"provider":provider,"model":model,"content":resp.choices[0].message.content or ""}
        except Exception as e:
            logger.warning("provider chat failed ({}): {}",model,e); return None
