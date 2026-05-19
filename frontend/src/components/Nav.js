import React from "react";
import { Github, Download as DownloadIcon } from "lucide-react";
import { dmgDownloadUrl } from "@/lib/api";
import RetroMascot from "@/components/RetroMascot";

export default function Nav() {
  return (
    <nav className="nl-nav" data-testid="nl-nav">
      <div className="brand">
        <RetroMascot size={26} />
        <span>Notchy Limit</span>
      </div>
      <div className="links">
        <a href="#how" data-testid="nav-how">How it works</a>
        <a href="#providers" data-testid="nav-providers">Providers</a>
        <a href="#setup" data-testid="nav-setup">Setup</a>
        <a href="#privacy" data-testid="nav-privacy">Privacy</a>
      </div>
      <a
        href="https://github.com/I-N-SILVA/NOTCHY"
        target="_blank"
        rel="noopener noreferrer"
        className="nl-cta ghost"
        data-testid="nav-github"
      >
        <Github size={14} /> GitHub
      </a>
      <a
        href={dmgDownloadUrl()}
        className="nl-cta"
        data-testid="nav-download"
      >
        <DownloadIcon size={14} /> Download
      </a>
    </nav>
  );
}
