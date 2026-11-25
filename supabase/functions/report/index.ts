// Reports from the app ("Melden"): something wrong in a lesson, a question or elsewhere. Each report is stored
// (table "reports") and sent as an e-mail to the Anatomia mailbox through Resend, once the secret RESEND_API_KEY is
// set; reports from before that go out with the next one. A device may send 10 reports an hour; at most 90 e-mails a day.
import { createClient } from "jsr:@supabase/supabase-js@2";

const TO = "anatomia.lernen@gmail.com";
const SITE = "https://niklasschroeder1904-ops.github.io/Anatomia10/";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const str = (v: unknown, n: number) => (typeof v === "string" ? v : v == null ? "" : String(v)).slice(0, n);
const esc = (s: unknown) => str(s, 4000).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
const KINDS: Record<string, string> = {
  learn: "Lernkarte", question: "Frage", case: "Klinischer Fall", flash: "Karteikarte", exam: "Prüfungsfrage",
  figure: "Bild im Bildatlas", figquiz: "Bildquiz", mnemonic: "Eselsbrücke", other: "Sonstiges",
};
const REASONS: Record<string, string> = {
  fact: "Inhalt falsch", picture: "Bild oder Markierung falsch", typo: "Tippfehler", translation: "Übersetzung", other: "Sonstiges",
};
const VIEWS: Record<string, string> = { atlas: "Atlasbild", real3d: "3D echt", "3d": "3D-Schema", schema: "Schema" };

