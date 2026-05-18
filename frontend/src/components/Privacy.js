import React from "react";
import { Check, ShieldCheck } from "lucide-react";

const items = [
  "Cookie stored only in the macOS Keychain. Never UserDefaults, never plain text.",
  "No telemetry. No analytics. No remote server in the loop.",
  "The app talks only to claude.ai (and status.claude.com).",
  "MIT licensed — audit the entire source yourself.",
  "Notifications use system APIs, no background daemons.",
];

export default function Privacy() {
  return (
    <section id="privacy" className="nl-section" data-testid="section-privacy">
      <span className="eyebrow">Privacy</span>
      <h2>Local-first. <span className="accent">Always.</span></h2>
      <div className="nl-privacy">
        <div>
          <p className="lead" style={{ marginBottom: 14 }}>
            Your Claude cookie is sensitive. We treat it like one.
            Everything Notchy Limit does happens on your Mac.
          </p>
          <div style={{ display: "flex", alignItems: "center", gap: 10, color: "var(--cool)" }}>
            <ShieldCheck size={18} />
            <span className="nl-mono" style={{ fontSize: 12 }}>0 bytes leave your machine besides the calls to claude.ai</span>
          </div>
        </div>
        <ul className="nl-privacy-list" data-testid="privacy-list">
          {items.map((t, i) => (
            <li key={i}><Check size={16} /><span>{t}</span></li>
          ))}
        </ul>
      </div>
    </section>
  );
}
