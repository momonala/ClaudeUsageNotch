import React, { useState } from "react";
import { motion } from "framer-motion";
import { Github } from "lucide-react";
import { joinWaitlist } from "@/lib/api";

function GeminiWaitlist() {
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState(null);

  const submit = async (e) => {
    e.preventDefault();
    if (!email || !email.includes("@")) {
      setMsg({ ok: false, text: "Enter a valid email." });
      return;
    }
    setBusy(true);
    setMsg(null);
    try {
      const res = await joinWaitlist(email, "gemini");
      setMsg({
        ok: true,
        text: res.deduped ? "Already on the list — we'll ping you." : "You're on the list.",
      });
      setEmail("");
    } catch {
      setMsg({ ok: false, text: "Couldn't add you. Try again later." });
    } finally {
      setBusy(false);
    }
  };

  return (
    <form className="nl-waitlist" onSubmit={submit} data-testid="waitlist-form-gemini">
      <input
        type="email"
        placeholder="you@domain.com"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        disabled={busy}
        aria-label="Email for Gemini waitlist"
        data-testid="waitlist-email-gemini"
      />
      <button type="submit" disabled={busy} data-testid="waitlist-submit-gemini">
        {busy ? "Joining…" : "Notify me"}
      </button>
      {msg && (
        <div
          className={`nl-waitlist-msg ${msg.ok ? "ok" : "err"}`}
          style={{ gridColumn: "1 / -1" }}
          data-testid="waitlist-msg-gemini"
        >
          {msg.text}
        </div>
      )}
    </form>
  );
}

export default function Providers() {
  return (
    <section id="providers" className="nl-section" data-testid="section-providers">
      <span className="eyebrow">Providers</span>
      <h2>Claude today. <span className="accent">More tomorrow.</span></h2>
      <p className="lead">
        Notchy ships with a clean <code>UsageProvider</code> protocol so new providers
        slot in without touching the UI layer.
      </p>

      <div className="nl-providers-grid">
        {/* Claude — featured */}
        <motion.div
          className="nl-provider nl-provider-featured"
          initial={{ opacity: 0, y: 16 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.3 }}
          transition={{ duration: 0.5 }}
          data-testid="provider-claude"
        >
          <div className="head">
            <div className="logo">C</div>
            <h4>Claude</h4>
            <span className="badge available">Available</span>
          </div>
          <p>Session + weekly limits, reset times, Pro Sonnet sub-quota — everything Anthropic exposes in their usage endpoint.</p>
        </motion.div>

        {/* Coming next */}
        <motion.div
          className="nl-provider nl-provider-coming"
          initial={{ opacity: 0, y: 16 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.3 }}
          transition={{ duration: 0.5, delay: 0.08 }}
          data-testid="provider-coming"
        >
          <div className="head">
            <h4 style={{ color: "var(--text-2)" }}>Coming next</h4>
          </div>
          <div className="nl-coming-list">
            <div className="nl-coming-item">
              <div className="logo">G</div>
              <div>
                <div style={{ fontWeight: 600, fontSize: 14 }}>Gemini</div>
                <div style={{ fontSize: 12, color: "var(--text-2)" }}>In progress — get notified</div>
              </div>
            </div>
            <div className="nl-coming-item">
              <div className="logo">▢</div>
              <div>
                <div style={{ fontWeight: 600, fontSize: 14 }}>ChatGPT</div>
                <div style={{ fontSize: 12, color: "var(--text-2)" }}>Planned — community welcome</div>
              </div>
            </div>
          </div>
          <GeminiWaitlist />
          <a
            href="https://github.com/I-N-SILVA/NOTCHY/blob/main/swift-project/NotchyLimit/docs/PROVIDER_GUIDE.md"
            target="_blank"
            rel="noopener noreferrer"
            className="nl-contribute-link"
          >
            <Github size={13} /> Contribute a provider →
          </a>
        </motion.div>
      </div>
    </section>
  );
}
