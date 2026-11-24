/* Before You Sign online — ARPRA website.
   Uploads the buyer's documents to ARPRA's checking server, follows the check,
   shows the free summary, and handles the paid review request.

   Where the checking server lives. Change this one line if the server moves
   (for example to Azure): e.g. "https://bys.arpra.org.au". */
var BYS_SERVER = "/bys";

(function () {
  'use strict';
  var S = BYS_SERVER.replace(/\/$/, '');
  var DOCS = [
    { key: 'ds', title: 'Disclosure Statement', hint: 'The document the operator must give you at least 14 days before you sign.' },
    { key: 'rsa', title: 'Residential Site Agreement', hint: 'The agreement for the site, including any extra pages or schedules.' },
    { key: 'rules', title: 'Community Rules', hint: 'The rules of the community, if you have been given them.' },
    { key: 'home', title: 'Contract for the home', hint: 'The contract to buy or build the home, if separate.' }
  ];
  var MAX_IMAGES = 100, MAX_BYTES = 60 * 1024 * 1024, MAX_EDGE = 1568;
  var files = { ds: [], rsa: [], rules: [], home: [] };
  var cfg = { enabled: false };
  var turnstileId = null;
  var pollTimer = null;

  function $(id) { return document.getElementById(id); }
  function show(id, on) { var el = $(id); if (el) el.hidden = !on; }
  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML; }

  /* ---- Saved state (so the page survives the trip to Stripe) ---- */
  var KEY = 'arpraBysOnline';
  function load() { try { return JSON.parse(localStorage.getItem(KEY) || '{}'); } catch (e) { return {}; } }
  function save(st) { try { localStorage.setItem(KEY, JSON.stringify(st)); } catch (e) {} }
  var st = load();
  function hex(n) {
    var a = new Uint8Array(n); (window.crypto || window.msCrypto).getRandomValues(a);
    return Array.prototype.map.call(a, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }
  if (!st.device || !/^web-[a-f0-9]{32}$/.test(st.device)) { st.device = 'web-' + hex(16); save(st); }

  function api(path, opts) {
    opts = opts || {};
    opts.headers = Object.assign({ 'X-BYS-Device': st.device }, opts.headers || {});
    return fetch(S + '/' + path, opts).then(function (r) {
      return r.text().then(function (t) {
        var j = {}; try { j = JSON.parse(t); } catch (e) {}
        return { status: r.status, json: j };
      });
    });
  }

  /* ---- Step 1: documents ---- */
  function renderDocs() {
    var box = $('bys-docs'); box.innerHTML = '';
    DOCS.forEach(function (d) {
      var card = document.createElement('div'); card.className = 'bys-doc';
      card.innerHTML = '<h3>' + esc(d.title) + '</h3><p class="hint">' + esc(d.hint) + '</p>' +
        '<input class="bys-file-input" type="file" id="f-' + d.key + '-pdf" accept="application/pdf,.pdf" multiple>' +
        '<input class="bys-file-input" type="file" id="f-' + d.key + '-img" accept="image/*" multiple>' +
        '<div class="btn-row"><button type="button" class="btn btn-line btn-sm" data-pick="' + d.key + '-pdf">Add PDF file</button>' +
        '<button type="button" class="btn btn-line btn-sm" data-pick="' + d.key + '-img">Add photos</button></div>' +
        '<ul class="bys-files" id="list-' + d.key + '"></ul>';
      box.appendChild(card);
      card.querySelector('#f-' + d.key + '-pdf').addEventListener('change', function (e) { addFiles(d.key, e.target.files); e.target.value = ''; });
      card.querySelector('#f-' + d.key + '-img').addEventListener('change', function (e) { addFiles(d.key, e.target.files); e.target.value = ''; });
      renderList(d.key);
    });
    box.querySelectorAll('[data-pick]').forEach(function (b) {
      b.addEventListener('click', function () { $('f-' + b.dataset.pick).click(); });
    });
  }

  function renderList(key) {
    var ul = $('list-' + key); ul.innerHTML = '';
    var page = 0;
    files[key].forEach(function (f, i) {
      var li = document.createElement('li');
      var label = f.kind === 'pdf' ? 'PDF: ' + f.name : 'Photo, page ' + (++page);
      li.innerHTML = '<span>' + esc(label) + '</span>';
      var b = document.createElement('button'); b.type = 'button'; b.textContent = 'Remove';
      b.setAttribute('aria-label', 'Remove ' + label);
      b.addEventListener('click', function () { files[key].splice(i, 1); renderList(key); });
      li.appendChild(b); ul.appendChild(li);
    });
  }

  function addFiles(key, list) {
    var arr = Array.prototype.slice.call(list || []);
    var chain = Promise.resolve();
    arr.forEach(function (file) {
      chain = chain.then(function () {
        var isPdf = file.type === 'application/pdf' || /\.pdf$/i.test(file.name);
        if (isPdf) { files[key].push({ kind: 'pdf', name: file.name, blob: file }); return; }
        if (!/^image\//.test(file.type)) { uploadError('"' + file.name + '" is not a PDF or a photo, so it can\'t be checked.'); return; }
        return shrink(file).then(function (blob) { files[key].push({ kind: 'image', name: file.name, blob: blob }); })
          .catch(function () { uploadError('"' + file.name + '" could not be read. Try taking the photo again, or save it as a JPEG.'); });
      });
    });
    chain.then(function () { renderList(key); });
  }

  /* Photos are reduced to 1,568 pixels on the longest side (all the checker reads). */
  function shrink(file) {
    var make = window.createImageBitmap ? createImageBitmap(file) : new Promise(function (ok, bad) {
      var img = new Image(); img.onload = function () { ok(img); }; img.onerror = bad; img.src = URL.createObjectURL(file);
    });
    return make.then(function (img) {
      var w = img.width, h = img.height, s = Math.min(1, MAX_EDGE / Math.max(w, h));
      var c = document.createElement('canvas'); c.width = Math.round(w * s); c.height = Math.round(h * s);
      var ctx = c.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height);
      ctx.drawImage(img, 0, 0, c.width, c.height);
      return new Promise(function (ok, bad) { c.toBlob(function (b) { b ? ok(b) : bad(); }, 'image/jpeg', 0.85); });
    });
  }

  function uploadError(msg) { var e = $('bys-upload-error'); e.textContent = msg; e.hidden = !msg; if (msg) e.scrollIntoView({ block: 'center' }); }

  /* ---- Run the check ---- */
  function startCheck() {
    uploadError('');
    var count = 0, images = 0, bytes = 0;
    DOCS.forEach(function (d) { files[d.key].forEach(function (f) { count++; bytes += f.blob.size; if (f.kind === 'image') images++; }); });
    if (!count) return uploadError('Please add at least one document first.');
    if (images > MAX_IMAGES) return uploadError('That is ' + images + ' photographed pages; the limit for one check is 100. If you have the documents as PDFs, add those instead.');
    if (bytes > MAX_BYTES) return uploadError('The documents are too large to send in one go. Try PDFs instead of photos, or remove duplicate pages.');
    if (!$('bys-consent').checked) return uploadError('Please tick the box to say you understand how the check works.');
    var token = '';
    if (cfg.turnstile_sitekey) {
      token = window.turnstile && turnstileId !== null ? turnstile.getResponse(turnstileId) : '';
      if (!token) return uploadError('Please complete the "I am human" check above the button.');
    }

    var ref = 'BYS-' + hex(4).toUpperCase();
    var fd = new FormData(), plan = [], n = 0;
    fd.append('ref', ref); fd.append('device', st.device); fd.append('turnstile', token);
    DOCS.forEach(function (d) {
      var photos = files[d.key].filter(function (f) { return f.kind === 'image'; }).length, page = 0, first = true;
      files[d.key].forEach(function (f) {
        n++;
        var name = 'f' + ('00' + n).slice(-3) + (f.kind === 'pdf' ? '.pdf' : '.jpg');
        if (f.kind === 'pdf') {
          plan.push({ type: 'text', text: '=== ' + d.title + ' (PDF: ' + f.name + ') ===' });
          plan.push({ type: 'file', file: name, media: 'application/pdf', title: d.title + ' - ' + f.name, label: d.title + ': PDF file ' + f.name });
        } else {
          plan.push({ type: 'text', text: '=== ' + d.title + ' — photographed page ' + (++page) + ' ===' });
          var part = { type: 'file', file: name, media: 'image/jpeg' };
          if (first) { part.label = d.title + ': ' + photos + ' photographed page(s)'; first = false; }
          plan.push(part);
        }
        fd.append('files[]', f.blob, name);
      });
    });
    fd.append('plan', JSON.stringify(plan));
    fd.append('details', JSON.stringify({ community: $('bys-community').value, site: $('bys-site').value, notes: $('bys-notes').value }));

    st.ref = ref; st.stage = 'checking'; delete st.report; save(st);
    showStage('working');
    window.scrollTo(0, 0);
    $('bys-progress-text').textContent = 'Sending your documents securely to ARPRA.';

    var posted = null;
    fetch(S + '/analyse.php', { method: 'POST', body: fd, headers: { 'X-BYS-Device': st.device } })
      .then(function (r) { return r.text().then(function (t) { var j = {}; try { j = JSON.parse(t); } catch (e) {} posted = { status: r.status, json: j }; }); })
      .catch(function () { posted = { status: 0, json: {} }; });

    var seen = false, started = Date.now();
    clearInterval(pollTimer);
    pollTimer = setInterval(function () {
      if (posted && posted.status !== 200 && !(posted.status === 0 && seen)) {
        return fail(posted.json.error || (posted.status === 0 ? 'Could not send your documents. Check your internet connection and try again.' : 'The check could not be started (error ' + posted.status + ').'));
      }
      if (Date.now() - started > 15 * 60 * 1000) return fail('The check took too long. Please try again, or call ARPRA on 1300 798 399.');
      followCheck(function () { seen = true; });
    }, 4000);
  }

  function followCheck(onSeen) {
    api('status.php?ref=' + encodeURIComponent(st.ref)).then(function (r) {
      if (r.status === 404) return; // still uploading
      if (r.status !== 200) return fail(r.json.error || 'The check could not be completed.');
      onSeen && onSeen();
      var j = r.json;
      if (j.chars > 0) $('bys-progress-text').textContent = 'Reading your documents — about ' + Math.round(j.chars / 6).toLocaleString('en-AU') + ' words of notes so far.';
      if (j.status === 'done') {
        clearInterval(pollTimer);
        st.report = j.report; st.stage = 'result'; save(st);
        showResult();
        window.scrollTo(0, 0);
      } else if (j.status === 'error') {
        fail(j.error || 'The check could not be completed.');
      }
    }).catch(function () { /* keep trying */ });
  }

  function fail(msg) {
    clearInterval(pollTimer);
    st.stage = 'upload'; save(st);
    showStage('upload');
    uploadError(msg);
    if (window.turnstile && turnstileId !== null) turnstile.reset(turnstileId);
  }

  /* ---- The free summary ---- */
  function counts(r) {
    var k = r._counts;
    if (k) return k;
    var L = function (v) { return Array.isArray(v) ? v.filter(function (x) { return x && typeof x === 'object'; }) : []; };
    var items = L(r.red).concat(L(r.amber));
    var b = function (m) { return String(m.basis || ''); };
    var lawRed = L(r.red).filter(function (m) { return b(m) === 'law'; }).length;
    return {
      more_items: items.length - lawRed,
      unfair_terms: items.filter(function (m) { return b(m) === 'unfair_terms'; }).length,
      blanks: L(r.blanks).length,
      tick_problems: L(r.tick_boxes).filter(function (m) { return m.status !== 'ok'; }).length,
      term_changes: L(r.standard_terms_changes).filter(function (m) { return ['changed', 'missing', 'added', 'old version'].indexOf(String(m.status || '').toLowerCase()) >= 0; }).length,
      questions: Array.isArray(r.questions) ? r.questions.length : 0
    };
  }
  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : many); }

  function showResult() {
    var r = st.report || {};
    $('bys-ref').textContent = st.ref;
    $('bys-title').textContent = [r.community, r.site ? 'Site ' + r.site : ''].filter(Boolean).join(' · ');
    var rating = String(r.overall_rating || '').toLowerCase();
    $('bys-rating').className = 'bys-rating ' + (['high', 'moderate', 'low'].indexOf(rating) >= 0 ? rating : 'moderate');
    $('bys-rating-value').textContent = r.overall_rating || '—';
    $('bys-rating-reason').textContent = r.overall_reason || '';
    $('bys-summary').textContent = r.summary || '';

    var top = Array.isArray(r.top_issues) ? r.top_issues : [];
    $('bys-top').innerHTML = top.map(function (m) {
      m = typeof m === 'object' ? m : { title: m };
      return '<li><strong>' + esc(m.title) + '</strong>' + (m.why ? '<br>' + esc(m.why) : '') + (m.ask ? '<br><span class="ask">Ask: ' + esc(m.ask) + '</span>' : '') + '</li>';
    }).join('');
    show('bys-top-wrap', top.length > 0);

    var dates = (Array.isArray(r.key_dates) ? r.key_dates : []).filter(function (m) { return m && typeof m === 'object'; });
    $('bys-dates').innerHTML = dates.map(function (m) { return '<tr><td>' + esc(m.date) + '</td><td>' + esc(m.what) + '</td></tr>'; }).join('');
    show('bys-dates-wrap', dates.length > 0);

    var law = (Array.isArray(r.red) ? r.red : []).filter(function (m) { return m && m.basis === 'law'; });
    $('bys-law').innerHTML = law.map(function (m) { return '<li><strong>' + esc(m.title) + '</strong>' + (m.law ? '<div class="ref">' + esc(m.law) + '</div>' : '') + '</li>'; }).join('');
    show('bys-law-wrap', law.length > 0);

    var k = counts(r), lines = [];
    if (k.more_items) lines.push(plural(k.more_items, 'more thing', 'more things') + ' to look at or ask about');
    if (k.unfair_terms) lines.push(plural(k.unfair_terms, 'term', 'terms') + ' that may be unfair under consumer law');
    if (k.term_changes) lines.push(plural(k.term_changes, 'change', 'changes') + ' to the standard terms of the agreement');
    if ((k.blanks || 0) + (k.tick_problems || 0)) lines.push(plural(k.blanks + k.tick_problems, 'blank field or tick-box problem', 'blank fields or tick-box problems'));
    lines.push('what it will cost, with the site fee worked out over 20 years');
    if (k.questions) lines.push(k.questions + ' questions to put to the operator');
    $('bys-more').innerHTML = lines.map(function (l) { return '<li>' + esc(l) + '</li>'; }).join('');

    showStage('result');
    if (cfg.payment_link) show('bys-step-review', true);
    show('bys-want-review', !!cfg.payment_link);
  }

  /* ---- Paid review ---- */
  function reviewError(msg) { var e = $('bys-review-error'); e.textContent = msg; e.hidden = !msg; }

  function pay() {
    reviewError('');
    var c = { name: $('bys-name').value.trim(), email: $('bys-email').value.trim(), phone: $('bys-phone').value.trim(), signing_date: $('bys-when').value.trim() };
    if (!c.name || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(c.email)) return reviewError('Please enter your name and a valid email address.');
    if (!c.phone) return reviewError('Please enter a phone number so the adviser can call you.');
    st.contact = c; st.stage = 'paying'; save(st);
    var url = cfg.payment_link + (cfg.payment_link.indexOf('?') >= 0 ? '&' : '?') +
      'client_reference_id=' + encodeURIComponent(st.ref) + '&prefilled_email=' + encodeURIComponent(c.email);
    window.open(url, '_blank', 'noopener');
    waitForPayment();
  }

  function waitForPayment() {
    show('bys-paying', true);
    clearInterval(pollTimer);
    var tries = 0;
    var tick = function () {
      if (++tries > 225) { clearInterval(pollTimer); show('bys-paying', false); return reviewError('We have not seen your payment yet. If you paid, call ARPRA on 1300 798 399 and quote ' + st.ref + '.'); }
      api('check.php?ref=' + encodeURIComponent(st.ref)).then(function (r) {
        if (r.status === 200 && r.json.paid) { clearInterval(pollTimer); sendRequest(); }
      }).catch(function () {});
    };
    tick();
    pollTimer = setInterval(tick, 4000);
  }

  function sendRequest() {
    var fd = new FormData();
    fd.append('ref', st.ref);
    fd.append('meta', JSON.stringify({ contact: st.contact || {}, title: $('bys-title').textContent }));
    api('web-request.php', { method: 'POST', body: fd }).then(function (r) {
      show('bys-paying', false);
      if (r.status !== 200 || !r.json.ok) return reviewError(r.json.error || 'Your payment was received, but your request could not be sent. Please call ARPRA on 1300 798 399 and quote ' + st.ref + '.');
      st.stage = 'sent'; save(st);
      showSent();
    }).catch(function () { show('bys-paying', false); reviewError('Your payment was received, but we lost the connection. Please call ARPRA on 1300 798 399 and quote ' + st.ref + '.'); });
  }

  function showSent() {
    $('bys-sent-ref').textContent = st.ref;
    $('bys-sent-reply').textContent = cfg.reply_promise || 'soon';
    showStage('result');
    show('bys-step-review', false);
    show('bys-want-review', false);
    show('bys-step-sent', true);
    $('bys-step-sent').scrollIntoView({ block: 'start' });
  }

  /* ---- Page set-up ---- */
  function showStage(name) {
    show('bys-step-upload', name === 'upload');
    show('bys-step-working', name === 'working');
    show('bys-step-result', name === 'result');
    if (name !== 'result') { show('bys-step-review', false); show('bys-step-sent', false); }
    show('bys-restart', name === 'result');
  }

  function restart() {
    clearInterval(pollTimer);
    st = { device: st.device }; save(st);
    DOCS.forEach(function (d) { files[d.key] = []; });
    renderDocs();
    ['bys-community', 'bys-site', 'bys-notes'].forEach(function (id) { $(id).value = ''; });
    $('bys-consent').checked = false;
    uploadError(''); reviewError('');
    showStage('upload');
    if (window.turnstile && turnstileId !== null) turnstile.reset(turnstileId);
    window.scrollTo(0, 0);
  }

  function loadTurnstile() {
    if (!cfg.turnstile_sitekey) return;
    window.bysTurnstileReady = function () {
      turnstileId = turnstile.render('#bys-turnstile', { sitekey: cfg.turnstile_sitekey, theme: 'light' });
    };
    var s = document.createElement('script');
    s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?onload=bysTurnstileReady&render=explicit';
    s.async = true; s.defer = true;
    document.head.appendChild(s);
  }

  renderDocs();
  $('bys-go').addEventListener('click', startCheck);
  $('bys-pay').addEventListener('click', pay);
  $('bys-restart').addEventListener('click', restart);
  $('bys-want-review').addEventListener('click', function (e) { e.preventDefault(); $('bys-step-review').scrollIntoView({ block: 'start' }); $('bys-name').focus(); });

  api('web-config.php').then(function (r) {
    cfg = r.json || {};
    if (!cfg.enabled) { show('bys-off', true); show('bys-step-upload', false); return; }
    $('bys-fee').textContent = cfg.fee_text || '';
    $('bys-reply').textContent = cfg.reply_promise || 'soon';
    if (st.contact) { $('bys-name').value = st.contact.name || ''; $('bys-email').value = st.contact.email || ''; $('bys-phone').value = st.contact.phone || ''; $('bys-when').value = st.contact.signing_date || ''; }
    if (st.stage === 'checking' && st.ref) { showStage('working'); pollTimer = setInterval(function () { followCheck(); }, 4000); followCheck(); }
    else if (st.stage === 'result' && st.report) { showResult(); }
    else if (st.stage === 'paying' && st.report) { showResult(); waitForPayment(); }
    else if (st.stage === 'sent' && st.report) { showResult(); showSent(); }
    else { showStage('upload'); loadTurnstile(); }
    if (st.stage !== 'upload' && st.stage) loadTurnstile();
  }).catch(function () { show('bys-off', true); show('bys-step-upload', false); });
})();
