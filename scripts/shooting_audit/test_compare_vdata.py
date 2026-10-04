"""Fixtures for the fresh-data audit parser, without requiring Valve assets."""
import unittest
from compare_vdata import compare, normalize, parse, resolve


class VDataChecks(unittest.TestCase):
    def test_inheritance_and_nested_fields(self):
        entries = parse('\tbase =\n\t\tm_flSpread = [ 0.002, 0.015 ]\n'
                        '\t\tm_nRecoilSeed = 3\n'
                        '\tgun =\n\t\t_base = "base"\n\t\tm_nRecoilSeed = 7\n'
                        '\t\t\tnested = 99\n')
        self.assertEqual(resolve(entries, "gun")["m_flSpread"], "[ 0.002, 0.015 ]")
        self.assertEqual(resolve(entries, "gun")["m_nRecoilSeed"], "7")
        self.assertNotIn("nested", resolve(entries, "gun"))

    def test_cycle_rejected(self):
        with self.assertRaises(ValueError):
            resolve({"a": {"_base": "b"}, "b": {"_base": "a"}}, "a")

    def test_quote_and_array_normalization(self):
        self.assertEqual(normalize('"WeaponSilencerType_Detachable"'),
                         "WeaponSilencerType_Detachable")
        self.assertEqual(normalize("[ 0.002, 0.015 ]"), "0.002|0.015")

    def test_reports_changes_additions_and_missing_fields(self):
        entries = {"gun": {"m_flSpread": "0.2", "m_nRecoilSeed": "7"}}
        _, report = compare(entries, {"gun": {"m_flSpread": "0.1", "m_flDamage": "10"}})
        self.assertEqual(report["compared_fields"], 1)
        self.assertEqual(report["changed"][0]["current"], "0.2")
        self.assertEqual(report["newly_present"][0]["field"], "m_nRecoilSeed")
        self.assertEqual(report["missing_from_scalar_decode"][0]["field"], "m_flDamage")


if __name__ == "__main__":
    unittest.main()
