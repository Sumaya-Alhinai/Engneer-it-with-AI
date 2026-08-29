import { type ReportAnalysis, reportAnalysisSchema } from "./analysis.ts";
import { reportAgentInstructions } from "./prompt.ts";

type ReportInput = {
  report_id: string;
  user_id: string;
  selected_type: string;
  description: string;
  location_text: string;
  has_coordinates: boolean;
  image_urls: string[];
  has_camera_exif: boolean;
};

export async function analyzeReport(input: ReportInput) {
  const apiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!apiKey) throw new Error("OPENAI_API_KEY_MISSING");
  const model = Deno.env.get("OPENAI_REPORT_MODEL") || "gpt-5.4-mini";
  const content: Array<Record<string, unknown>> = [{
    type: "input_text",
    text: JSON.stringify({
      report_id: input.report_id,
      selected_type: input.selected_type,
      description: input.description,
      location_text: input.location_text,
      has_coordinates: input.has_coordinates,
      has_image: input.image_urls.length > 0,
      has_camera_exif: input.has_camera_exif,
    }),
  }];
  for (const imageUrl of input.image_urls.slice(0, 3)) {
    content.push({ type: "input_image", image_url: imageUrl, detail: "high" });
  }

  const payload = {
    model,
    store: false,
    reasoning: { effort: "low" },
    max_output_tokens: 3500,
    instructions: reportAgentInstructions,
    input: [{ role: "user", content }],
    text: {
      format: {
        type: "json_schema",
        name: "aman_report_analysis",
        strict: true,
        schema: reportAnalysisSchema,
      },
    },
    safety_identifier: await safetyIdentifier(input.user_id),
  };

  let lastError = "OPENAI_REQUEST_FAILED";
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const response = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(55_000),
      });
      if (!response.ok) {
        lastError = `OPENAI_HTTP_${response.status}`;
        if (
          (response.status === 429 || response.status >= 500) && attempt < 2
        ) continue;
        throw new Error(lastError);
      }
      const body = await response.json();
      const outputText = typeof body.output_text === "string"
        ? body.output_text
        : extractOutputText(body.output);
      if (!outputText) throw new Error("OPENAI_EMPTY_OUTPUT");
      return {
        analysis: JSON.parse(outputText) as ReportAnalysis,
        model,
        responseId: String(body.id ?? ""),
      };
    } catch (error) {
      lastError = error instanceof Error ? error.message : lastError;
      if (
        attempt < 2 &&
        (lastError.includes("timed out") ||
          lastError.includes("OPENAI_HTTP_5") ||
          lastError === "OPENAI_HTTP_429")
      ) continue;
      throw new Error(lastError);
    }
  }
  throw new Error(lastError);
}

function extractOutputText(output: unknown) {
  if (!Array.isArray(output)) return "";
  for (const item of output) {
    if (!item || typeof item !== "object" || !Array.isArray(item.content)) {
      continue;
    }
    for (const part of item.content) {
      if (part?.type === "output_text" && typeof part.text === "string") {
        return part.text;
      }
    }
  }
  return "";
}

async function safetyIdentifier(userId: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(userId),
  );
  return Array.from(new Uint8Array(digest)).slice(0, 16).map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}
