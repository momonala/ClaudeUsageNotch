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
    "Stop": "idle",
}


def _status_for_notification(payload):
    """Claude Code's Notification hook fires for two unrelated situations: a
    tool genuinely needs the user's permission, or Claude has simply been
    idle for a while waiting on the user (a routine nudge, not a request).
    Only the former should read as `needsInput` — the idle nudge should look
    like nothing's wrong, since nothing is.
    """
    message = str(payload.get("message", "")).lower()
    return "needsInput" if "permission" in message else "idle"


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
    known_events = set(STATUS_BY_EVENT) | {"Notification", "SessionEnd"}
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
                status = (
                    _status_for_notification(payload)
                    if event == "Notification"
                    else STATUS_BY_EVENT[event]
                )
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
