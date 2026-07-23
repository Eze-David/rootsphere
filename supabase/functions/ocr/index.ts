// Rootsphere — Phase 3 OCR Edge Function.
//
// Cross-platform text extraction for record attachments. The Flutter client
// invokes this with `{ fileUrl }` (a public Supabase Storage URL) and
// receives `{ text }`. Running it server-side keeps a single code path
// across web and mobile.
//
// Two paths, chosen by file type:
//  - Images/PDFs: actual OCR via OCR.space (https://ocr.space/ocrapi) — set
//    the API key as a secret:
//      supabase secrets set OCR_SPACE_API_KEY=your_key
//  - .docx: not an image, so there's nothing to optically recognise — the
//    text is already there natively in the file's XML, so this reads it
//    directly instead of routing through an OCR provider.
//
// Deploy:
//   supabase functions deploy ocr
//
// To swap OCR providers (e.g. Google Vision), only `runOcr` needs changing.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import JSZip from "npm:jszip@3.10.1";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isDocxUrl(fileUrl: string): boolean {
  return /\.docx(\?|$)/i.test(fileUrl);
}

/** Calls OCR.space with a remote file URL and returns the parsed text. */
async function runOcr(fileUrl: string): Promise<string> {
  const apiKey = Deno.env.get("OCR_SPACE_API_KEY");
  if (!apiKey) {
    throw new Error("OCR_SPACE_API_KEY is not configured.");
  }

  const form = new FormData();
  form.append("url", fileUrl);
  form.append("language", "eng");
  form.append("isOverlayRequired", "false");
  form.append("scale", "true");
  form.append("OCREngine", "2");
  // PDFs are supported by OCR.space; the filetype is inferred from the URL.

  const res = await fetch("https://api.ocr.space/parse/image", {
    method: "POST",
    headers: { apikey: apiKey },
    body: form,
  });

  if (!res.ok) {
    throw new Error(`OCR provider returned ${res.status}`);
  }

  const data = await res.json();
  if (data.IsErroredOnProcessing === true) {
    const msg = Array.isArray(data.ErrorMessage)
      ? data.ErrorMessage.join(" ")
      : String(data.ErrorMessage ?? "OCR failed");
    throw new Error(msg);
  }

  const parsed: string = (data.ParsedResults ?? [])
    .map((r: { ParsedText?: string }) => r.ParsedText ?? "")
    .join("\n")
    .trim();
  return parsed;
}

function decodeXmlEntities(s: string): string {
  return s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

/**
 * Pulls plain text out of a .docx's `word/document.xml`. Text lives in
 * `<w:t>` runs; a single pass over the XML in document order — alternating
 * on `<w:t>…</w:t>` and bare `</w:p>` (paragraph end) — rebuilds the text
 * with paragraph breaks in the right places without needing a full XML
 * parser.
 */
function extractDocxText(xml: string): string {
  const tokenRe = /<w:t[^>]*>([\s\S]*?)<\/w:t>|<\/w:p>/g;
  let result = "";
  let match: RegExpExecArray | null;
  while ((match = tokenRe.exec(xml)) !== null) {
    result += match[1] !== undefined ? decodeXmlEntities(match[1]) : "\n";
  }
  return result.trim();
}

/** Downloads a .docx and extracts its text directly (no OCR provider). */
async function runDocxExtraction(fileUrl: string): Promise<string> {
  const res = await fetch(fileUrl);
  if (!res.ok) {
    throw new Error(`Could not download the file (${res.status}).`);
  }
  const bytes = new Uint8Array(await res.arrayBuffer());
  const zip = await JSZip.loadAsync(bytes);
  const documentXml = zip.file("word/document.xml");
  if (!documentXml) {
    throw new Error("Not a valid .docx file.");
  }
  const xml = await documentXml.async("string");
  const text = extractDocxText(xml);
  if (!text) {
    throw new Error("No text found in this document.");
  }
  return text;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const { fileUrl } = await req.json();
    if (typeof fileUrl !== "string" || !fileUrl.startsWith("http")) {
      return json({ error: "A valid fileUrl is required." }, 400);
    }
    const text = isDocxUrl(fileUrl)
      ? await runDocxExtraction(fileUrl)
      : await runOcr(fileUrl);
    return json({ text });
  } catch (err) {
    const message = err instanceof Error ? err.message : "OCR failed";
    return json({ error: message }, 500);
  }
});
