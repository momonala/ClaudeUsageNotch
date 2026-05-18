import axios from "axios";

const BACKEND_URL = process.env.REACT_APP_BACKEND_URL;
export const API = `${BACKEND_URL}/api`;

export const api = axios.create({
  baseURL: API,
  timeout: 15000,
});

export async function getStats() {
  const { data } = await api.get("/stats");
  return data;
}

export async function joinWaitlist(email, provider = "gemini") {
  const { data } = await api.post("/waitlist", { email, provider });
  return data;
}

export function sourceDownloadUrl() {
  return `${API}/download/source`;
}

export function dmgDownloadUrl() {
  return `${API}/download/dmg`;
}
