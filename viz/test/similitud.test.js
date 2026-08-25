const { test } = require("node:test");
const assert = require("node:assert");
const { tokens, jaccard } = require("../lib/similitud");

test("tokens: normaliza acentos, quita cortas y stopwords, recorta a prefijo 5", () => {
  const t = tokens("Diseñar las diapositivas de la clase enfocadas en la oferta");
  assert.deepStrictEqual([...t].sort(), ["clase", "diapo", "disen", "enfoc", "ofert"]);
});
test("jaccard: 0 con vacíos, 1 idénticos, proporción si comparten", () => {
  assert.strictEqual(jaccard(new Set(), new Set(["a"])), 0);
  assert.strictEqual(jaccard(tokens("Escribir el VSL"), tokens("Escribir el VSL")), 1);
  const j = jaccard(tokens("Escribir los mensajes de calentamiento"), tokens("Programar los mensajes de calentamiento"));
  assert.ok(j > 0.4 && j < 1, `j=${j}`);
});
