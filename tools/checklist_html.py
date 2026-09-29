"""Render docs/BETA-DAY.md as a standalone HTML page with tickable boxes (saved in the browser).

    python3 tools/checklist_html.py docs/BETA-DAY.md ~/Desktop/ForeverAddons/Beta-day-checklist.html
"""
import html
import re
import sys

CSS = """
:root{--bg:#F6EFE3;--card:#FFFBF3;--ink:#2A2233;--soft:#5E5468;--line:#DCCFB4;--gold:#9A7432;--accent:#14708F;--done:#8C8496;--codebg:#EFE4CB;--quote:#F0E5CE;color-scheme:light}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#232244;--card:#2C2B4E;--ink:#F1E9D8;--soft:#C4BBD2;--line:#3F3E68;--gold:#D9B96A;--accent:#3FC2E6;--done:#8C8496;--codebg:#3A3962;--quote:#2F2E56;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#232244;--card:#2C2B4E;--ink:#F1E9D8;--soft:#C4BBD2;--line:#3F3E68;--gold:#D9B96A;--accent:#3FC2E6;--done:#8C8496;--codebg:#3A3962;--quote:#2F2E56;color-scheme:dark}
body{margin:0;background:var(--bg);color:var(--ink);font:17px/1.55 "Source Sans 3","Segoe UI",system-ui,sans-serif}
.wrap{width:min(860px,calc(100% - 36px));margin:0 auto;padding:32px 0 64px}
h1{font-family:Cinzel,Georgia,serif;letter-spacing:.03em;font-size:1.8rem;margin:0 0 8px;text-wrap:balance}
h2{font-family:Cinzel,Georgia,serif;letter-spacing:.03em;font-size:1.2rem;color:var(--gold);margin:34px 0 10px}
p{margin:0 0 12px;max-width:65ch}
.lead{color:var(--soft)}
ul.checks{list-style:none;margin:0 0 12px;padding:0;display:grid;gap:6px}
ul.checks>li>label{display:grid;grid-template-columns:22px 1fr;gap:10px;align-items:start;background:var(--card);border:1px solid var(--line);border-radius:6px;padding:9px 12px;cursor:pointer}
ul.checks input{width:18px;height:18px;margin:3px 0 0;accent-color:var(--accent)}
ul.checks li.done>label>span{color:var(--done);text-decoration:line-through}
ul.sub{margin:6px 0 2px;padding-left:1.1em;display:grid;gap:3px;color:var(--soft)}
ol{margin:0 0 12px;padding-left:1.4em;display:grid;gap:4px}
code{font-family:"JetBrains Mono",ui-monospace,Menlo,monospace;font-size:.86em;background:var(--codebg);border-radius:4px;padding:1px 5px;overflow-wrap:anywhere}
blockquote{margin:0 0 12px;background:var(--quote);border:1px solid var(--line);border-radius:6px;padding:12px 16px}
blockquote p{margin:0 0 8px}
blockquote p:last-child{margin:0}
.bar{display:flex;gap:12px;align-items:center;justify-content:space-between;flex-wrap:wrap;margin:14px 0 0;color:var(--soft);font-size:.95rem}
button{font:inherit;background:var(--card);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:5px 12px;cursor:pointer}
button:focus-visible,input:focus-visible{outline:3px solid var(--accent);outline-offset:2px}
"""

JS = """
(function(){
  var KEY='foreverbuddy-beta-checklist';
  var state={};
  try{state=JSON.parse(localStorage.getItem(KEY)||'{}')}catch(e){state={}}
  var boxes=[].slice.call(document.querySelectorAll('ul.checks input'));
  function paint(){
    var done=0;
    boxes.forEach(function(b){var on=!!state[b.id];b.checked=on;b.closest('li').classList.toggle('done',on);if(on)done++});
    document.getElementById('progress').textContent=done+' of '+boxes.length+' done';
  }
  boxes.forEach(function(b){b.addEventListener('change',function(){state[b.id]=b.checked;try{localStorage.setItem(KEY,JSON.stringify(state))}catch(e){}paint()})});
  document.getElementById('reset').addEventListener('click',function(){state={};try{localStorage.removeItem(KEY)}catch(e){}paint()});
  paint();
})();
"""


def inline(text):
    parts = re.split(r"(`[^`]+`)", text)
    out = []
    for part in parts:
        if part.startswith("`") and part.endswith("`"):
            out.append("<code>%s</code>" % html.escape(part[1:-1]))
        else:
            s = html.escape(part)
            s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
            out.append(s)
    return "".join(out)


def render(md):
    lines = md.splitlines()
    body, title, i, box = [], "Checklist", 0, 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("# "):
            title = line[2:].strip()
            body.append("<h1>%s</h1>" % inline(title))
            i += 1
        elif line.startswith("## "):
            body.append("<h2>%s</h2>" % inline(line[3:].strip()))
            i += 1
        elif line.startswith("- [ ] "):
            body.append('<ul class="checks">')
            while i < len(lines) and lines[i].startswith("- [ ] "):
                box += 1
                item = inline(lines[i][6:])
                i += 1
                subs = []
                while i < len(lines) and lines[i].startswith("  - "):
                    subs.append("<li>%s</li>" % inline(lines[i][4:]))
                    i += 1
                sub = ('<ul class="sub">%s</ul>' % "".join(subs)) if subs else ""
                body.append('<li><label><input type="checkbox" id="c%d"><span>%s%s</span></label></li>' % (box, item, sub))
            body.append("</ul>")
        elif re.match(r"^\d+\. ", line):
            body.append("<ol>")
            while i < len(lines) and re.match(r"^\d+\. ", lines[i]):
                body.append("<li>%s</li>" % inline(re.sub(r"^\d+\. ", "", lines[i])))
                i += 1
            body.append("</ol>")
        elif line.startswith(">"):
            paras, cur = [], []
            while i < len(lines) and lines[i].startswith(">"):
                t = lines[i][1:].strip()
                if t:
                    cur.append(t)
                elif cur:
                    paras.append(" ".join(cur)); cur = []
                i += 1
            if cur:
                paras.append(" ".join(cur))
            body.append("<blockquote>%s</blockquote>" % "".join("<p>%s</p>" % inline(p) for p in paras))
        elif line.strip():
            cls = ' class="lead"' if len(body) == 1 else ""
            body.append("<p%s>%s</p>" % (cls, inline(line.strip())))
            i += 1
        else:
            i += 1
    body.insert(2, '<div class="bar"><span id="progress"></span><button type="button" id="reset">Clear all ticks</button></div>')
    return title, "\n".join(body)


def main(argv):
    src, dst = argv[1], argv[2]
    title, body = render(open(src, encoding="utf-8").read())
    page = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
            '<title>ForeverBuddy Beta Day</title>\n<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cinzel:wght@700&family=Source+Sans+3:wght@400;600;700&family=JetBrains+Mono:wght@400&display=swap">\n'
            '<style>%s</style>\n</head>\n<body>\n<div class="wrap">\n%s\n</div>\n<script>%s</script>\n</body>\n</html>\n') % (CSS, body, JS)
    open(dst, "w", encoding="utf-8").write(page)
    print("wrote %s (%s)" % (dst, title))


if __name__ == "__main__":
    main(sys.argv)
