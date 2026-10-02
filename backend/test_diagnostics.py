import unittest
from diagnostics import build_audit, build_diagnostics, freshness, strategy_health


class DiagnosticsTests(unittest.TestCase):
    def test_freshness_states(self):
        self.assertEqual(freshness(None)["state"], "no-data")
        self.assertEqual(freshness(1000, 1010)["state"], "fresh")
        self.assertEqual(freshness(1000, 1100)["state"], "stale")
        self.assertEqual(freshness(1000, 1201)["state"], "expired")

    def test_strategy_health_does_not_invent_evaluations(self):
        evidence = [
            {"id": 1, "state": "active"},
            {"id": 2, "state": "unavailable"},
            {"id": 3, "state": "inactive"},
        ]
        result = strategy_health(evidence, 426)
        self.assertEqual(result["registered"], 426)
        self.assertEqual(result["evaluated"], 3)
        self.assertEqual(result["not_evaluated"], 423)

    def test_diagnostics_and_audit_are_read_only(self):
        class Engine:
            last = {"action": "WAIT", "reasons": ["test"], "ts": 100}
            strategy_evidence = [{"id": 1, "family": "x", "name": "y", "state": "active"}]

        state = {
            "last_update": 100,
            "error": None,
            "nse_error": None,
            "nse_mcp_error": None,
            "market_open": True,
        }
        d = build_diagnostics(
            state=state,
            engine=Engine(),
            registry_count=426,
            angel_connected=True,
            nse_mcp_connected=True,
            ai_providers=[],
        )
        self.assertTrue(d["ok"])
        self.assertEqual(d["signal"]["action"], "WAIT")
        self.assertEqual(d["strategies"]["active"], 1)

        a = build_audit(Engine(), 426)
        self.assertEqual(a["action"], "WAIT")
        self.assertEqual(a["active_count"], 1)
        self.assertEqual(a["strategy_registry_count"], 426)


if __name__ == "__main__":
    unittest.main()
