import React, { useEffect, useState } from "react";
import { Download, Github, Star } from "lucide-react";
import { motion } from "framer-motion";
import { dmgDownloadUrl } from "@/lib/api";
import NotchDemo from "@/components/NotchDemo";
import RetroMascot from "@/components/RetroMascot";

export default function Hero() {
  const [stars, setStars] = useState(null);
  useEffect(() => {
    fetch("https://api.github.com/repos/I-N-SILVA/NOTCHY")
      .then((r) => r.json())
      .then((d) => typeof d.stargazers_count === "number" && setStars(d.stargazers_count))
      .catch(() => {});
  }, []);
  return (
    <header className="nl-hero" data-testid="hero">
      <motion.div
        className="nl-hero-copy"
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.55, ease: "easeOut" }}
      >
        {/* Badge row */}
        <div className="nl-hero-badge-row">
          <RetroMascot size={44} />
          <div className="nl-hero-badges">
            <span className="nl-badge accent">Free &amp; Open Source</span>
            <span className="nl-badge">MIT License</span>
            <span className="nl-badge">macOS 12+</span>
          </div>
        </div>

        <h1>
          Your notch.<br />
          <span className="pop">Now showing your AI limits.</span>
        </h1>

        <p className="nl-hero-lead">
          A tiny pill blends seamlessly with your MacBook notch and shows your
          Claude usage at a glance. Hover to expand — session %, weekly quota,
          time to reset. Everything runs locally. Nothing leaves your Mac.
        </p>

        {/* Feature bullets */}
        <ul className="nl-hero-bullets">
          <li><span className="bull-dot healthy" /> Session &amp; weekly usage, always visible</li>
          <li><span className="bull-dot warn" /> Threshold alerts at 25 / 50 / 75 / 90%</li>
          <li><span className="bull-dot" style={{ background: "var(--cool)" }} /> Cookie stored in Keychain — never logged</li>
        </ul>

        <div className="actions">
          <a
            href="https://github.com/I-N-SILVA/NOTCHY"
            target="_blank"
            rel="noopener noreferrer"
            className="nl-cta"
            data-testid="hero-github"
          >
            <Github size={16} /> View on GitHub
          </a>
          <a href={dmgDownloadUrl()} className="nl-cta ghost" data-testid="hero-download">
            <Download size={16} /> Build from source
          </a>
        </div>

        <div className="nl-hero-meta">
          <Star size={12} />
          {stars !== null
            ? <span><strong style={{ color: "var(--text-0)" }}>{stars.toLocaleString()}</strong> stars on GitHub — add yours</span>
            : <span>Star the repo if you find it useful</span>
          }
        </div>
      </motion.div>

      <motion.div
        className="nl-hero-demo"
        initial={{ opacity: 0, y: 28 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.65, ease: "easeOut", delay: 0.12 }}
      >
        <NotchDemo />
      </motion.div>
    </header>
  );
}
