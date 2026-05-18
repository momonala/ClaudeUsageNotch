import React, { useEffect, useState } from "react";
import Nav from "@/components/Nav";
import Hero from "@/components/Hero";
import HowItWorks from "@/components/HowItWorks";
import Privacy from "@/components/Privacy";
import Providers from "@/components/Providers";
import Setup from "@/components/Setup";
import Download from "@/components/Download";
import Footer from "@/components/Footer";
import { getStats } from "@/lib/api";

export default function Landing() {
  const [stats, setStats] = useState(null);

  useEffect(() => {
    let cancelled = false;
    getStats()
      .then((d) => { if (!cancelled) setStats(d); })
      .catch(() => { /* non-fatal */ });
    return () => { cancelled = true; };
  }, []);

  return (
    <div className="nl-page">
      <Nav />
      <Hero />
      <HowItWorks />
      <Privacy />
      <Providers />
      <Setup />
      <Download stats={stats} />
      <Footer stats={stats} />
    </div>
  );
}
