import { Image } from "https://deno.land/x/imagescript@1.2.15/mod.ts";

export type FaceBox = {
  x: number;
  y: number;
  width: number;
  height: number;
  confidence: number;
};

export type ImagePrivacyResult = {
  file: File;
  audit: {
    success: boolean;
    processed: boolean;
    people_visible: boolean | null;
    faces: number;
    method: "targeted" | "full_image_fallback" | "not_needed";
    reason: string;
  };
};

type Detection = {
  people_visible: boolean;
  uncertain: boolean;
  faces: FaceBox[];
  reason: string;
};

const faceSchema = {
  type: "object",
  additionalProperties: false,
  required: ["people_visible", "uncertain", "faces", "reason"],
  properties: {
    people_visible: { type: "boolean" },
    uncertain: { type: "boolean" },
    faces: {
      type: "array",
      maxItems: 30,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["x", "y", "width", "height", "confidence"],
        properties: {
          x: { type: "number", minimum: 0, maximum: 1000 },
          y: { type: "number", minimum: 0, maximum: 1000 },
          width: { type: "number", minimum: 1, maximum: 1000 },
          height: { type: "number", minimum: 1, maximum: 1000 },
          confidence: { type: "number", minimum: 0, maximum: 1 },
        },
      },
    },
    reason: { type: "string", maxLength: 240 },
  },
} as const;

function extractOutputText(output: unknown) {
  if (!Array.isArray(output)) return "";
  for (const item of output) {
    if (!item || typeof item !== "object" || !("content" in item) || !Array.isArray(item.content)) continue;
    for (const part of item.content) {
      if (part?.type === "output_text" && typeof part.text === "string") return part.text;
    }
  }
  return "";
}

function bytesToBase64(bytes: Uint8Array) {
  let binary = "";
  const chunk = 0x8000;
  for (let index = 0; index < bytes.length; index += chunk) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunk));
  }
  return btoa(binary);
}

async function detectFaces(image: Image, userId: string): Promise<Detection> {
  const apiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!apiKey) throw new Error("OPENAI_API_KEY_MISSING");
  const preview = image.clone();
  const largestSide = Math.max(preview.width, preview.height);
  if (largestSide > 1280) {
    const scale = 1280 / largestSide;
    preview.resize(Math.max(1, Math.round(preview.width * scale)), Math.max(1, Math.round(preview.height * scale)));
  }
  const previewBytes = await preview.encodeJPEG(78);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(userId));
  const safetyIdentifier = Array.from(new Uint8Array(digest)).slice(0, 16).map((byte) => byte.toString(16).padStart(2, "0")).join("");
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: Deno.env.get("OPENAI_PRIVACY_MODEL") || Deno.env.get("OPENAI_REPORT_MODEL") || "gpt-5.4-mini",
      store: false,
      reasoning: { effort: "low" },
      max_output_tokens: 900,
      safety_identifier: safetyIdentifier,
      instructions: "You are a privacy redaction detector. Find every visible human face or identifiable head, including frontal, profile, partial, small, reflected, screen-displayed, printed-photo, and background faces. Coordinates must be normalized to 0..1000 relative to the complete image: x/y are top-left and width/height are box size. Include enough of the head to make the person unidentifiable. Set people_visible when any human/person appears. Set uncertain when a possible person/face may be present but cannot be localized reliably. Do not identify people. Be privacy-conservative.",
      input: [{ role: "user", content: [
        { type: "input_text", text: "Return all face/head boxes for mandatory privacy blurring." },
        { type: "input_image", image_url: `data:image/jpeg;base64,${bytesToBase64(previewBytes)}`, detail: "high" },
      ] }],
      text: { format: { type: "json_schema", name: "aman_face_redaction", strict: true, schema: faceSchema } },
    }),
    signal: AbortSignal.timeout(35_000),
  });
  if (!response.ok) throw new Error(`OPENAI_PRIVACY_HTTP_${response.status}`);
  const body = await response.json();
  const outputText = typeof body.output_text === "string" ? body.output_text : extractOutputText(body.output);
  if (!outputText) throw new Error("OPENAI_PRIVACY_EMPTY_OUTPUT");
  return JSON.parse(outputText) as Detection;
}

function clampedBox(box: FaceBox, width: number, height: number) {
  const x = box.x / 1000 * width;
  const y = box.y / 1000 * height;
  const w = box.width / 1000 * width;
  const h = box.height / 1000 * height;
  if (![x, y, w, h].every(Number.isFinite) || w < 2 || h < 2) return null;
  const paddingX = w * 0.3;
  const paddingY = h * 0.35;
  const left = Math.max(0, Math.floor(x - paddingX));
  const top = Math.max(0, Math.floor(y - paddingY));
  const right = Math.min(width, Math.ceil(x + w + paddingX));
  const bottom = Math.min(height, Math.ceil(y + h + paddingY));
  return right > left && bottom > top ? { left, top, width: right - left, height: bottom - top } : null;
}

export function redactImageWithBoxes(image: Image, boxes: FaceBox[]) {
  let applied = 0;
  for (const raw of boxes) {
    const box = clampedBox(raw, image.width, image.height);
    if (!box) continue;
    const region = image.clone().crop(box.left, box.top, box.width, box.height);
    const pixelWidth = Math.max(3, Math.min(18, Math.round(box.width / 18)));
    const pixelHeight = Math.max(3, Math.min(18, Math.round(box.height / 18)));
    region.resize(pixelWidth, pixelHeight);
    region.resize(box.width, box.height);
    image.composite(region, box.left, box.top);
    applied++;
  }
  return applied;
}

export async function protectImage(file: File, userId: string): Promise<ImagePrivacyResult> {
  let image: Image;
  try {
    image = await Image.decode(new Uint8Array(await file.arrayBuffer()));
  } catch {
    throw new Error("PRIVACY_IMAGE_DECODE_FAILED");
  }

  let detection: Detection | null = null;
  let method: ImagePrivacyResult["audit"]["method"] = "not_needed";
  let applied = 0;
  let reason = "لم تظهر وجوه بشرية في فحص الخصوصية";
  try {
    detection = await detectFaces(image, userId);
    applied = redactImageWithBoxes(image, detection.faces.filter((box) => box.confidence >= 0.35));
    if (applied > 0) {
      method = "targeted";
      reason = detection.reason;
    } else if (detection.people_visible || detection.uncertain) {
      pixelateEntireImage(image);
      method = "full_image_fallback";
      reason = "تمويه احتياطي كامل لوجود شخص دون موضع وجه موثوق";
    }
  } catch {
    pixelateEntireImage(image);
    method = "full_image_fallback";
    reason = "تمويه احتياطي كامل لتعذر فحص الوجوه";
  }

  let output: Uint8Array;
  try {
    output = await image.encodeJPEG(86);
  } catch {
    throw new Error("PRIVACY_IMAGE_ENCODE_FAILED");
  }
  const cleanName = `${file.name.replace(/\.[^.]+$/, "") || "aman-image"}-protected.jpg`;
  return {
    file: new File([Uint8Array.from(output).buffer], cleanName, { type: "image/jpeg" }),
    audit: {
      success: true,
      processed: method !== "not_needed",
      people_visible: detection?.people_visible ?? null,
      faces: applied,
      method,
      reason,
    },
  };
}

function pixelateEntireImage(image: Image) {
  const width = image.width;
  const height = image.height;
  const smallest = Math.min(width, height);
  const scale = Math.min(1, 28 / Math.max(1, smallest));
  image.resize(Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(height * scale)));
  image.resize(width, height);
}
