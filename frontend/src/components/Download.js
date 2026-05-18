import React from "react";
import { Download as DownloadIcon, FileCode, Github } from "lucide-react";
import { dmgDownloadUrl, sourceDownloadUrl } from "@/lib/api";

export default function Download({ stats }) {
  return (
    <section id="download" className="nl-section" data-testid="section-download">
      <div className="nl-download">
        <h3>Get Notchy Limit</h3>
        <p>Free. Open source. MIT. Build it yourself or grab a signed DMG from GitHub Releases.</p>
        <div className="buttons">
          <a href={dmgDownloadUrl()} className="nl-cta" data-testid="download-dmg">
            <DownloadIcon size={16} /> Download DMG (macOS 12+)
          </a>
          <a href={sourceDownloadUrl()} className="nl-cta ghost" data-testid="download-source">
            <FileCode size={16} /> Download source (.zip)
          </a>
          <a
            href="https://github.com/notchylimit/notchy-limit"
            target="_blank"
            rel="noopener noreferrer"
            className="nl-cta ghost"
            data-testid="download-github"
          >
            <Github size={16} /> Star on GitHub
          </a>
        </div>
        <div className="meta" data-testid="download-meta">
          {stats ? (
            <>
              {stats.downloads} source downloads · {stats.waitlist_count} on the waitlist
            </>
          ) : (
            <>—</>
          )}
        </div>
      </div>
    </section>
  );
}
