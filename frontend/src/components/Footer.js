import React from "react";
import RetroMascot from "@/components/RetroMascot";

export default function Footer({ stats }) {
  return (
    <footer className="nl-footer" data-testid="footer">
      <div className="left">
        <RetroMascot size={28} />
        <span>Notchy Limit · v0.1.0 · MIT</span>
      </div>
      <div>
        Built for the Claude community ·
        {" "}
        <a href="https://github.com/notchylimit/notchy-limit" target="_blank" rel="noopener noreferrer">GitHub</a> ·
        {" "}
        <a href="https://github.com/notchylimit/notchy-limit/issues" target="_blank" rel="noopener noreferrer">Issues</a>
      </div>
    </footer>
  );
}
