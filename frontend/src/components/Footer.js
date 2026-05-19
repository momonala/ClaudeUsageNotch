import React from "react";
import RetroMascot from "@/components/RetroMascot";

export default function Footer({ stats }) {
  return (
    <footer className="nl-footer" data-testid="footer">
      <div className="left">
        <RetroMascot size={28} />
        <span>Notchy Limit · v0.1.0 · MIT</span>
      </div>
      <div className="nl-footer-links">
        Built for the Claude community ·
        {" "}
        <a href="https://github.com/I-N-SILVA/NOTCHY" target="_blank" rel="noopener noreferrer">GitHub</a> ·
        {" "}
        <a href="https://github.com/I-N-SILVA/NOTCHY/issues" target="_blank" rel="noopener noreferrer">Issues</a> ·
        {" "}
        <a href="https://ko-fi.com/iamnsilva" target="_blank" rel="noopener noreferrer" className="nl-kofi-link">☕ Buy me a coffee</a>
      </div>
    </footer>
  );
}
