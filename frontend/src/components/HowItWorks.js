import React from "react";
import { Cookie, MousePointer2, Bell } from "lucide-react";
import { motion } from "framer-motion";

const steps = [
  {
    icon: <Cookie size={18} />,
    title: "Grab your session token",
    body: (
      <>
        Sign into <kbd>claude.ai</kbd>, open DevTools (<kbd>⌘+⌥+I</kbd>), and
        copy one value from the Network tab. Takes 30 seconds — stored in your
        macOS Keychain, never on disk, never logged.
      </>
    ),
  },
  {
    icon: <MousePointer2 size={18} />,
    title: "Glance at the notch",
    body: (
      <>
        A small pill shows your session usage and reset ETA. Hover it for the full
        panel with weekly + pace details.
      </>
    ),
  },
  {
    icon: <Bell size={18} />,
    title: "Stay ahead of limits",
    body: (
      <>
        Get a quiet notification at 25/50/75/90% so you never hit the wall mid-task.
        Each threshold fires only once per window.
      </>
    ),
  },
];

export default function HowItWorks() {
  return (
    <section id="how" className="nl-section" data-testid="section-how">
      <span className="eyebrow">How it works</span>
      <h2>Three things, <span className="accent">that's it.</span></h2>
      <p className="lead">No accounts. No backend. Just a tiny app and your cookie.</p>
      <div className="nl-steps">
        {steps.map((s, i) => (
          <motion.div
            key={i}
            className="nl-step"
            initial={{ opacity: 0, y: 16 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, amount: 0.4 }}
            transition={{ duration: 0.5, delay: i * 0.08 }}
            data-testid={`step-${i}`}
          >
            <span className="num">{i + 1}</span>
            <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 8 }}>
              <span style={{ color: "var(--warm)" }}>{s.icon}</span>
              <h3>{s.title}</h3>
            </div>
            <p>{s.body}</p>
          </motion.div>
        ))}
      </div>
    </section>
  );
}
