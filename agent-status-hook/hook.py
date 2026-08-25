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
}

# Emitted by Claude at the end of a turn (per global CLAUDE.md instruction)
# when it's blocked on something only the user can do outside the chat, e.g.
# reconnecting a VPN — not a tool-permission prompt, so Notification never
# fires for it and Stop would otherwise read as plain idle.
NEEDS_ACTION_MARKER = "[NEEDS-ACTION]"


def _status_for_notification(payload, current_status):
    """Claude Code's Notification hook fires for two unrelated situations: a
    tool genuinely needs the user's permission, or Claude has simply been
    idle for a while waiting on the user (a routine nudge, not a request).
    The former always reads as `needsInput`. The latter is just a heartbeat —
    it must not clobber a `needsInput` a prior `Stop` already set (e.g. from
    the `[NEEDS-ACTION]` marker), since the nudge fires repeatedly while
    Claude is still waiting on that same unresolved ask.
    """
    message = str(payload.get("message", "")).lower()
    if "permission" in message:
        return "needsInput"
    return "needsInput" if current_status == "needsInput" else "idle"


def _last_assistant_text(transcript_path):
    if not transcript_path:
        return ""
    try:
        with open(transcript_path) as fh:
            lines = fh.readlines()
    except OSError:
        return ""
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("type") != "assistant":
            continue
        content = entry.get("message", {}).get("content", [])
        if isinstance(content, str):
            return content
        return "\n".join(
            block.get("text", "")
            for block in content
            if isinstance(block, dict) and block.get("type") == "text"
        )
    return ""


def _status_for_stop(payload):
    text = _last_assistant_text(payload.get("transcript_path"))
    return "needsInput" if NEEDS_ACTION_MARKER in text else "idle"


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
                status = (
                    _status_for_notification(payload, current_status)
                    if event == "Notification"
                    else _status_for_stop(payload)
                    if event == "Stop"
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
