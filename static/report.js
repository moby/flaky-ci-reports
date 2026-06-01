// report.js — client-side rendering + filtering for the dashboard.
//
// Both the live server and the static (GitHub Pages) export embed their data in
// a <script> block and call renderIndex()/renderGroup(); all period/day
// filtering happens here in the browser, so the static export needs no server
// and a page is one file per project / per error (no per-window HTML).
//
// window.FLAKIE_STATIC (set only in the static export) switches group links to
// the flat file layout and drops server-only affordances (log links).

(function () {
  'use strict';

  const CAT_COLORS = {
    test: '#dc2626', network: '#0284c7', dependency: '#d97706', other: '#94a3b8',
  };
  const catColor = (c) => CAT_COLORS[(c || 'other').toLowerCase()] || '#64748b';
  const catLabel = (c) => (c && c.trim()) ? c : 'other';

  // slug mirrors Go ui.groupSlug — stable, readable, hash-free.
  function slug(key) {
    let s = key.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
    if (!s) s = 'group';
    return s.length > 120 ? s.slice(0, 120) : s;
  }
  function groupHref(project, key) {
    return window.FLAKIE_STATIC ? `${project}-${slug(key)}.html` : `/g/${encodeURIComponent(key)}`;
  }

  const DAY = 86400;
  const nowSec = () => Math.floor(Date.now() / 1000);
  const dayStr = (t) => new Date(t * 1000).toISOString().slice(0, 10);
  const fmtDateTime = (t) => new Date(t * 1000).toISOString().slice(0, 16).replace('T', ' ');
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // chartWindow: the daily chart spans this many days (capped for "all time").
  const chartWindow = (days) => (days > 0 ? days : 90);

  // buildDailyStack returns a Chart.js config: one bar per day over the window,
  // stacked by category. rows: [{t, c}]. onDay(dayLabel|null) handles drill.
  function buildDailyStack(rows, days, selectedDay, onDay) {
    const span = chartWindow(days);
    const today = nowSec();
    const labels = [];
    const idx = {};
    for (let i = span - 1; i >= 0; i--) {
      const d = dayStr(today - i * DAY);
      idx[d] = labels.length;
      labels.push(d);
    }
    const per = {}; // category -> int[]
    const order = [];
    for (const r of rows) {
      const d = dayStr(r.t);
      if (!(d in idx)) continue;
      const cat = catLabel(r.c);
      if (!per[cat]) { per[cat] = new Array(span).fill(0); order.push(cat); }
      per[cat][idx[d]]++;
    }
    order.sort((a, b) => per[b].reduce((x, y) => x + y, 0) - per[a].reduce((x, y) => x + y, 0));
    const datasets = order.map((cat) => ({
      label: cat,
      data: per[cat],
      backgroundColor: selectedDay
        ? labels.map((d) => d === selectedDay ? catColor(cat) : fade(catColor(cat)))
        : catColor(cat),
      borderRadius: 2, maxBarThickness: 24, stack: 's',
    }));
    return {
      type: 'bar',
      data: { labels, datasets },
      options: {
        responsive: true, maintainAspectRatio: false,
        // Day-drill is pure client-side filtering now, so it works in the
        // static export too (no per-day pages, no server).
        onHover: (e, items) => { e.native.target.style.cursor = items.length ? 'pointer' : 'default'; },
        onClick: (e, items) => {
          if (!items.length) return;
          const d = labels[items[0].index];
          onDay(d === selectedDay ? null : d);
        },
        plugins: { legend: { display: false } },
        scales: {
          x: { stacked: true, grid: { display: false }, ticks: { color: '#64748b', font: { size: 10 } } },
          y: { stacked: true, beginAtZero: true, grid: { color: '#e2e8f0' }, ticks: { color: '#64748b', font: { size: 11 }, precision: 0 } },
        },
      },
    };
  }
  function fade(hex) {
    const n = parseInt(hex.slice(1), 16);
    return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},0.25)`;
  }

  function inWindow(t, days, selectedDay) {
    if (selectedDay) return dayStr(t) === selectedDay;
    return days <= 0 || t >= nowSec() - days * DAY;
  }

  // ---- Index ----------------------------------------------------------------

  window.renderIndex = function (d) {
    const rows = d.rows || [];
    const fixes = d.fixes || {};
    let days = 30, selectedDay = null, showFixed = false, chart = null;

    const tbody = document.getElementById('idx-tbody');
    const empty = document.getElementById('idx-empty');
    const canvas = document.getElementById('idx-chart').getContext('2d');

    function aggregate(rs) {
      const g = {};
      for (const r of rs) {
        let e = g[r.k];
        if (!e) { e = g[r.k] = { key: r.k, name: r.n, cat: r.c, hits: 0, first: r.t, last: r.t, wf: new Set(), br: new Set(), pr: new Set() }; }
        e.hits++;
        if (r.t < e.first) e.first = r.t;
        if (r.t > e.last) e.last = r.t;
        if (r.c && !e.cat) e.cat = r.c;
        if (r.w) e.wf.add(r.w);
        if (r.b) e.br.add(r.b);
        if (r.p) e.pr.add(r.p);
      }
      return Object.values(g).sort((a, b) => b.hits - a.hits || (a.key < b.key ? -1 : 1)).slice(0, 50);
    }

    function render() {
      // The chart always covers the whole window (selecting a day only fades the
      // other bars — it's how you pick/clear the day); the table narrows to the
      // selected day.
      const winRows = rows.filter((r) => inWindow(r.t, days, null));
      const listRows = selectedDay ? winRows.filter((r) => dayStr(r.t) === selectedDay) : winRows;
      // chart
      if (chart) chart.destroy();
      chart = new Chart(canvas, buildDailyStack(winRows, days, selectedDay, (dd) => { selectedDay = dd; render(); }));
      // table
      let groups = aggregate(listRows);
      let hidden = 0;
      const out = [];
      for (const e of groups) {
        const fx = fixes[e.key];
        const fixed = fx != null;
        const regressed = fixed && e.last > fx;
        if (fixed && !regressed && !showFixed) { hidden++; continue; }
        const badge = regressed
          ? '<span class="badge badge-regressed">regressed</span>'
          : (fixed ? `<span class="badge badge-fixed" title="fixed ${esc(dayStr(fx))}">fixed</span>` : '');
        out.push(`<tr class="${fixed && !regressed ? 'row-fixed' : ''}"><td>` +
          `<a class="key" href="${esc(groupHref(d.project, e.key))}">${esc(e.key)}</a>` +
          `<span class="cat-chip" style="background:${catColor(e.cat)}">${esc(catLabel(e.cat))}</span>${badge}` +
          `<div class="dim" style="margin-top:0.25rem">${esc(e.name)}</div></td>` +
          `<td class="num"><strong>${e.hits}</strong></td>` +
          `<td class="dim">${esc(fmtDateTime(e.first))}</td><td class="dim">${esc(fmtDateTime(e.last))}</td>` +
          `<td class="dim">${e.wf.size}</td><td class="dim">${e.br.size}</td></tr>`);
      }
      tbody.innerHTML = out.join('');
      empty.style.display = out.length ? 'none' : '';
      const sf = document.getElementById('idx-showfixed');
      if (sf) sf.textContent = showFixed ? 'hide fixed' : (hidden ? `show fixed (${hidden})` : 'show fixed');
      document.querySelectorAll('#idx-pills [data-days]').forEach((el) =>
        el.classList.toggle('active', +el.dataset.days === days && !selectedDay));
      const banner = document.getElementById('idx-day');
      if (banner) { banner.style.display = selectedDay ? '' : 'none'; banner.querySelector('strong').textContent = selectedDay || ''; }
    }

    document.querySelectorAll('#idx-pills [data-days]').forEach((el) =>
      el.addEventListener('click', (e) => { e.preventDefault(); days = +el.dataset.days; selectedDay = null; render(); }));
    const sf = document.getElementById('idx-showfixed');
    if (sf) sf.addEventListener('click', (e) => { e.preventDefault(); showFixed = !showFixed; render(); });
    const clr = document.getElementById('idx-day-clear');
    if (clr) clr.addEventListener('click', (e) => { e.preventDefault(); selectedDay = null; render(); });
    render();
  };

  // ---- Group detail ---------------------------------------------------------

  window.renderGroup = function (d) {
    const obs = d.obs || [];
    let days = 30, selectedDay = null, chart = null;
    const canvas = document.getElementById('g-chart').getContext('2d');

    function render() {
      // Chart spans the whole window (a selected day only fades the rest);
      // the stat, tag breakdown and list narrow to the selected day.
      const winRows = obs.filter((o) => inWindow(o.t, days, null));
      const rs = selectedDay ? winRows.filter((o) => dayStr(o.t) === selectedDay) : winRows;
      // chart (reuse the category stack; map obs -> {t,c})
      if (chart) chart.destroy();
      chart = new Chart(canvas, buildDailyStack(winRows.map((o) => ({ t: o.t, c: o.cat })), days, selectedDay,
        (dd) => { selectedDay = dd; render(); }));
      // window-hits stat (lifetime cards stay server-rendered)
      setText('g-window-hits', rs.length);
      const wl = document.getElementById('g-window-label');
      if (wl) wl.textContent = selectedDay ? selectedDay : (days > 0 ? days + 'd' : 'all');
      // tag breakdown
      renderTags(rs);
      // observations
      renderObs(rs);
      document.querySelectorAll('#g-pills [data-days]').forEach((el) =>
        el.classList.toggle('active', +el.dataset.days === days && !selectedDay));
      const banner = document.getElementById('g-day');
      if (banner) { banner.style.display = selectedDay ? '' : 'none'; banner.querySelector('strong').textContent = selectedDay || ''; }
    }

    // renderTags mirrors the markup of the old server-rendered breakdown so it
    // reuses the existing .tag-block / .bar-row CSS.
    function renderTags(rs) {
      const per = {}; // key -> {val -> count}
      let total = 0;
      for (const o of rs) {
        total++;
        for (const k in (o.tags || {})) {
          const v = o.tags[k]; (per[k] || (per[k] = {}))[v] = (per[k][v] || 0) + 1;
        }
      }
      const keys = Object.keys(per).sort((a, b) => (a === 'test' ? -1 : b === 'test' ? 1 : a < b ? -1 : 1));
      const out = keys.map((k) => {
        const vals = Object.entries(per[k]).sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1));
        const max = vals[0][1];
        let tagged = 0;
        for (const [, n] of vals) tagged += n;
        const rows = vals.map(([v, n]) =>
          `<div class="bar-row"><div class="label" title="${esc(v)}">${esc(v)}</div>` +
          `<div class="bar"><div style="width:${Math.round(n * 100 / max)}%;background:${tagColor(k)}"></div></div>` +
          `<div class="count">${n} <span style="color:var(--text-faint);font-size:0.75rem">(${Math.round(n * 100 / (total || 1))}%)</span></div></div>`).join('');
        return `<div class="tag-block" style="--tag-color:${tagColor(k)}">` +
          `<div style="display:flex;justify-content:space-between;align-items:baseline;margin-bottom:0.625rem">` +
          `<div class="tag-key">${esc(k)}</div>` +
          `<div class="tag-meta">${vals.length} value${vals.length === 1 ? '' : 's'}${tagged < total ? ` · ${tagged}/${total} tagged` : ''}</div></div>${rows}</div>`;
      });
      document.getElementById('g-tags').innerHTML = out.length ? out.join('') : '<div class="empty">No tags in this window.</div>';
    }

    function renderObs(rs) {
      const out = rs.map((o) => {
        const post = (d.fixedAt && o.t > d.fixedAt);
        const gh = o.url ? `<a href="${esc(o.url)}" target="_blank" rel="noopener">github ↗</a>` : '';
        // o.log is the server-built in-app log URL (already existence-checked);
        // omitted in the static export, where logs aren't published.
        const log = (!window.FLAKIE_STATIC && o.log) ? ` <a href="${esc(o.log)}">inspect log →</a>` : '';
        const tags = o.tags ? Object.entries(o.tags).map(([k, v]) =>
          `<span class="tag-chip"><span class="dot" style="background:${tagColor(k)}"></span><strong>${esc(k)}=</strong>${esc(v)}</span>`).join('') : '';
        return `<div class="obs${post ? ' obs-postfix' : ''}"><span class="when">${esc(fmtDateTime(o.t))}</span>` +
          `${post ? '<span class="badge badge-regressed" title="after the fix time">post-fix</span>' : ''}` +
          `<span class="cat-chip" style="background:${catColor(o.cat)}">${esc(catLabel(o.cat))}</span> ${gh}${log}` +
          `${o.job_name ? `<div class="job">${esc(o.job_name)}</div>` : ''}` +
          `${tags ? `<div class="tags">${tags}</div>` : ''}</div>`;
      });
      document.getElementById('g-obs').innerHTML = out.length ? out.join('') : '<div class="empty">No occurrences in this window.</div>';
    }

    document.querySelectorAll('#g-pills [data-days]').forEach((el) =>
      el.addEventListener('click', (e) => { e.preventDefault(); days = +el.dataset.days; selectedDay = null; render(); }));
    const clr = document.getElementById('g-day-clear');
    if (clr) clr.addEventListener('click', (e) => { e.preventDefault(); selectedDay = null; render(); });
    render();
  };

  function setText(id, v) { const el = document.getElementById(id); if (el) el.textContent = v; }
  const TAG_COLORS = { test: '#4f46e5', worker: '#d97706', frontend: '#059669', host: '#e11d48', status: '#0284c7', slice: '#7c3aed', reason: '#0f766e' };
  const tagColor = (k) => TAG_COLORS[k] || '#64748b';
})();
