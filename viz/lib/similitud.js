// similitud — tokenizador + Jaccard compartidos por la UI de revisión (las
// «hermanas» de un lote se calculan aquí, sin ir a Postgres). Misma regla que
// bash/tasks/relacionadas.sh y sin_arquetipo.sh: minúsculas sin acentos,
// palabras de ≥4 letras que no sean stopwords, recortadas a prefijo 5 (un
// stemming pobre pero honesto: «mensajes»/«mensaje», «programar»/«programa»).
const STOP = new Set("para con como esta este esto ese esa del los las una unos unas por que sobre desde hasta entre hacer crear tarea tareas".split(" "));

function tokens(text) {
  const s = String(text || "").normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase();
  const out = new Set();
  for (const w of s.match(/[a-z0-9]+/g) || []) if (w.length >= 4 && !STOP.has(w)) out.add(w.slice(0, 5));
  return out;
}
function jaccard(a, b) {
  if (!a.size || !b.size) return 0;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  return inter / (a.size + b.size - inter);
}
module.exports = { tokens, jaccard };
