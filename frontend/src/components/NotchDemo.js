import React, { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { RefreshCw, Key, Bell, Activity } from "lucide-react";

/**
 * Interactive notch demo. Mirrors the real app:
 *  - Compact pill (session % + status dot + tiny bar)
 *  - Hover → auto-expand (180ms intent delay)
 *  - Click → pin (toggle)
 *  - Auto-cycles session pct so the page feels alive.
 */
export default function NotchDemo() {
  const [percent, setPercent] = useState(42);
  const [expanded, setExpanded] = useState(false);
  const [pinned, setPinned] = useState(false);
  const hoverTimer = useRef(null);

  // Slowly drift the session percent so the demo doesn't feel static.
  useEffect(() => {
    const id = setInterval(() => {
      setPercent((p) => {
        // bounce 28..82
        const next = p + (Math.random() < 0.5 ? -2 : 2);
        if (next < 28) return 30;
        if (next > 82) return 80;
        return next;
      });
    }, 1800);
    return () => clearInterval(id);
  }, []);

  const status = percent >= 90 ? "critical" : percent >= 70 ? "warning" : "healthy";
  const weekly = Math.min(99, Math.round(percent * 0.7 + 12));
  const weeklyStatus = weekly >= 90 ? "critical" : weekly >= 70 ? "warning" : "healthy";
  const showPanel = expanded || pinned;

  const handleMouseEnter = () => {
    if (pinned) return;
    if (hoverTimer.current) clearTimeout(hoverTimer.current);
    hoverTimer.current = setTimeout(() => setExpanded(true), 180);
  };
  const handleMouseLeave = () => {
    if (pinned) return;
    if (hoverTimer.current) clearTimeout(hoverTimer.current);
    setExpanded(false);
  };
  const handleClick = () => setPinned((p) => !p);

  return (
    <div data-testid="notch-demo">
      <div className="nl-laptop" aria-label="MacBook notch preview">
        <div className="screen-bezel">
          <div className="wall" />
          <div className="menubar" aria-hidden="true">
            <span> Finder</span>
            <span>File</span>
            <span>Edit</span>
            <span>View</span>
            <span style={{ marginLeft: "auto" }}>14:32</span>
          </div>
          <div className="notch-cutout" aria-hidden="true" />
          <div className="pill-host">
            <AnimatePresence mode="wait" initial={false}>
              {showPanel ? (
                <motion.div
                  key="panel"
                  className="nl-panel"
                  data-testid="notch-panel"
                  initial={{ opacity: 0, y: -10, scale: 0.96 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: -10, scale: 0.97 }}
                  transition={{ type: "spring", stiffness: 280, damping: 26 }}
                  onMouseEnter={handleMouseEnter}
                  onMouseLeave={handleMouseLeave}
                  onClick={(e) => {
                    if (e.target.closest("button")) return;
                    handleClick();
                  }}
                >
                  <div className="panel-head">
                    <div
                      className={`nl-pill-compact`}
                      style={{ padding: "4px 8px", pointerEvents: "none", background: "transparent", border: "none", boxShadow: "none" }}
                    >
                      <span className={`dot nl-dot-${status}`} />
                    </div>
                    <div>
                      <div className="title">Notchy Limit</div>
                      <div className="sub">Updated just now · Claude</div>
                    </div>
                    <button
                      type="button"
                      aria-label={pinned ? "Unpin" : "Pin"}
                      onClick={(e) => { e.stopPropagation(); handleClick(); }}
                      style={{
                        marginLeft: "auto",
                        background: "transparent",
                        border: "1px solid var(--stroke)",
                        color: "var(--text-1)",
                        borderRadius: 8,
                        padding: "3px 8px",
                        fontSize: 10,
                        cursor: "pointer",
                      }}
                      data-testid="pin-toggle"
                    >
                      {pinned ? "Pinned" : "Pin"}
                    </button>
                  </div>

                  <div className="card primary" data-testid="session-card">
                    <div className="row">
                      <span className="label">Session</span>
                      <span className={`value nl-text-${status}`}>{percent}%</span>
                    </div>
                    <div className="bar">
                      <motion.div
                        className={`fill nl-fill-${status}`}
                        animate={{ width: `${percent}%` }}
                        transition={{ duration: 0.6 }}
                        style={{ position: "absolute", inset: 0, width: `${percent}%` }}
                      />
                    </div>
                    <div className="meta">
                      <span>Resets in 1h 12m</span>
                      <span className={`nl-text-${status}`}>
                        {status === "critical" ? "At limit" : status === "warning" ? "Approaching" : "On track"}
                      </span>
                    </div>
                  </div>

                  <div className="card" data-testid="weekly-card">
                    <div className="row">
                      <span className="label" style={{ fontSize: 12 }}>This week</span>
                      <span className={`value nl-text-${weeklyStatus}`} style={{ fontSize: 14 }}>{weekly}%</span>
                    </div>
                    <div className="bar" style={{ height: 4 }}>
                      <motion.div
                        className={`fill nl-fill-${weeklyStatus}`}
                        animate={{ width: `${weekly}%` }}
                        transition={{ duration: 0.6 }}
                        style={{ position: "absolute", inset: 0, width: `${weekly}%` }}
                      />
                    </div>
                    <div className="meta">
                      <span>Resets Mon 00:00</span>
                    </div>
                  </div>

                  <div className="actions-row">
                    <div className="action"><span className="ic"><RefreshCw size={14} /></span>Refresh</div>
                    <div className="action"><span className="ic"><Key size={14} /></span>Cookie</div>
                    <div className="action"><span className="ic"><Bell size={14} /></span>Alerts</div>
                    <div className="action"><span className="ic"><Activity size={14} /></span>Diag</div>
                  </div>
                  <div className="panel-foot">
                    <span>v0.1.0</span>
                    <a href="https://github.com/I-N-SILVA/NOTCHY" target="_blank" rel="noopener noreferrer">GitHub</a>
                  </div>
                </motion.div>
              ) : (
                <motion.div
                  key="compact"
                  className="nl-pill-compact"
                  data-testid="notch-pill"
                  initial={{ opacity: 0, y: -6, scale: 0.96 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: -6, scale: 0.96 }}
                  transition={{ type: "spring", stiffness: 360, damping: 26 }}
                  onMouseEnter={handleMouseEnter}
                  onMouseLeave={handleMouseLeave}
                  onClick={handleClick}
                >
                  <span className={`dot nl-dot-${status}`} />
                  <span className="bar"><span className="fill" style={{ width: `${percent}%`, background: `var(--${status === "critical" ? "red" : status === "warning" ? "amber" : "green"})` }} /></span>
                  <span className="pct">{percent}%</span>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </div>
      </div>
      <div className="nl-laptop-caption">
        <span>Hover the pill to expand. Click to pin. State: <code data-testid="notch-state">{pinned ? "pinned" : expanded ? "hovered" : "compact"}</code></span>
      </div>
    </div>
  );
}
