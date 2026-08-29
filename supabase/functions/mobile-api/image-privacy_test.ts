import { Image } from "https://deno.land/x/imagescript@1.2.15/mod.ts";
import { redactImageWithBoxes } from "./image-privacy.ts";

Deno.test("redacts only the padded face region", () => {
  const image = new Image(120, 100);
  image.fill((x, y) => ((x * 13) << 24) | ((y * 17) << 16) | (((x + y) * 11) << 8) | 255);
  const outsideBefore = image.getPixelAt(2, 2);
  const insideBefore = image.getPixelAt(60, 50);

  const applied = redactImageWithBoxes(image, [{ x: 400, y: 350, width: 200, height: 300, confidence: 0.99 }]);

  if (applied !== 1) throw new Error(`expected one redaction, got ${applied}`);
  if (image.getPixelAt(2, 2) !== outsideBefore) throw new Error("pixel outside face region changed");
  if (image.getPixelAt(60, 50) === insideBefore) throw new Error("pixel inside face region was not redacted");
});

Deno.test("ignores invalid face boxes", () => {
  const image = new Image(20, 20);
  image.fill(0xffffffff);
  const applied = redactImageWithBoxes(image, [{ x: Number.NaN, y: 0, width: 10, height: 10, confidence: 1 }]);
  if (applied !== 0) throw new Error("invalid box should not be applied");
});
