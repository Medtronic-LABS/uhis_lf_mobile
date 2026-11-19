#!/usr/bin/env python3
"""Unit tests for the promotion plan in play_promote.py. Run: python3 scripts/test_play_promote.py"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from play_promote import PromotionError, plan_promotion  # noqa: E402

NOTES = [{"language": "en-US", "text": "Bug fixes."}]


def track(*releases):
    return {"releases": list(releases)}


def release(code, status="completed", fraction=None):
    built = {"name": "1.1.%s" % code, "versionCodes": [code], "status": status,
             "releaseNotes": NOTES}
    if fraction is not None:
        built["userFraction"] = fraction
    return built


class PlanPromotionTest(unittest.TestCase):
    def test_staged_rollout_carries_name_and_notes_from_internal(self):
        planned = plan_promotion(track(release("17")), track(release("16")), "17", 20)
        self.assertEqual(planned, {"name": "1.1.17", "versionCodes": ["17"], "releaseNotes": NOTES,
                                   "status": "inProgress", "userFraction": 0.2})

    def test_full_rollout_is_completed_without_a_fraction(self):
        planned = plan_promotion(track(release("17")), track(release("16")), "17", 100)
        self.assertEqual(planned["status"], "completed")
        self.assertNotIn("userFraction", planned)

    def test_widening_an_existing_staged_rollout(self):
        target = track(release("17", "inProgress", 0.2), release("16"))
        self.assertEqual(plan_promotion(track(release("17")), target, "17", 50)["userFraction"], 0.5)

    def test_already_fully_rolled_out_needs_nothing(self):
        self.assertIsNone(plan_promotion(track(release("17")), track(release("17")), "17", 100))

    def test_build_missing_from_internal_is_refused(self):
        with self.assertRaisesRegex(PromotionError, "not a completed release"):
            plan_promotion(track(release("16")), track(release("16")), "17", 20)

    def test_draft_on_internal_is_refused(self):
        with self.assertRaisesRegex(PromotionError, "not a completed release"):
            plan_promotion(track(release("17", "draft")), track(release("16")), "17", 20)

    def test_older_than_live_build_is_refused(self):
        with self.assertRaisesRegex(PromotionError, "older than build 16"):
            plan_promotion(track(release("15")), track(release("16")), "15", 20)

    def test_same_or_lower_percentage_is_refused(self):
        target = track(release("17", "inProgress", 0.5), release("16"))
        with self.assertRaisesRegex(PromotionError, "already rolled out to 50%"):
            plan_promotion(track(release("17")), target, "17", 50)

    def test_percentage_out_of_range_is_refused(self):
        with self.assertRaisesRegex(PromotionError, "between 1 and 100"):
            plan_promotion(track(release("17")), track(), "17", 0)


if __name__ == "__main__":
    unittest.main()