async function sha(s: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

// a picture of the app (a file name of the app's own), as an address the e-mail can show
const picture = (src: unknown) => {
  const f = str(src, 200).replace(/^\.?\//, "").split("?")[0];
  return /^[\w.\-]+\.(jpg|jpeg|png)$/i.test(f) ? SITE + f : null;
};

function mailOf(r: Record<string, any>) {
  const c = (r.ctx && typeof r.ctx === "object" ? r.ctx : {}) as Record<string, any>;
  const row = (k: string, v: unknown) => (v == null || v === "" ? "" : `<tr><td style="padding:4px 10px 4px 0;color:#5B6B80;vertical-align:top;white-space:nowrap">${esc(k)}</td><td style="padding:4px 0">${esc(v)}</td></tr>`);
  const kind = KINDS[str(r.kind, 40)] || str(r.kind, 40) || "Meldung";
  const lesson = [c.lesson?.title, c.lesson?.unit && `(${c.lesson.unit})`].filter(Boolean).join(" ");
  const slide = c.slide ? `${c.slide.n} von ${c.slide.total}` : "";
  const item = c.item ? [c.item.la, c.item.de].filter(Boolean).join(" – ") : "";
  const q = c.question || {};
  const opts = Array.isArray(q.options)
    ? `<ol style="margin:4px 0 0;padding-left:20px">${q.options
        .slice(0, 12)
        .map((o: any, i: number) => `<li>${esc(o && o.label)}${o && o.correct ? " <b style=\"color:#2B8A3E\">✓ richtig</b>" : ""}${q.picked === i ? " <i style=\"color:#C92A2A\">← gewählt</i>" : ""}</li>`)
        .join("")}</ol>`
    : "";
  const pics = (Array.isArray(c.images) ? c.images : []).map(picture).filter(Boolean).slice(0, 3) as string[];
  const answered = q.answered ? (q.right ? "richtig" : "falsch") : "";
  const where = str(c.lesson?.title, 80) || str(c.figure, 80);
  const subject = `Anatomia-Meldung #${r.id}: ${kind}${where ? " · " + where : ""}`;
  const html = `<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;max-width:640px;color:#1E2836">
<h2 style="margin:0 0 4px">Meldung #${r.id}: ${esc(kind)}</h2>
<div style="color:#5B6B80;margin-bottom:14px">${esc(new Date(r.created_at).toLocaleString("de-DE", { timeZone: "Europe/Berlin" }))}</div>
<div style="background:#FFF4E6;border:1px solid #FFD8A8;border-radius:10px;padding:12px 14px;margin-bottom:16px">
<div style="font-weight:700;margin-bottom:4px">Was ist falsch${r.reason ? " – " + esc(REASONS[r.reason] || r.reason) : ""}:</div>
<div style="white-space:pre-wrap">${esc(r.message)}</div></div>
<table style="border-collapse:collapse;font-size:15px;margin-bottom:14px">
${row("Stelle in der App", c.what)}${row("Lektion", lesson)}${row("Lektion (ID)", c.lesson?.id)}${row("Runde", c.round)}${row("Stapel", c.deck)}
${row("Karte / Folie", slide)}${row("Struktur", item)}${row("Karte (ID)", c.item?.id)}${row("Beschriftung Nr.", c.item?.label)}${row("Text der Karte", c.item?.fact)}
${row("Ansicht", VIEWS[c.view] || c.view)}${row("Frage", q.n ? `${q.n} von ${q.total}` : "")}${row("Fragetyp", q.type)}${row("Fragetext", q.text)}${row("Eingetippt", q.typed)}${row("Beantwortet", answered)}
${row("Fall Nr.", c.case?.no)}${row("Fall", c.case?.text)}${row("Frage zum Fall", c.case?.question)}${row("Erklärung", c.case?.explain)}${row("Bild", c.figure)}
${row("Eselsbrücken", Array.isArray(c.mnemonics) ? c.mnemonics.join(", ") : "")}
</table>
${opts ? `<div style="margin-bottom:14px"><b>Antworten:</b>${opts}</div>` : ""}
${pics.map((p) => `<div style="margin-bottom:10px"><img src="${esc(p)}" alt="" style="max-width:100%;max-height:480px;border:1px solid #E3E8F0;border-radius:8px"><div style="font-size:12px;color:#5B6B80">${esc(p)}</div></div>`).join("")}
${c.screen ? `<details open><summary style="font-weight:700;margin:6px 0">So stand es auf dem Bildschirm</summary><pre style="white-space:pre-wrap;font-family:inherit;background:#F4F6FB;border-radius:8px;padding:10px;font-size:13px">${esc(c.screen)}</pre></details>` : ""}
<table style="border-collapse:collapse;font-size:13px;color:#5B6B80;margin-top:12px">
${row("Bildschirm", c.route)}${row("App-Sprache", r.lang)}${row("Begriffe", c.terms)}${row("Konto", c.nick ? c.nick : "ohne Konto")}${row("Version", c.version)}${row("Gerät", c.device)}
</table></div>`;
  return { subject, html };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  let b: Record<string, any>;
  try {
    b = await req.json();
  } catch {
    return json({ error: "json" }, 400);
  }
  const message = str(b.message, 2000).trim();
  if (message.length < 3) return json({ error: "message" }, 400);
  const ctx = b.ctx && typeof b.ctx === "object" && !Array.isArray(b.ctx) ? b.ctx : {};
  if (JSON.stringify(ctx).length > 15000) return json({ error: "ctx" }, 400);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  // who reports: a signed-in account (its nickname goes into the e-mail), else nobody
  let uid: string | null = null;
  const auth = req.headers.get("authorization") || "";
  if (/^Bearer [\w-]+\.[\w-]+\.[\w-]+$/.test(auth)) {
    const { data } = await db.auth.getUser(auth.slice(7));
    if (data && data.user) {
      uid = data.user.id;
      const { data: p } = await db.from("profiles").select("name").eq("id", uid).maybeSingle();
      ctx.nick = p ? p.name : null;
    }
  }
  // a device may send 10 reports an hour (its address only as a hash, keyed with a secret of the server)
  const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim();
  const ipHash = ip ? await sha(ip + "|anatomia-report|" + (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "").slice(-24)) : null;
  if (ipHash) {
    const { count } = await db.from("reports").select("id", { count: "exact", head: true }).eq("ip_hash", ipHash).gte("created_at", new Date(Date.now() - 36e5).toISOString());
    if ((count || 0) >= 10) return json({ error: "rate" }, 429);
  }
  const { data: rep, error } = await db
    .from("reports")
    .insert({
      user_id: uid,
      ip_hash: ipHash,
      kind: str(b.kind, 40) || "other",
      lesson_id: str(ctx.lesson && ctx.lesson.id, 120) || null,
      lesson_title: str(ctx.lesson && ctx.lesson.title, 300) || null,
      reason: str(b.reason, 60) || null,
      message,
      ctx,
      lang: str(b.lang, 8) || null,
    })
    .select("id")
    .single();
  if (error || !rep) return json({ error: "db" }, 500);
  // the e-mails: this report and any that waited, while the day's limit allows
  const key = Deno.env.get("RESEND_API_KEY");
  let mailed = false;
  if (key) {
    const day = new Date(Date.now() - 864e5).toISOString();
    const { count: sentToday } = await db.from("reports").select("id", { count: "exact", head: true }).gte("emailed_at", day);
    const room = Math.max(0, 90 - (sentToday || 0));
    const { data: open } = await db.from("reports").select("*").is("emailed_at", null).order("created_at", { ascending: true }).limit(Math.min(5, room));
    for (const r of open || []) {
      const m = mailOf(r);
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from: "Anatomia <onboarding@resend.dev>", to: [TO], subject: m.subject, html: m.html }),
      });
      if (!res.ok) break;
      await db.from("reports").update({ emailed_at: new Date().toISOString() }).eq("id", r.id);
      if (r.id === rep.id) mailed = true;
    }
  }
  return json({ ok: true, id: rep.id, mailed });
});
