import React, { useState } from "react";
import { motion } from "framer-motion";
import { joinWaitlist } from "@/lib/api";

const providers = [
  { key: "claude",  letter: "C", name: "Claude",  status: "available", copy: "Session + weekly limits, reset times, Pro Sonnet sub-quota." },
  { key: "gemini",  letter: "G", name: "Gemini",  status: "soon",      copy: "Coming next. Join the waitlist to get notified when support lands." },
  { key: "chatgpt", letter: "▢", name: "ChatGPT", status: "planned",   copy: "Planned. Provider abstraction is in place, awaiting community help." },
];

function WaitlistRow({ provider }) {
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
      const res = await joinWaitlist(email, provider);
      setMsg({
        ok: true,
        text: res.deduped ? "You're already on the list — we'll be in touch." : "You're on the list.",
      });
      setEmail("");
    } catch (err) {
      setMsg({ ok: false, text: "Couldn't add you. Try again later." });
    } finally {
      setBusy(false);
    }
  };

  return (
    <form className="nl-waitlist" onSubmit={submit} data-testid={`waitlist-form-${provider}`}>
      <input
        type="email"
        placeholder="you@domain.com"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        disabled={busy}
        aria-label={`Email for ${provider} waitlist`}
        data-testid={`waitlist-email-${provider}`}
      />
      <button type="submit" disabled={busy} data-testid={`waitlist-submit-${provider}`}>
        {busy ? "Joining…" : "Join waitlist"}
      </button>
      {msg && (
        <div
          className={`nl-waitlist-msg ${msg.ok ? "ok" : "err"}`}
          style={{ gridColumn: "1 / -1", flexBasis: "100%" }}
          data-testid={`waitlist-msg-${provider}`}
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
      <p className="lead">Notchy Limit ships with a clean <code>UsageProvider</code> interface so new providers slot in without touching the UI.</p>
      <div className="nl-providers">
        {providers.map((p, i) => (
          <motion.div
            key={p.key}
            className="nl-provider"
            initial={{ opacity: 0, y: 16 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, amount: 0.3 }}
            transition={{ duration: 0.5, delay: i * 0.08 }}
            data-testid={`provider-${p.key}`}
          >
            <div className="head">
              <div className="logo">{p.letter}</div>
              <h4>{p.name}</h4>
              <span className={`badge ${p.status}`}>{p.status === "available" ? "Available" : p.status === "soon" ? "Coming soon" : "Planned"}</span>
            </div>
            <p>{p.copy}</p>
            {p.status !== "available" && <WaitlistRow provider={p.key} />}
          </motion.div>
        ))}
      </div>
    </section>
  );
}
