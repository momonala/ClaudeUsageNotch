#!/usr/bin/env python3
"""Tests for hook.py's status classification.

Stdlib only and run under bare `python3`, matching how Claude Code invokes
the hook itself:

    python3 -m unittest discover -s agent-status-hook
"""
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "hook", pathlib.Path(__file__).with_name("hook.py")
)
hook = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hook)


class AsksAQuestion(unittest.TestCase):
    def test_plain_trailing_question(self):
        self.assertTrue(hook._asks_a_question("Want me to commit this?"))

    def test_question_in_the_closing_paragraph(self):
        self.assertTrue(hook._asks_a_question("Fixed the lock race.\n\nCommit it?"))

    def test_question_followed_by_qualifiers(self):
        # The common shape: the ask, then a sentence or two narrowing it. The
        # "?" is nowhere near the final line.
        text = (
            "Blue shows up, so rendering is fine.\n\n"
            "So — has the amber ring ever fired on this machine? Specifically "
            "after a turn that ends on a question. If not, it's the trigger "
            "logic and I'll look at the Stop payload next."
        )
        self.assertTrue(hook._asks_a_question(text))

    def test_statement_is_not_a_question(self):
        self.assertFalse(hook._asks_a_question("Done — tests pass."))

    def test_rhetorical_question_earlier_in_the_answer(self):
        # Would otherwise leave the notch amber after nearly every turn.
        text = (
            "Why did it race? The lock swapped inodes on every atomic replace.\n\n"
            "Moved the lock onto its own file. Tests pass."
        )
        self.assertFalse(hook._asks_a_question(text))

    def test_empty_text(self):
        self.assertFalse(hook._asks_a_question(""))


class StatusForStop(unittest.TestCase):
    def test_trailing_question_needs_input(self):
        payload = {"last_assistant_message": "Ready. Want me to push?"}
        self.assertEqual(hook._status_for_stop(payload), "needsInput")

    def test_explicit_marker_needs_input(self):
        payload = {"last_assistant_message": "VPN is down. [NEEDS-ACTION]"}
        self.assertEqual(hook._status_for_stop(payload), "needsInput")

    def test_plain_completion_is_idle(self):
        payload = {"last_assistant_message": "Build succeeded."}
        self.assertEqual(hook._status_for_stop(payload), "idle")

    def test_absent_message_is_idle(self):
        # `last_assistant_message` is optional in the hook schema.
        self.assertEqual(hook._status_for_stop({}), "idle")
        self.assertEqual(hook._status_for_stop({"last_assistant_message": None}), "idle")


class StatusForNotification(unittest.TestCase):
    def test_permission_prompt_needs_input(self):
        payload = {"notification_type": "permission_prompt"}
        self.assertEqual(hook._status_for_notification(payload, "working"), "needsInput")

    def test_subagent_needs_input(self):
        payload = {"notification_type": "agent_needs_input"}
        self.assertEqual(hook._status_for_notification(payload, "working"), "needsInput")

    def test_idle_nudge_alone_is_idle(self):
        payload = {"notification_type": "idle_prompt"}
        self.assertEqual(hook._status_for_notification(payload, "working"), "idle")

    def test_idle_nudge_preserves_an_existing_needs_input(self):
        payload = {"notification_type": "idle_prompt"}
        self.assertEqual(
            hook._status_for_notification(payload, "needsInput"), "needsInput"
        )


if __name__ == "__main__":
    unittest.main()
