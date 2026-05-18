import React from "react";
import { Download, Github } from "lucide-react";
import { motion } from "framer-motion";
import { dmgDownloadUrl } from "@/lib/api";
import NotchDemo from "@/components/NotchDemo";
import RetroMascot from "@/components/RetroMascot";

export default function Hero() {
  return (
    <header className="nl-hero" data-testid="hero">
      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.6, ease: "easeOut" }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
          <RetroMascot size={56} />
          <div style={{ fontSize: 12, color: "var(--text-2)", letterSpacing: "0.16em", textTransform: "uppercase" }}>
            Open source · MIT · macOS
          </div>
        </div>
        <h1>
          See your AI limits<br />
          <span className="pop">at a glance.</span>
        </h1>
        <p>
          Notchy Limit lives in your MacBook notch. A tiny pill shows your
          session usage. Hover for the full picture — session, weekly, and reset times,
          all local, all yours.
        </p>
        <div className="actions">
          <a href={dmgDownloadUrl()} className="nl-cta" data-testid="hero-download">
            <Download size={16} /> Download for macOS
          </a>
          <a
            href="https://github.com/notchylimit/notchy-limit"
            target="_blank"
            rel="noopener noreferrer"
            className="nl-cta ghost"
            data-testid="hero-github"
          >
            <Github size={16} /> View on GitHub
          </a>
        </div>
        <div className="pills">
          <span className="nl-pill"><span className="ind" /> Claude supported</span>
          <span className="nl-pill">Gemini next</span>
          <span className="nl-pill">Local-only · Keychain</span>
        </div>
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 24 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.7, ease: "easeOut", delay: 0.1 }}
      >
        <NotchDemo />
      </motion.div>
    </header>
  );
}
