#!/usr/bin/env python3
"""Generate a self-contained force-directed viewer for a graph, with the data
embedded inline (no external requests — Artifact CSP-safe).

One engine, two profiles — the layers of the ontology:
  schema   : graph.json     → entities, FKs, rules            (the data layer)
  business : business.json  → value chain → SOP → arquetipo    (the concept layer)

Usage: build_viewer.py <dir> [--profile schema|business] [--graph F] [--out F]
"""
import json, os, sys

argv = sys.argv[1:]
D = argv[0] if argv and not argv[0].startswith("--") else "."
def opt(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default
PROFILE = opt("--profile", "schema")

# ---- profiles ---------------------------------------------------------------
# Colors are mid-tone on purpose: they must read on both the dark and the light
# ground, since the page follows the viewer's theme.
PROFILES = {
    "schema": {
        "graph": "graph.json", "out": "schema-graph.html",
        "title": "ikigaigm · mapa de entidades",
        "subtitle": "ontología de datos de Ikigai — primer vistazo desde el esquema",
        "colors": {
            "tasks":"#E0A458","meetings":"#4FB0A5","crm":"#E0685E","ads":"#9B7EDE",
            "finance":"#5FB37A","catalog":"#5B9BD5","people":"#E6C34A","projects":"#CE6BA6",
            "okr":"#3FB6C9","runtime":"#7C77D6","content":"#E08A45","whatsapp":"#7FB84A",
            "misc":"#9AA0A6",
        },
        "stats": [("entidades","n_nodes"),("foreign keys","n_fk"),
                  ("implícitas","n_implicit"),("reglas","n_rules")],
        "dashed": ["implicit"], "groups_off": [],
        "edge_labels": {"fk":"foreign keys","implicit":"implícitas"},
        "hint": ('<b>doble-click</b> un dominio para aislarlo · el <b>tamaño</b> del nodo crece con '
                 'sus conexiones · línea <code>punteada</code> = relación <b>implícita</b>: no la fuerza '
                 'ningún FK, se verificó contra datos reales y el panel muestra su tasa de resolución.'),
        "legend_title": "Dominios",
    },
    "business": {
        "graph": "business.json", "out": "business-graph.html",
        "title": "Ikigai · ontología de la organización",
        "subtitle": "cadena de valor → macro-proceso → SOP → arquetipo → tarea",
        "colors": {
            "macro":"#E0685E","sop":"#5B9BD5","archetype":"#E0A458",
            "role":"#E6C34A","project":"#CE6BA6","io_type":"#4FB0A5",
        },
        "stats": [("conceptos","n_nodes"),("relaciones","n_edges")],
        # observed relations are drawn dashed: they come from real tasks, not
        # from the catalog's declaration
        "dashed": ["ejecuta","consume"],
        # 644 edges at once is a hairball. Open on the process spine
        # (macro → SOP → arquetipo) with the peripheral classes folded away;
        # switching one on brings its relations with it.
        "groups_off": ["role","project","io_type"],
        "edge_labels": {"precede":"cadena","descompone":"descompone","agrupa":"agrupa",
                        "dueño":"dueño (decl.)","ejecuta":"ejecuta (obs.)",
                        "consume":"consume (obs.)","requiere":"requiere","produce":"produce"},
        "hint": ('<b>doble-click</b> una clase para aislarla · línea <code>punteada</code> = relación '
                 '<b>observada</b> (sale de las 329 tareas reales), sólida = <b>declarada</b> por el '
                 'catálogo. El contraste entre ambas es el hallazgo.'),
        "legend_title": "Clases",
    },
}
P = PROFILES[PROFILE]
graph = json.load(open(os.path.join(D, opt("--graph", P["graph"]))))
OUTFILE = opt("--out", P["out"])

# ---- normalise both shapes onto one vocabulary the JS can rely on -----------
# schema nodes carry domain/domain_label and display as their id; business nodes
# carry group/group_label and display as their short code.
meta = graph["meta"]
meta["groups"] = meta.get("domains") or meta.get("classes")
for n in graph["nodes"]:
    n["group"] = n.get("domain") or n.get("group")
    n["group_label"] = n.get("domain_label") or n.get("group_label")
    n["disp"] = n.get("label") or n["id"]
kinds = []
for e in graph["edges"]:
    if e["kind"] not in kinds: kinds.append(e["kind"])
meta["edge_kinds"] = [
    {"k": k, "label": P["edge_labels"].get(k, k),
     "n": sum(1 for e in graph["edges"] if e["kind"] == k),
     "dash": k in P["dashed"]}
    for k in kinds
]
meta["groups_off"] = P.get("groups_off", [])
STATS = [[lbl, meta.get(key)] for lbl, key in P["stats"] if meta.get(key) is not None]
STATS.append(["clases" if PROFILE == "business" else "dominios", len(meta["groups"])])

DATA  = json.dumps(graph, ensure_ascii=False, separators=(",", ":"))
CJSON = json.dumps(P["colors"])
SJSON = json.dumps(STATS, ensure_ascii=False)

HTML = r"""<meta charset="utf-8">
<title>__TITLE__</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root{
  --bg:#0f131a; --canvas:#0c1016; --panel:#161c26; --panel2:#1b222e;
  --ink:#e6ebf2; --muted:#8a97a8; --line:#2a333f; --line2:#38424f;
  --accent:#6ea8fe; --shadow:rgba(0,0,0,.45);
  --font:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
  --mono:ui-monospace,"SF Mono","JetBrains Mono","Cascadia Code",Menlo,monospace;
}
@media (prefers-color-scheme:light){
  :root{ --bg:#eef1f5; --canvas:#f4f6f9; --panel:#ffffff; --panel2:#f2f5f8;
    --ink:#1a2230; --muted:#5b6675; --line:#d7dee6; --line2:#c3cdd7;
    --accent:#2f6fe0; --shadow:rgba(20,30,50,.12); }
}
:root[data-theme="dark"]{ --bg:#0f131a; --canvas:#0c1016; --panel:#161c26; --panel2:#1b222e;
  --ink:#e6ebf2; --muted:#8a97a8; --line:#2a333f; --line2:#38424f; --accent:#6ea8fe; --shadow:rgba(0,0,0,.45); }
:root[data-theme="light"]{ --bg:#eef1f5; --canvas:#f4f6f9; --panel:#ffffff; --panel2:#f2f5f8;
  --ink:#1a2230; --muted:#5b6675; --line:#d7dee6; --line2:#c3cdd7; --accent:#2f6fe0; --shadow:rgba(20,30,50,.12); }

*{box-sizing:border-box}
html,body{height:100%;margin:0}
body{background:var(--bg);color:var(--ink);font-family:var(--font);
  overflow:hidden;-webkit-font-smoothing:antialiased}

/* ---- top bar ---- */
header{position:fixed;top:0;left:0;right:0;height:60px;z-index:20;
  display:flex;align-items:center;gap:20px;padding:0 20px;
  background:linear-gradient(180deg,var(--panel),color-mix(in srgb,var(--panel) 88%,transparent));
  border-bottom:1px solid var(--line);backdrop-filter:blur(6px)}
.brand{display:flex;flex-direction:column;gap:1px;min-width:0}
.brand h1{font-family:var(--mono);font-size:14px;font-weight:600;margin:0;letter-spacing:.02em;white-space:nowrap}
.brand .sub{font-size:11px;color:var(--muted);letter-spacing:.04em}
.stats{display:flex;gap:8px;margin-left:auto;flex-wrap:wrap}
.stat{background:var(--panel2);border:1px solid var(--line);border-radius:7px;
  padding:5px 11px;display:flex;flex-direction:column;line-height:1.15;min-width:64px}
.stat b{font-family:var(--mono);font-size:15px;font-variant-numeric:tabular-nums}
.stat span{font-size:10px;color:var(--muted);letter-spacing:.05em;text-transform:uppercase}

/* ---- left rail ---- */
.rail{position:fixed;top:72px;left:16px;z-index:15;width:236px;
  background:var(--panel);border:1px solid var(--line);border-radius:12px;
  box-shadow:0 8px 30px var(--shadow);overflow:hidden;
  display:flex;flex-direction:column;max-height:calc(100vh - 92px)}
.rail .pad{padding:12px}
.search{width:100%;background:var(--panel2);border:1px solid var(--line2);color:var(--ink);
  border-radius:8px;padding:8px 10px;font-family:var(--mono);font-size:12px;outline:none}
.search:focus{border-color:var(--accent)}
.sec-t{font-size:10px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);
  margin:14px 2px 7px}
.sec-t.row{display:flex;align-items:baseline;justify-content:space-between;gap:8px}
.mini{font-size:10px;letter-spacing:.04em;text-transform:none;color:var(--muted);cursor:pointer;
  user-select:none;border:none;background:none;padding:0;font-family:var(--font)}
.mini:hover{color:var(--accent)}
.mini + .mini{margin-left:2px}
.sep{color:var(--line2)}
.legend{display:flex;flex-direction:column;gap:1px;overflow-y:auto}
.dom{display:flex;align-items:center;gap:9px;padding:5px 7px;border-radius:7px;cursor:pointer;
  user-select:none;border:1px solid transparent}
.dom:hover{background:var(--panel2)}
.dom.off{opacity:.34}
.dom .dot{width:11px;height:11px;border-radius:3px;flex:none}
.dom .nm{font-size:12px;flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.dom .ct{font-family:var(--mono);font-size:11px;color:var(--muted);font-variant-numeric:tabular-nums}
.edgetog{display:flex;gap:6px;margin-top:4px;flex-wrap:wrap}
.etg{flex:1 1 44%;font-size:10.5px;text-align:center;padding:5px 4px;border-radius:7px;cursor:pointer;
  border:1px solid var(--line2);background:var(--panel2);user-select:none;line-height:1.25}
.etg.dash{border-style:dashed}
.etg.off{opacity:.4}
.etg b{display:block;font-family:var(--mono);font-size:12px}
.hint{font-size:10.5px;color:var(--muted);line-height:1.5;padding:10px 2px 2px;border-top:1px solid var(--line);margin-top:10px}
.hint code{font-family:var(--mono);background:var(--panel2);padding:1px 4px;border-radius:4px}

/* ---- detail panel ---- */
.detail{position:fixed;top:72px;right:16px;z-index:15;width:300px;
  background:var(--panel);border:1px solid var(--line);border-radius:12px;
  box-shadow:0 8px 30px var(--shadow);overflow:hidden;
  display:none;flex-direction:column;max-height:calc(100vh - 92px)}
.detail.on{display:flex}
.dhead{padding:14px 14px 12px;border-bottom:1px solid var(--line);position:relative}
.dhead .stripe{position:absolute;left:0;top:0;bottom:0;width:4px}
.dhead .dom-lbl{font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted)}
.dhead h2{font-family:var(--mono);font-size:15px;margin:3px 0 8px;word-break:break-all}
.chips{display:flex;gap:6px;flex-wrap:wrap}
.chip{font-family:var(--mono);font-size:10.5px;background:var(--panel2);border:1px solid var(--line2);
  border-radius:6px;padding:2px 7px;color:var(--muted);font-variant-numeric:tabular-nums}
.dbody{overflow-y:auto;padding:4px 0 10px}
.rel-t{font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);padding:12px 14px 5px}
.rel{display:block;padding:6px 14px;cursor:pointer;border-left:2px solid transparent}
.rel:hover{background:var(--panel2);border-left-color:var(--accent)}
.rel .r1{display:flex;align-items:baseline;gap:7px}
.rel .r2{display:flex;align-items:baseline;gap:7px;flex-wrap:wrap;margin-top:2px}
.rel .to{font-family:var(--mono);font-size:12px;flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.rel .via{font-family:var(--mono);font-size:10px;color:var(--muted);word-break:break-all}
.rel .meta{font-size:9.5px;color:var(--muted)}
.rel .kb{font-size:9px;font-family:var(--mono);padding:1px 5px;border-radius:4px;flex:none}
.cardb{font-family:var(--mono);font-size:9px;padding:1px 5px;border-radius:4px;flex:none;
  background:var(--panel2);border:1px solid var(--line2);color:var(--muted)}
.opt{font-style:italic}
/* rules block */
.rule{padding:5px 14px;line-height:1.55}
.rule .rt{font-size:9px;font-family:var(--mono);padding:0 4px;border-radius:3px;margin-right:6px;
  background:var(--panel2);border:1px solid var(--line2);color:var(--muted)}
.rule .rc{font-family:var(--mono);font-size:11px}
.rule .rv{font-family:var(--mono);font-size:10px;color:var(--muted);word-break:break-word}
.cols{padding:2px 14px 8px;font-family:var(--mono);font-size:10.5px;color:var(--muted);
  word-break:break-word;line-height:1.75}
.kb.fk{background:color-mix(in srgb,var(--accent) 22%,transparent);color:var(--accent)}
.kb.impl{background:color-mix(in srgb,#E0A458 26%,transparent);color:#E0A458;border:1px dashed #E0A458}
.close{position:absolute;top:12px;right:12px;cursor:pointer;color:var(--muted);
  font-size:18px;line-height:1;width:22px;height:22px;text-align:center;border-radius:6px}
.close:hover{background:var(--panel2);color:var(--ink)}
.empty{color:var(--muted);font-size:11px;padding:2px 14px 8px;font-style:italic}

/* ---- canvas + tooltip ---- */
canvas{position:fixed;inset:0;z-index:1;display:block;touch-action:none}
.tip{position:fixed;z-index:30;pointer-events:none;background:var(--panel);border:1px solid var(--line2);
  border-radius:7px;padding:6px 9px;font-family:var(--mono);font-size:11px;box-shadow:0 4px 14px var(--shadow);
  display:none;white-space:nowrap}
.tip b{font-size:12px}.tip small{color:var(--muted)}
.zoombar{position:fixed;bottom:16px;left:16px;z-index:15;display:flex;gap:6px}
.zb{width:34px;height:34px;background:var(--panel);border:1px solid var(--line);border-radius:8px;
  color:var(--ink);font-size:17px;cursor:pointer;box-shadow:0 4px 14px var(--shadow);
  display:flex;align-items:center;justify-content:center}
.zb:hover{border-color:var(--accent)}
.zb.wide{width:auto;padding:0 12px;font-size:12px;font-family:var(--font)}
@media (max-width:720px){ .rail{display:none} .detail{width:calc(100vw - 32px)} }
</style>

<header>
  <div class="brand">
    <h1>__TITLE__</h1>
    <span class="sub" id="subline">__SUBTITLE__</span>
  </div>
  <div class="stats" id="stats"></div>
</header>

<div class="rail">
  <div class="pad">
    <input class="search" id="search" placeholder="buscar entidad…" autocomplete="off" spellcheck="false">
    <div class="sec-t">Relaciones</div>
    <div class="edgetog" id="edgetog"></div>
    <div class="sec-t row"><span>__LEGEND_TITLE__</span><span><button class="mini" id="dom-all">todos</button><span class="sep">·</span><button class="mini" id="dom-none">ninguno</button></span></div>
    <div class="legend" id="legend"></div>
    <div class="hint">
      <b>click</b> un nodo para ver sus relaciones · <b>arrastra</b> para fijarlo ·
      rueda para <b>zoom</b> · fondo para desplazar.<br>
      __HINT__
    </div>
  </div>
</div>

<div class="detail" id="detail">
  <div class="dhead">
    <div class="stripe" id="d-stripe"></div>
    <div class="close" id="d-close">×</div>
    <div class="dom-lbl" id="d-dom"></div>
    <h2 id="d-name"></h2>
    <div class="chips" id="d-chips"></div>
  </div>
  <div class="dbody" id="d-body"></div>
</div>

<div class="tip" id="tip"></div>
<div class="zoombar">
  <div class="zb" id="z-in">+</div>
  <div class="zb" id="z-out">−</div>
  <div class="zb wide" id="z-fit">ajustar</div>
</div>

<canvas id="cv"></canvas>

<script>
const GRAPH = __DATA__;
const COL = __COLORS__;
const RED = matchMedia('(prefers-reduced-motion:reduce)').matches;

// ---- model ----
const nodes = GRAPH.nodes.map(n=>({...n}));
const byId = new Map(nodes.map(n=>[n.id,n]));
const edges = GRAPH.edges.map(e=>({...e, s:byId.get(e.source), t:byId.get(e.target)})).filter(e=>e.s&&e.t);
const DOMS = GRAPH.meta.groups;
const adj = new Map(nodes.map(n=>[n.id,[]]));
edges.forEach(e=>{ adj.get(e.source).push(e); if(e.target!==e.source) adj.get(e.target).push(e); });

const state = { domOff:new Set(GRAPH.meta.groups_off||[]), ekOff:new Set(), sel:null, hover:null, query:"" };

// ---- header stats ----
const m = GRAPH.meta;
document.getElementById('stats').innerHTML = __STATS__
  .map(([l,v])=>`<div class="stat"><b>${v}</b><span>${l}</span></div>`).join('');

// edge-kind toggles, generated from the kinds this graph actually has
const DASH = new Set(m.edge_kinds.filter(k=>k.dash).map(k=>k.k));
document.getElementById('edgetog').innerHTML = m.edge_kinds
  .map(k=>`<div class="etg${k.dash?' dash':''}" data-ek="${k.k}"><b>${k.n}</b>${k.label}</div>`).join('');

// ---- legend ----
const domCounts={}; nodes.forEach(n=>domCounts[n.group]=(domCounts[n.group]||0)+1);
const legend=document.getElementById('legend');
const domsShown=Object.keys(DOMS).filter(d=>domCounts[d]).sort((a,b)=>domCounts[b]-domCounts[a]);
function syncLegend(){ legend.querySelectorAll('.dom').forEach(el=>
  el.classList.toggle('off', state.domOff.has(el.dataset.dom))); }
domsShown.forEach(d=>{
  const el=document.createElement('div'); el.className='dom'; el.dataset.dom=d;
  el.innerHTML=`<span class="dot" style="background:${COL[d]}"></span><span class="nm">${DOMS[d]}</span><span class="ct">${domCounts[d]}</span>`;
  el.onclick=()=>{ if(state.domOff.has(d)){state.domOff.delete(d);}
    else{state.domOff.add(d);} syncLegend(); draw(); };
  el.ondblclick=()=>{ // isolate this domain (solo); dbl-click again to restore all
    const soloed = domsShown.every(x=> x===d ? !state.domOff.has(x) : state.domOff.has(x));
    state.domOff = new Set(soloed ? [] : domsShown.filter(x=>x!==d));
    syncLegend(); draw(); };
  legend.appendChild(el);
});
syncLegend();   // reflect any classes this profile folds away on open
document.getElementById('dom-all').onclick=()=>{ state.domOff.clear(); syncLegend(); draw(); };
document.getElementById('dom-none').onclick=()=>{ state.domOff=new Set(domsShown); syncLegend(); draw(); };
document.querySelectorAll('.etg').forEach(el=>{
  el.onclick=()=>{ const k=el.dataset.ek;
    if(state.ekOff.has(k)){state.ekOff.delete(k);el.classList.remove('off');}
    else{state.ekOff.add(k);el.classList.add('off');} draw(); };
});
const nodeVisible=n=>!state.domOff.has(n.group);
const edgeVisible=e=>!state.ekOff.has(e.kind)&&nodeVisible(e.s)&&nodeVisible(e.t);

// ---- layout: seed by domain cluster ----
const domList=Object.keys(DOMS);
nodes.forEach(n=>{
  const di=domList.indexOf(n.group), a=di/domList.length*Math.PI*2;
  const r=180+Math.random()*120;
  n.x=Math.cos(a)*r + (Math.random()-.5)*80;
  n.y=Math.sin(a)*r + (Math.random()-.5)*80;
  n.vx=0; n.vy=0; n.pinned=false;
  n.rad=5+Math.sqrt(n.degree)*2.4;
});
// ---- force sim ----
let alpha=1;
const MAXV=32, FMAX=45;              // velocity + force caps keep the sim stable
function tick(){
  const k=alpha;
  for(let i=0;i<nodes.length;i++){
    const a=nodes[i];
    for(let j=i+1;j<nodes.length;j++){
      const b=nodes[j]; let dx=a.x-b.x, dy=a.y-b.y; let d2=dx*dx+dy*dy;
      if(d2>90000) continue;
      if(d2<36) d2=36;               // floor distance so close pairs don't explode
      const d=Math.sqrt(d2);
      const f=Math.min(1500/d2,FMAX)*k;
      const fx=dx/d*f, fy=dy/d*f; a.vx+=fx;a.vy+=fy;b.vx-=fx;b.vy-=fy;
    }
    a.vx-=a.x*0.01*k; a.vy-=a.y*0.01*k; // gravity to center
  }
  for(const e of edges){
    const a=e.s,b=e.t; let dx=b.x-a.x, dy=b.y-a.y; let d=Math.hypot(dx,dy)||1;
    const L=64+(a.rad+b.rad); const f=(d-L)*0.05*k; const fx=dx/d*f, fy=dy/d*f;
    a.vx+=fx;a.vy+=fy;b.vx-=fx;b.vy-=fy;
  }
  for(const n of nodes){ if(n.pinned){n.vx=0;n.vy=0;continue;}
    n.vx=Math.max(-MAXV,Math.min(MAXV,n.vx)); n.vy=Math.max(-MAXV,Math.min(MAXV,n.vy));
    if(!Number.isFinite(n.vx))n.vx=0; if(!Number.isFinite(n.vy))n.vy=0;
    n.x+=n.vx; n.y+=n.vy; n.vx*=0.8; n.vy*=0.8; }
  alpha*=0.985; if(alpha<0.02) alpha=0.02;
}

// ---- view transform ----
const cv=document.getElementById('cv'), ctx=cv.getContext('2d');
let DPR=1, view={x:0,y:0,s:1};
function resize(){ DPR=Math.min(devicePixelRatio||1,2);
  // A <canvas> is a replaced element: position:fixed+inset:0 does NOT stretch it,
  // it keeps its intrinsic (attribute) size as CSS size. Pin the CSS size to the
  // viewport explicitly so screen = view.s*world + view.x (no stray DPR factor),
  // which is what the zoom/pick math assumes.
  cv.style.width=innerWidth+'px'; cv.style.height=innerHeight+'px';
  cv.width=Math.round(innerWidth*DPR); cv.height=Math.round(innerHeight*DPR); draw(); }
addEventListener('resize',resize);
function toScreen(p){ return {x:(p.x*view.s+view.x)*DPR, y:(p.y*view.s+view.y)*DPR}; }
function toWorld(sx,sy){ return {x:(sx*DPR/DPR-view.x)/view.s, y:(sy*DPR/DPR-view.y)/view.s}; }

function fit(){
  const vis=nodes.filter(n=>nodeVisible(n)&&Number.isFinite(n.x)&&Number.isFinite(n.y)); if(!vis.length) return;
  let x0=1e9,y0=1e9,x1=-1e9,y1=-1e9;
  vis.forEach(n=>{x0=Math.min(x0,n.x);y0=Math.min(y0,n.y);x1=Math.max(x1,n.x);y1=Math.max(y1,n.y);});
  // inset the fit for the fixed UI chrome so the graph centers in the *visible* area
  const railW = innerWidth>720 ? 268 : 16;   // left rail + margin
  const topH = 72, padR = 28, padB = 24;
  const availW = Math.max(innerWidth - railW - padR, 120);
  const availH = Math.max(innerHeight - topH - padB, 120);
  const s=Math.min(availW/(x1-x0||1), availH/(y1-y0||1), 2.0);
  view.s=Math.max(s,0.25);
  const cx=(x0+x1)/2, cy=(y0+y1)/2;
  view.x = railW + availW/2 - cx*view.s;   // center within the visible band
  view.y = topH  + availH/2 - cy*view.s;
}

// ---- draw ----
function css(v){ return getComputedStyle(document.documentElement).getPropertyValue(v).trim(); }
function draw(){
  const cvbg=css('--canvas'), line=css('--line'), ink=css('--ink'), muted=css('--muted'), panel=css('--panel');
  ctx.setTransform(1,0,0,1,0,0); ctx.fillStyle=cvbg; ctx.fillRect(0,0,cv.width,cv.height);
  ctx.setTransform(DPR,0,0,DPR,0,0);
  ctx.translate(view.x,view.y); ctx.scale(view.s,view.s);

  const sel=state.sel;
  const neigh=new Set();
  if(sel){ neigh.add(sel.id); adj.get(sel.id).forEach(e=>{neigh.add(e.source);neigh.add(e.target);}); }

  // edges
  for(const e of edges){
    if(!edgeVisible(e)) continue;
    const hot = sel && (e.source===sel.id||e.target===sel.id);
    if(sel && !hot){ ctx.globalAlpha=0.06; } else { ctx.globalAlpha= sel?0.9:0.34; }
    ctx.beginPath(); ctx.moveTo(e.s.x,e.s.y); ctx.lineTo(e.t.x,e.t.y);
    ctx.strokeStyle = hot ? (COL[e.s.group]||line) : line;
    ctx.lineWidth = (hot?1.8:0.8)/view.s;
    if(DASH.has(e.kind)){ ctx.setLineDash([5/view.s,4/view.s]); } else { ctx.setLineDash([]); }
    ctx.stroke();
    // arrow head for hot edges
    if(hot){ const dx=e.t.x-e.s.x,dy=e.t.y-e.s.y,d=Math.hypot(dx,dy)||1;
      const ux=dx/d,uy=dy/d; const bx=e.t.x-ux*(e.t.rad+2), by=e.t.y-uy*(e.t.rad+2); const a=7/view.s;
      ctx.beginPath(); ctx.moveTo(bx,by);
      ctx.lineTo(bx-ux*a-uy*a*0.6, by-uy*a+ux*a*0.6);
      ctx.lineTo(bx-ux*a+uy*a*0.6, by-uy*a-ux*a*0.6);
      ctx.closePath(); ctx.fillStyle=COL[e.s.group]||line; ctx.fill(); }
  }
  ctx.setLineDash([]); ctx.globalAlpha=1;

  // nodes
  for(const n of nodes){
    if(!nodeVisible(n)) continue;
    const dim = sel && !neigh.has(n.id);
    const isSel = sel && n.id===sel.id;
    const q = state.query && n.disp.toLowerCase().includes(state.query);
    ctx.globalAlpha = dim?0.18:1;
    ctx.beginPath(); ctx.arc(n.x,n.y,n.rad,0,7);
    ctx.fillStyle=COL[n.group]||muted; ctx.fill();
    ctx.lineWidth=(isSel?2.6:1.1)/view.s;
    ctx.strokeStyle=isSel?ink:(q?css('--accent'):'rgba(0,0,0,.35)');
    if(q&&!isSel) ctx.lineWidth=2.4/view.s;
    ctx.stroke();
    // label
    const showLabel = !dim && (isSel || n===state.hover || n.degree>=4 || q || (neigh.has(n.id)&&sel) || view.s>1.1);
    if(showLabel){
      const fs=Math.max(10, 11)/view.s;
      ctx.font=`${fs}px ${css('--mono')||'monospace'}`;
      const tw=ctx.measureText(n.disp).width;
      const ty=n.y+n.rad+fs*1.15;
      ctx.globalAlpha=dim?0.2:0.92;
      ctx.fillStyle=panel; ctx.fillRect(n.x-tw/2-2/view.s, ty-fs*0.85, tw+4/view.s, fs*1.15);
      ctx.fillStyle=isSel?ink:muted;
      ctx.textAlign='center'; ctx.textBaseline='alphabetic';
      ctx.fillText(n.disp, n.x, ty);
    }
  }
  ctx.globalAlpha=1;
}

// ---- animation ----
// Settle the layout synchronously up front so the initial view is static — a
// drifting graph under the cursor is what makes zoom feel un-anchored. After
// settling the loop only runs while the user is interacting, then self-stops.
let running=false;
function loop(){ if(running){ for(let i=0;i<2;i++) tick(); draw(); if(alpha<=0.021) running=false; } requestAnimationFrame(loop); }
for(let i=0;i<340;i++) tick();
alpha=0.02;
fit(); resize();
requestAnimationFrame(loop);

// ---- picking ----
function pick(sx,sy){ const w=toWorld(sx,sy); let best=null,bd=1e9;
  for(const n of nodes){ if(!nodeVisible(n))continue; const d=Math.hypot(n.x-w.x,n.y-w.y);
    if(d<n.rad+4/view.s && d<bd){bd=d;best=n;} } return best; }

// ---- interaction ----
let drag=null, panning=false, last=null, moved=false;
cv.addEventListener('pointerdown',ev=>{
  const n=pick(ev.clientX,ev.clientY); moved=false;
  if(n){ drag=n; n.pinned=true; running=true; alpha=Math.max(alpha,0.3); }
  else { panning=true; last={x:ev.clientX,y:ev.clientY}; }
  cv.setPointerCapture(ev.pointerId);
});
cv.addEventListener('pointermove',ev=>{
  if(drag){ const w=toWorld(ev.clientX,ev.clientY); drag.x=w.x; drag.y=w.y; moved=true; if(running)0; else draw(); }
  else if(panning){ view.x+=ev.clientX-last.x; view.y+=ev.clientY-last.y; last={x:ev.clientX,y:ev.clientY}; moved=true; draw(); }
  else { const n=pick(ev.clientX,ev.clientY); const tip=document.getElementById('tip');
    if(n!==state.hover){ state.hover=n; if(!running)draw(); }
    if(n){ tip.style.display='block'; tip.style.left=(ev.clientX+12)+'px'; tip.style.top=(ev.clientY+12)+'px';
      const sub = n.rows!==undefined
        ? `${n.kind} · ~${n.rows.toLocaleString()} filas · ${n.degree} conexiones`
        : `${(n.name&&n.name!==n.disp)?n.name+' · ':''}${n.degree} conexiones`;
      tip.innerHTML=`<b>${n.disp}</b> <small>· ${DOMS[n.group]}</small><br><small>${sub}</small>`;
      cv.style.cursor='pointer'; }
    else { tip.style.display='none'; cv.style.cursor='grab'; } }
});
cv.addEventListener('pointerup',ev=>{
  if(drag && !moved){ select(drag); }
  else if(panning && !moved){ select(null); }
  drag=null; panning=false;
  if(!RED && alpha>0.05) running=true;   // loop self-stops once it settles
});
cv.addEventListener('wheel',ev=>{ ev.preventDefault();
  const f=ev.deltaY<0?1.12:0.893; const mx=ev.clientX,my=ev.clientY;
  const wx=(mx-view.x)/view.s, wy=(my-view.y)/view.s;
  view.s=Math.max(0.15,Math.min(4,view.s*f));
  view.x=mx-wx*view.s; view.y=my-wy*view.s; draw();
},{passive:false});

document.getElementById('z-in').onclick=()=>zoomStep(1.2);
document.getElementById('z-out').onclick=()=>zoomStep(1/1.2);
document.getElementById('z-fit').onclick=()=>{fit();draw();};
function zoomStep(f){ const mx=innerWidth/2,my=innerHeight/2;
  const wx=(mx-view.x)/view.s, wy=(my-view.y)/view.s; view.s=Math.max(0.15,Math.min(4,view.s*f));
  view.x=mx-wx*view.s; view.y=my-wy*view.s; draw(); }

// ---- selection + detail panel ----
function select(n){ state.sel=n; renderDetail(); draw(); }
const dp=document.getElementById('detail');
document.getElementById('d-close').onclick=()=>select(null);
function renderDetail(){
  const n=state.sel; if(!n){ dp.classList.remove('on'); return; }
  dp.classList.add('on');
  document.getElementById('d-stripe').style.background=COL[n.group];
  document.getElementById('d-dom').textContent=DOMS[n.group];
  document.getElementById('d-name').textContent=n.disp;
  const esc=s=>String(s).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
  const chips=[];
  if(n.rows!==undefined){                      // data layer
    chips.push(`${n.kind}`,`~${n.rows.toLocaleString()} filas`,`${n.cols} columnas`,`${n.degree} conexiones`);
    if(n.pk) chips.push(`pk ${n.pk}`);
  } else {                                     // concept layer
    if(n.verb) chips.push(n.verb);
    if(n.sop) chips.push(`SOP ${n.sop}`);
    if(n.macro) chips.push(`macro ${n.macro}`);
    if(n.chain_order) chips.push(`paso ${n.chain_order} de la cadena`);
    if(n.tasks!==undefined) chips.push(`${n.tasks} tarea${n.tasks===1?'':'s'}`);
    if(n.open_tasks!==undefined) chips.push(`${n.open_tasks} abiertas`);
    if(n.people!==undefined) chips.push(`${n.people} persona${n.people===1?'':'s'}`);
    if(n.category) chips.push(n.category);
    if(n.is_gate) chips.push('gate');
    chips.push(`${n.degree} conexiones`);
  }
  document.getElementById('d-chips').innerHTML=chips.map(c=>`<span class="chip">${esc(c)}</span>`).join('');
  const out=adj.get(n.id).filter(e=>e.source===n.id);
  const inc=adj.get(n.id).filter(e=>e.target===n.id && e.source!==n.id);
  const KL={}; m.edge_kinds.forEach(k=>KL[k.k]=k.label);
  const row=e=>{ const other=e.source===n.id?e.t:e.s;
    const bits=[];
    if(e.card) bits.push(e.optional?'<span class="opt">opcional</span>':'obligatoria');
    if(e.on_delete && e.on_delete!=='no action' && e.on_delete!=='—') bits.push('on delete '+esc(e.on_delete));
    if(e.verified) bits.push(`resuelve ${e.verified.matched}/${e.verified.total} (${e.verified.pct}%)`);
    if(e.tasks) bits.push(`${e.tasks} tarea${e.tasks===1?'':'s'}`);
    if(e.required) bits.push('requerido');
    if(e.note && !e.verified) bits.push(esc(e.note));
    const right = e.card || (e.tasks?`×${e.tasks}`:'');
    return `<div class="rel" data-go="${other.id}">
      <div class="r1">
        <span class="kb ${DASH.has(e.kind)?'impl':'fk'}">${esc(e.kind==='fk'?'FK':(KL[e.kind]||e.kind))}</span>
        <span class="to" style="color:${COL[other.group]}">${esc(other.disp)}</span>
        ${right?`<span class="cardb">${esc(right)}</span>`:''}
      </div>
      <div class="r2"><span class="via">${esc(other.name&&other.name!==other.disp?other.name:e.label)}</span>
        ${bits.length?`<span class="meta">${bits.join(' · ')}</span>`:''}</div></div>`; };
  let html='';
  if(n.name && n.name!==n.disp) html+=`<div class="cols" style="padding-top:10px">${esc(n.name)}</div>`;
  html+=`<div class="rel-t">Apunta a → (${out.length})</div>`;
  html+= out.length? out.map(row).join('') : `<div class="empty">no apunta a nada</div>`;
  html+=`<div class="rel-t">← Referenciada por (${inc.length})</div>`;
  html+= inc.length? inc.map(row).join('') : `<div class="empty">nada la referencia</div>`;

  // rules: enums, CHECK (incl. the check-as-enum idiom) and unique constraints
  const enums=n.enums||[], checks=n.checks||[], uniq=n.uniques||[];
  const nRules=enums.length+checks.length+uniq.length;
  if(nRules){
    html+=`<div class="rel-t">Reglas (${nRules})</div>`;
    enums.forEach(en=>{ html+=`<div class="rule"><span class="rt">enum</span><span class="rc">${esc(en.col)}</span>
      <div class="rv">${en.values.map(esc).join(' · ')}</div></div>`; });
    checks.forEach(ck=>{ html+= ck.type==='allowed_values'
      ? `<div class="rule"><span class="rt">check</span><span class="rc">${esc(ck.col)}</span>
         <div class="rv">${ck.values.map(esc).join(' · ')}</div></div>`
      : `<div class="rule"><span class="rt">check</span><span class="rv">${esc(ck.expr)}</span></div>`; });
    uniq.forEach(u=>{ html+=`<div class="rule"><span class="rt">único</span><span class="rv">${u.cols.map(esc).join(', ')}</span></div>`; });
  }
  // columns that can hide relations no FK enforces
  const js=n.jsonb||[], ar=n.arrays||[];
  if(js.length||ar.length){
    html+=`<div class="rel-t">Columnas semiestructuradas</div><div class="cols">`;
    if(js.length) html+=`jsonb: ${js.map(esc).join(' · ')}<br>`;
    if(ar.length) html+=`array: ${ar.map(a=>esc(a.col)+'['+esc(a.of)+']').join(' · ')}`;
    html+=`</div>`;
  }
  const body=document.getElementById('d-body'); body.innerHTML=html;
  body.querySelectorAll('.rel').forEach(r=>r.onclick=()=>{ const g=byId.get(r.dataset.go); if(g){select(g);centerOn(g);} });
}
function centerOn(n){ view.x=innerWidth/2-n.x*view.s; view.y=innerHeight*0.5-n.y*view.s; draw(); }

// ---- search ----
document.getElementById('search').addEventListener('input',ev=>{
  state.query=ev.target.value.trim().toLowerCase();
  if(state.query){ const hit=nodes.find(n=>n.disp.toLowerCase()===state.query)||nodes.find(n=>(n.disp+' '+(n.name||'')).toLowerCase().includes(state.query));
    if(hit && ev.inputType==null){} }
  draw();
});
document.getElementById('search').addEventListener('keydown',ev=>{
  if(ev.key==='Enter'){ const hit=nodes.find(n=>(n.disp+' '+(n.name||'')).toLowerCase().includes(state.query)); if(hit){select(hit);centerOn(hit);} }
});
</script>
"""

out = (HTML.replace("__DATA__", DATA).replace("__COLORS__", CJSON)
           .replace("__STATS__", SJSON)
           .replace("__TITLE__", P["title"]).replace("__SUBTITLE__", P["subtitle"])
           .replace("__LEGEND_TITLE__", P["legend_title"]).replace("__HINT__", P["hint"]))
leftover = [t for t in ("__DATA__","__COLORS__","__STATS__","__TITLE__","__SUBTITLE__",
                        "__LEGEND_TITLE__","__HINT__") if t in out]
if leftover:
    sys.exit(f"placeholders sin reemplazar: {leftover}")
path = os.path.join(D, OUTFILE)
with open(path, "w") as f:
    f.write(out)
print(f"wrote {path} ({len(out)} bytes) · perfil={PROFILE} · "
      f"{len(graph['nodes'])} nodos / {len(graph['edges'])} aristas")
