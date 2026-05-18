import React from "react";

/**
 * RetroMascot — a friendly pixel/retro-styled character rendered in pure SVG.
 * Antenna LED softly pulses. Used in the hero, nav, and footer.
 */
export default function RetroMascot({ size = 96, blinking = true }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 96 96"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="Notchy Limit mascot"
      data-testid="retro-mascot"
      style={{ display: "block" }}
    >
      <defs>
        <linearGradient id="headGrad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"  stopColor="#1c1c25" />
          <stop offset="100%" stopColor="#0c0c12" />
        </linearGradient>
        <linearGradient id="eyeGrad" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%"  stopColor="#ff8a66" />
          <stop offset="100%" stopColor="#ff5e3a" />
        </linearGradient>
        <radialGradient id="antennaGlow" cx="50%" cy="50%" r="50%">
          <stop offset="0%"  stopColor="#ff8a66" stopOpacity="0.9" />
          <stop offset="60%" stopColor="#ff8a66" stopOpacity="0.2" />
          <stop offset="100%" stopColor="#ff8a66" stopOpacity="0" />
        </radialGradient>
        <filter id="softGlow" x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="2" />
        </filter>
        <style>{`
          @keyframes nlBlink { 0%, 92%, 100% { transform: scaleY(1);} 95%, 97% { transform: scaleY(0.1);} }
          @keyframes nlPulse { 0%, 100% { opacity: 0.6;} 50% { opacity: 1;} }
          @keyframes nlBob { 0%, 100% { transform: translateY(0);} 50% { transform: translateY(-1.5px);} }
          .nl-eye  { transform-origin: center; transform-box: fill-box; ${blinking ? "animation: nlBlink 4.5s ease-in-out infinite;" : ""} }
          .nl-ant  { animation: nlPulse 1.6s ease-in-out infinite; }
          .nl-body { animation: nlBob 4s ease-in-out infinite; transform-origin: center; transform-box: fill-box; }
        `}</style>
      </defs>

      {/* Antenna glow */}
      <circle cx="48" cy="14" r="10" fill="url(#antennaGlow)" className="nl-ant" />
      {/* Antenna stem */}
      <rect x="47" y="16" width="2" height="10" rx="1" fill="#3a3a48" />
      {/* Antenna tip */}
      <circle cx="48" cy="16" r="3" fill="#ff8a66" filter="url(#softGlow)" />
      <circle cx="48" cy="16" r="2" fill="#ffbfa8" />

      <g className="nl-body">
        {/* Head body */}
        <rect x="18" y="26" width="60" height="54" rx="14" fill="url(#headGrad)" stroke="rgba(255,255,255,0.10)" strokeWidth="1" />
        {/* Visor / face plate */}
        <rect x="24" y="34" width="48" height="24" rx="8" fill="#0a0a10" stroke="rgba(255,255,255,0.06)" strokeWidth="1" />
        {/* Eyes */}
        <rect className="nl-eye" x="33" y="42" width="7" height="8" rx="3.5" fill="url(#eyeGrad)" />
        <rect className="nl-eye" x="56" y="42" width="7" height="8" rx="3.5" fill="url(#eyeGrad)" style={{ animationDelay: "0.15s" }} />
        {/* Cheek vents */}
        <rect x="27" y="62" width="6" height="2" rx="1" fill="#2a2a36" />
        <rect x="63" y="62" width="6" height="2" rx="1" fill="#2a2a36" />
        {/* Mouth (smile) */}
        <rect x="40" y="66" width="16" height="3" rx="1.5" fill="#6ef0f5" />
        {/* Side bolts */}
        <circle cx="22" cy="36" r="1.5" fill="#2a2a36" />
        <circle cx="74" cy="36" r="1.5" fill="#2a2a36" />
        <circle cx="22" cy="70" r="1.5" fill="#2a2a36" />
        <circle cx="74" cy="70" r="1.5" fill="#2a2a36" />
      </g>
    </svg>
  );
}
