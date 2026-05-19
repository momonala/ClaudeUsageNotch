import React, { useState } from "react";
import { ChevronDown } from "lucide-react";

const items = [
  {
    q: "How do I get my session token?",
    a: (
      <>
        <p style={{ marginBottom: 10, color: "var(--text-2)", fontSize: 12 }}>
          Takes about 30 seconds. No extensions, no scripts — just your browser's built-in DevTools.
        </p>
        <ol>
          <li>Open <code>claude.ai</code> and make sure you're logged in.</li>
          <li>Press <code>⌘+⌥+I</code> to open DevTools, then click the <strong>Network</strong> tab.</li>
          <li>Refresh the page (<code>⌘+R</code>). A list of requests will appear.</li>
          <li>Click the request named <strong>usage</strong> (filter by "usage" if needed).</li>
          <li>Under <strong>Request Headers</strong>, find and copy the full <code>Cookie</code> value.</li>
          <li>Paste it into Notchy's setup screen and hit <strong>Validate</strong>.</li>
        </ol>
        <p style={{ marginTop: 10, fontSize: 12, color: "var(--text-2)" }}>
          Your token is stored in the macOS <strong>Keychain</strong> — never on disk, never logged.{" "}
          <a
            href="https://github.com/I-N-SILVA/NOTCHY/blob/main/swift-project/NotchyLimit/docs/COOKIE_SETUP.md"
            target="_blank"
            rel="noopener noreferrer"
            style={{ color: "var(--cool)" }}
          >
            Full guide with screenshots →
          </a>
        </p>
      </>
    ),
  },
  {
    q: "Where is my cookie stored?",
    a: <p>In the macOS <code>Keychain</code>, scoped to the Notchy Limit bundle id. Never in UserDefaults, never logged. You can wipe it any time from Settings → Providers → Remove.</p>,
  },
  {
    q: "What if Claude changes their response?",
    a: <p>Notchy Limit decodes a small set of fields (<code>five_hour.utilization</code>, <code>seven_day.utilization</code>, <code>resets_at</code>). If the schema changes, you'll see a <strong>Diagnostics</strong> error explaining what failed. We ship patches quickly — watch the GitHub releases.</p>,
  },
  {
    q: "How do I build it?",
    a: (
      <>
        <p>You need macOS 12+, Xcode 15+, and <code>brew install xcodegen</code>. Then:</p>
        <ol>
          <li><code>cd NotchyLimit && xcodegen generate</code></li>
          <li><code>./scripts/build.sh</code></li>
          <li><code>open build/NotchyLimit.app</code></li>
        </ol>
        <p>Full instructions inside the source bundle at <code>docs/BUILDING.md</code>.</p>
      </>
    ),
  },
  {
    q: "Can I add another provider?",
    a: <p>Yes — implement the <code>UsageProvider</code> protocol, return a <code>ServiceUsageSnapshot</code>, register in <code>ProviderRegistry</code>. The notch UI, polling, and notifications all consume the unified domain types, so nothing else changes. See <code>docs/PROVIDER_GUIDE.md</code>.</p>,
  },
];

export default function Setup() {
  const [openIdx, setOpenIdx] = useState(0);
  return (
    <section id="setup" className="nl-section" data-testid="section-setup">
      <span className="eyebrow">Setup</span>
      <h2>30-second setup. <span className="accent">Open-source forever.</span></h2>
      <p className="lead">Everything you need to install, configure, and extend.</p>
      <div className="nl-accordion">
        {items.map((it, i) => {
          const isOpen = openIdx === i;
          return (
            <div key={i} className="nl-acc-item" data-testid={`acc-item-${i}`}>
              <button
                type="button"
                className={`nl-acc-trigger ${isOpen ? "open" : ""}`}
                onClick={() => setOpenIdx(isOpen ? -1 : i)}
                aria-expanded={isOpen}
                data-testid={`acc-trigger-${i}`}
              >
                <span>{it.q}</span>
                <ChevronDown size={16} className="chev" />
              </button>
              {isOpen && (
                <div className="nl-acc-body" data-testid={`acc-body-${i}`}>
                  {it.a}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </section>
  );
}
