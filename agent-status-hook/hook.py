#!/usr/bin/env python3
"""Claude Code hook entry point that feeds ClaudeUsageNotch's status pulse.

Registered in ~/.claude/settings.json for UserPromptSubmit, PreToolUse,
Notification, Stop, and SessionEnd. Each invocation reads the hook JSON
payload from stdin and updates this session's entry in a shared status
file, keyed by session_id, that the notch app polls.

Stdlib only, no third-party dependencies.
"""
import fcntl
import json
import os
import re
import sys
import tempfile
import time

STATUS_DIR = os.path.expanduser("~/Library/Application Support/ClaudeUsageNotch")
STATUS_FILE = os.path.join(STATUS_DIR, "agent-status.json")
# Locking the status file itself doesn't work: an atomic replace swaps in a new
# inode, so a second invocation can end up holding a lock on the orphaned old
# one and clobber the first's update. The lock lives on its own file, which is
# only ever created and locked — never replaced — so all invocations contend
# for the same inode.
LOCK_FILE = os.path.join(STATUS_DIR, "agent-status.lock")

STATUS_BY_EVENT = {
    "UserPromptSubmit": "working",
    "PreToolUse": "working",
}

# `notification_type` values that mean something is blocked on the user, as
# opposed to `idle_prompt` (the 60s "are you still there" nudge, which says
# nothing about whether Claude is waiting on anything).
BLOCKED_NOTIFICATIONS = {
    "permission_prompt",
    "worker_permission_prompt",
    "agent_needs_input",
}

# Optional explicit marker: a global CLAUDE.md can instruct Claude to append
# this when it's blocked on something only the user can do outside the chat
# (e.g. reconnecting a VPN). Honoured when present, but `_asks_a_question`
# below is what carries most turns — the marker depends on an instruction
# that isn't installed on every machine.
NEEDS_ACTION_MARKER = "[NEEDS-ACTION]"


def _status_for_notification(payload, current_status):
    """Classify a Notification by its `notification_type`.

    Claude Code fires this hook for several unrelated situations. Only the
    ones in `BLOCKED_NOTIFICATIONS` mean something is actually waiting on the
    user. `idle_prompt` — the 60s "Claude is waiting for your input" nudge —
    is a heartbeat: it fires repeatedly, so it must not clobber a
    `needsInput` an earlier event already set for the same unresolved ask.
    """
    if payload.get("notification_type") in BLOCKED_NOTIFICATIONS:
        return "needsInput"
    return "needsInput" if current_status == "needsInput" else "idle"


def _asks_a_question(text):
    """True when the turn's closing paragraph puts a question to the user.

    Claude Code fires no Notification for a turn that simply ends on a
    question ("Want me to also update the README?"), yet the session is every
    bit as blocked as it is on a permission prompt.

    Scoped to the last blank-line-separated block rather than the whole
    message or just the final line. The whole message is too broad — any
    rhetorical "why did it race?" mid-answer would leave the notch amber
    after nearly every turn. The final line is too narrow: an ask is usually
    followed by a sentence or two qualifying it, so the "?" lands mid-block.
    """
    blocks = [b for b in re.split(r"\n\s*\n", text.strip()) if b.strip()]
    return "?" in blocks[-1] if blocks else False


def _status_for_stop(payload):
    """`last_assistant_message` is supplied by the Stop payload itself, so
    there's no transcript to open and parse. It's optional in the schema —
    absent means nothing to classify, which reads as plain idle.
    """
    text = str(payload.get("last_assistant_message") or "")
    if NEEDS_ACTION_MARKER in text or _asks_a_question(text):
        return "needsInput"
    return "idle"


def _status_for_event(event, payload, current_status):
    """The status this event puts the session in."""
    if event == "Notification":
        return _status_for_notification(payload, current_status)
    if event == "Stop":
        return _status_for_stop(payload)
    return STATUS_BY_EVENT[event]


def _load():
    try:
        with open(STATUS_FILE) as fh:
            raw = fh.read()
    except FileNotFoundError:
        return {}
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def _write_atomic(data):
    fd, tmp_path = tempfile.mkstemp(dir=STATUS_DIR)
    try:
        with os.fdopen(fd, "w") as tmp:
            json.dump(data, tmp)
        os.replace(tmp_path, STATUS_FILE)
    except OSError:
        os.unlink(tmp_path)
        raise


def main():
    payload = json.load(sys.stdin)
    event = payload.get("hook_event_name")
    session_id = payload.get("session_id")
    known_events = set(STATUS_BY_EVENT) | {"Notification", "Stop", "SessionEnd"}
    if not session_id or event not in known_events:
        return

    os.makedirs(STATUS_DIR, exist_ok=True)
    # Hold an flock on the dedicated lock file across the read-modify-write so
    # concurrent hook invocations from different sessions don't race.
    with open(LOCK_FILE, "a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            data = _load()
            if event == "SessionEnd":
                data.pop(session_id, None)
            else:
                current_status = data.get(session_id, {}).get("status")
                status = _status_for_event(event, payload, current_status)
                data[session_id] = {
                    "status": status,
                    "event": event,
                    "ts": time.time(),
                    "cwd": payload.get("cwd", ""),
                }
            _write_atomic(data)
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


if __name__ == "__main__":
    main()
