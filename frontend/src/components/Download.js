import React from "react";
import { Download as DownloadIcon, FileCode, Github, Star } from "lucide-react";
import { dmgDownloadUrl, sourceDownloadUrl } from "@/lib/api";

export default function Download({ stats }) {
  return (
    <section id="download" className="nl-section" data-testid="section-download">
      <div className="nl-download">
        <h3>Get Notchy Limit</h3>
        <p>Free. Open source. MIT. Build it yourself or grab a signed DMG from GitHub Releases.</p>
        <div className="buttons">
          <a href={dmgDownloadUrl()} className="nl-cta" data-testid="download-dmg">
            <DownloadIcon size={16} /> Download DMG
          </a>
          <a href={sourceDownloadUrl()} className="nl-cta ghost" data-testid="download-source">
            <FileCode size={16} /> Source .zip
          </a>
        </div>
        <div className="nl-download-sub">
          <a
            href="https://github.com/I-N-SILVA/NOTCHY"
            target="_blank"
            rel="noopener noreferrer"
            className="nl-download-star"
            data-testid="download-github"
          >
            <Star size={13} /> Star on GitHub
          </a>
          {stats && (
            <span className="nl-download-meta" data-testid="download-meta">
              {stats.downloads} source downloads · {stats.waitlist_count} on the waitlist
            </span>
          )}
        </div>
      </div>
    </section>
  );
}
