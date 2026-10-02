import unittest
from strategy_registry import STRATEGIES, ALL_STRATEGIES, evaluate_strategies

class MasterStrategyRegistryTests(unittest.TestCase):
    def test_master_registry_contains_all_377_modules(self):
        self.assertEqual(len(STRATEGIES), 377)
        self.assertEqual([s["id"] for s in STRATEGIES], list(range(1, 378)))
        # Names may repeat across strategy families; IDs and family/name pairs must be unique.\n        self.assertEqual(len({s["id"] for s in STRATEGIES}), 377)\n        self.assertEqual(len({(s["family"], s["name"]) for s in STRATEGIES}), 377)
        self.assertEqual(len(ALL_STRATEGIES), 426)
        self.assertEqual([s["id"] for s in ALL_STRATEGIES], list(range(1, 427)))

    def test_core_option_classification_is_evaluable(self):
        rows = [{
            "strike": 25000,
            "ce": {"ltp": 120, "prev_ltp": 100, "oi": 100000, "prev_oi": 80000, "vol": 50000},
            "pe": {"ltp": 80, "prev_ltp": 90, "oi": 120000, "prev_oi": 110000, "vol": 45000},
        }]
        result = evaluate_strategies({"spot": 25000, "rows": rows, "timestamp": 1})
        by_name = {x["name"]: x for x in result}
        self.assertEqual(by_name["Long Buildup"]["state"], "active")
        self.assertEqual(by_name["Short Buildup"]["state"], "active")
        self.assertEqual(by_name["Fresh OI Addition"]["state"], "active")

    def test_missing_data_never_creates_fake_signal(self):
        result = evaluate_strategies({"spot": 25000, "rows": [], "timestamp": 1})
        self.assertTrue(all(x["state"] in {"unavailable", "inactive"} for x in result))

if __name__ == "__main__":
    unittest.main()
