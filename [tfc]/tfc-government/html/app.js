// Government Center, DMV, and police license screens. The server checks everything.

const $ = (id) => document.getElementById(id);
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'tfc-government';

async function nui(name, data = {}) {
    try {
        const res = await fetch(`https://${resource}/${name}`, {
            method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
        });
        return await res.json();
    } catch (e) {
        return { ok: false, error: 'no response, try again' };
    }
}

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => '$' + Math.round(n || 0).toLocaleString('en-US');
const ago = (t) => {
    const s = Math.max(0, Date.now() / 1000 - t);
    if (s < 3600) return `${Math.max(1, Math.floor(s / 60))} min ago`;
    if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
    return `${Math.floor(s / 86400)} d ago`;
};
const STATUS = { valid: 'Valid', suspended: 'Suspended', revoked: 'Revoked', none: 'Not held' };
const pill = (s) => `<span class="pill ${esc(s)}">${STATUS[s] || esc(s)}</span>`;

const S = { view: null, data: null, tab: null, busy: false, quiz: null };

function setMsg(text, ok) {
    $('msg').textContent = text || '';
    $('msg').className = 'msg' + (text ? (ok ? ' ok' : ' err') : '');
}

function close() {
    $('backdrop').classList.add('hidden');
    $('quiz').classList.add('hidden');
    nui('close');
}
$('close').addEventListener('click', close);
document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || $('backdrop').classList.contains('hidden')) return;
    if (!$('quiz').classList.contains('hidden')) $('quiz').classList.add('hidden'); else close();
});

function tabs(list) {
    $('tabs').innerHTML = list.map(([id, label]) => `<button class="tab" data-tab="${id}" aria-selected="${id === S.tab}">${label}</button>`).join('');
    $('tabs').querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => { S.tab = t.dataset.tab; setMsg(''); render(); }));
}

async function call(endpoint, action, data) {
    if (S.busy) return null;
    S.busy = true;
    const r = await nui(endpoint, { action, data });
    S.busy = false;
    if (r && (r.view || r.licenses || r.jobs)) S.data = { ...S.data, ...r };
    setMsg(r && r.ok ? (r.message || '') : ((r && r.error) || 'something went wrong'), r && r.ok);
    render();
    return r;
}

function waypoint(place) {
    nui('waypoint', { x: place.x, y: place.y, label: place.label });
}

// Government Center ------------------------------------------------------------------------------

function renderCity() {
    const d = S.data;
    $('brand').textContent = 'State of San Andreas';
    $('title').textContent = 'Government Center';
    tabs([['welcome', 'Welcome'], ['jobs', 'Jobs'], ['licenses', 'Licenses'], ['services', 'Services'], ['faq', 'Help & rules']]);
    const body = $('body');
    const placeById = (id) => d.places.find((p) => p.id === id);

    if (S.tab === 'welcome') {
        body.innerHTML = `
            <h2>${esc(d.info.title)}</h2>
            <p class="intro">${esc(d.info.intro)}</p>
            <h3>Getting started</h3>
            <div class="grid">${d.info.steps.map((s, i) => {
                let btn = '';
                if (s.place && placeById(s.place)) btn = `<button class="secondary small" data-way="${esc(s.place)}">Set waypoint</button>`;
                else if (s.tab) btn = `<button class="secondary small" data-tabgo="${esc(s.tab)}">Open</button>`;
                else if (s.action === 'accountant' && d.accountant) btn = '<button class="primary small" data-acct>Talk to the Accountant</button>';
                return `<div class="card"><div class="t"><span><span class="step-n">${i + 1}</span>${esc(s.title)}</span></div>
                    <div class="d">${esc(s.text)}</div><div class="acts">${btn}</div></div>`;
            }).join('')}</div>
            <h3>Places</h3>
            <div class="list">${d.places.map((p, i) => `<div class="row"><span class="grow">${esc(p.label)}</span>
                <button class="ghost small" data-place="${i}">Set waypoint</button></div>`).join('')}</div>`;
        body.querySelectorAll('[data-way]').forEach((b) => b.addEventListener('click', () => waypoint(placeById(b.dataset.way))));
        body.querySelectorAll('[data-place]').forEach((b) => b.addEventListener('click', () => waypoint(d.places[Number(b.dataset.place)])));
        body.querySelectorAll('[data-tabgo]').forEach((b) => b.addEventListener('click', () => { S.tab = b.dataset.tabgo; render(); }));
        body.querySelectorAll('[data-acct]').forEach((b) => b.addEventListener('click', () => nui('accountant')));
    } else if (S.tab === 'jobs') {
        const cur = d.currentJob;
        body.innerHTML = `
            <p class="intro">Sign up for a public job and start at the entry rank. Police, EMS and Fire hire through their own departments, and businesses hire through their owners.</p>
            ${cur && cur.name !== 'unemployed' ? `<div class="list" style="margin-bottom:16px"><div class="row"><span class="grow">Your job: <strong>${esc(cur.label)}</strong>${cur.grade ? ' · ' + esc(cur.grade) : ''}</span>
                <button class="ghost small" id="quit">Quit job</button></div></div>` : ''}
            <div class="grid">${d.jobs.length ? d.jobs.map((j) => `<div class="card${j.current ? ' mine' : ''}">
                <div class="t">${esc(j.label)}${j.current ? '<span class="pill valid">Your job</span>' : ''}</div>
                <div class="d">${esc(j.description)}</div>
                <div class="meta">Start as <strong>${esc(j.startRank)}</strong> · ${money(j.startPay)} per paycheck · ${j.ranks} ranks</div>
                <div class="acts">${j.current ? '' : `<button class="primary small" data-apply="${esc(j.name)}">Sign up</button>`}</div></div>`).join('')
                : '<p class="muted">No public jobs right now.</p>'}</div>`;
        if ($('quit')) $('quit').addEventListener('click', () => call('city', 'quit'));
        body.querySelectorAll('[data-apply]').forEach((b) => b.addEventListener('click', () => {
            if (cur && cur.name !== 'unemployed' && !b.dataset.sure) {
                b.dataset.sure = '1';
                b.textContent = `Leave ${cur.label}?`;
                return;
            }
            call('city', 'apply', { job: b.dataset.apply });
        }));
    } else if (S.tab === 'licenses') {
        const dmv = d.places.find((p) => p.id === 'dmv');
        body.innerHTML = `
            <p class="intro">Licenses are issued at the DMV. Endorsements, weapon, boat and pilot licenses need a short 5-question test.</p>
            ${dmv ? '<p><button class="primary" id="dmv-way">Set waypoint to the DMV</button></p>' : ''}
            <div class="list">${d.licenses.map((l) => `<div class="row"><div class="grow"><div>${esc(l.label)}</div>
                <div class="sub">${esc(l.description)} · ${money(l.price)}${l.quiz ? ' · test' : ''}</div></div>${pill(l.status)}</div>`).join('')}</div>`;
        if (dmv) $('dmv-way').addEventListener('click', () => waypoint(dmv));
    } else if (S.tab === 'services') {
        body.innerHTML = `<div class="grid">
            <div class="card"><div class="t">Replacement ID card</div>
                <div class="d">Lost your ID? Get a new one for ${money(d.idCardFee)}.</div>
                <div class="acts"><button class="primary small" id="idcard" ${d.hasIdCard ? 'disabled' : ''}>${d.hasIdCard ? 'You have one' : `Get ID card · ${money(d.idCardFee)}`}</button></div></div>
            ${d.accountant ? `<div class="card"><div class="t">City Accountant</div>
                <div class="d">Free advice on your money: bills, credit, saving and investing in the stock market.</div>
                <div class="acts"><button class="primary small" data-acct>Talk to the Accountant</button></div></div>` : ''}
            <div class="card"><div class="t">Bills</div><div class="d">See and pay your bills anywhere with <strong>/bills</strong>, or at any bank.</div></div>
            <div class="card"><div class="t">Your job</div><div class="d">Type <strong>/job</strong> to see your rank, pay and next paycheck. <strong>/duty</strong> to clock in.</div></div>
        </div>`;
        $('idcard').addEventListener('click', () => call('city', 'idcard'));
        body.querySelectorAll('[data-acct]').forEach((b) => b.addEventListener('click', () => nui('accountant')));
    } else {
        body.innerHTML = `<h3>Questions</h3>${d.info.faq.map((f) => `<details class="faq"><summary>${esc(f.q)}</summary><p>${esc(f.a)}</p></details>`).join('')}
            <h3>City rules</h3><ul class="rules">${d.info.rules.map((r) => `<li>${esc(r)}</li>`).join('')}</ul>`;
    }
}

// DMV -------------------------------------------------------------------------------------------------

function renderDmv() {
    const d = S.data;
    $('brand').textContent = 'Department of Motor Vehicles';
    $('title').textContent = 'DMV';
    tabs([]);
    $('body').innerHTML = `
        <p class="intro">Pay with your bank (or cash). Tests need ${d.passScore} of 5 right. Lost a card? A replacement is ${money(d.replacementFee)} while the license is valid.</p>
        <div class="grid">${d.licenses.map((l) => {
            let acts = '';
            if (l.status === 'none') {
                if (!l.requiresOk) acts = `<button class="secondary small" disabled>Needs ${esc(l.requires)}</button>`;
                else if (l.quiz) acts = `<button class="primary small" data-quiz="${esc(l.id)}">Take the test · ${money(l.price)}</button>`;
                else acts = `<button class="primary small" data-buy="${esc(l.id)}">Get it · ${money(l.price)}</button>`;
            } else if (l.status === 'valid') {
                acts = l.hasCard ? '<span class="muted">Card in your pocket</span>'
                    : `<button class="secondary small" data-replace="${esc(l.id)}">Replacement card · ${money(d.replacementFee)}</button>`;
            } else {
                acts = l.pending ? '<span class="pill pending">Reinstatement requested</span>'
                    : `<button class="secondary small" data-reinstate="${esc(l.id)}">Request reinstatement</button>`;
            }
            return `<div class="card"><div class="t">${esc(l.label)}${l.status !== 'none' ? pill(l.status) : ''}</div>
                <div class="d">${esc(l.description)}</div>
                ${l.status !== 'none' && l.status !== 'valid' && l.reason ? `<div class="meta">Reason: ${esc(l.reason)}</div>` : ''}
                ${l.requires && l.status === 'none' ? `<div class="meta">Requires: <strong>${esc(l.requires)}</strong></div>` : ''}
                <div class="acts">${acts}</div></div>`;
        }).join('')}</div>`;
    const b = $('body');
    b.querySelectorAll('[data-buy]').forEach((x) => x.addEventListener('click', () => call('dmv', 'buy', { id: x.dataset.buy })));
    b.querySelectorAll('[data-replace]').forEach((x) => x.addEventListener('click', () => call('dmv', 'replace', { id: x.dataset.replace })));
    b.querySelectorAll('[data-reinstate]').forEach((x) => x.addEventListener('click', () => call('dmv', 'reinstate', { id: x.dataset.reinstate })));
    b.querySelectorAll('[data-quiz]').forEach((x) => x.addEventListener('click', () => startQuiz(x.dataset.quiz)));
}

async function startQuiz(id) {
    const r = await nui('dmv', { action: 'quiz', data: { id } });
    if (!r || !r.ok) return setMsg((r && r.error) || 'could not start the test', false);
    S.quiz = r;
    $('quiz-title').textContent = r.label;
    $('quiz-body').innerHTML = r.questions.map((q, i) => `<div class="q"><div class="qt">${i + 1}. ${esc(q.q)}</div>
        ${q.c.map((c, j) => `<label><input type="radio" name="q${i}" value="${j + 1}"><span>${esc(c)}</span></label>`).join('')}</div>`).join('');
    $('quiz-submit').textContent = 'Submit answers';
    $('quiz-submit').disabled = false;
    $('quiz').classList.remove('hidden');
}

$('quiz-cancel').addEventListener('click', () => $('quiz').classList.add('hidden'));
$('quiz-submit').addEventListener('click', async () => {
    const q = S.quiz;
    if (!q) return;
    if (q.state === 'passed') {
        $('quiz').classList.add('hidden');
        call('dmv', 'buy', { id: q.id });
        return;
    }
    if (q.state === 'failed') return startQuiz(q.id);

    const answers = q.questions.map((_, i) => {
        const el = document.querySelector(`input[name="q${i}"]:checked`);
        return el ? Number(el.value) : 0;
    });
    if (answers.includes(0)) {
        $('quiz-submit').textContent = 'Answer every question';
        setTimeout(() => { $('quiz-submit').textContent = 'Submit answers'; }, 1500);
        return;
    }
    const r = await nui('dmv', { action: 'submit', data: { id: q.id, answers } });
    if (!r || !r.ok) { $('quiz').classList.add('hidden'); return setMsg((r && r.error) || 'something went wrong', false); }
    q.state = r.passed ? 'passed' : 'failed';
    const lic = S.data.licenses.find((l) => l.id === q.id);
    $('quiz-body').innerHTML = `<div class="result ${r.passed ? 'pass' : 'fail'}">${esc(r.message)}</div>`;
    $('quiz-submit').textContent = r.passed ? `Pay ${money(lic ? lic.price : 0)} and get the license` : 'Try again';
});

// Police ---------------------------------------------------------------------------------------------

function renderPolice() {
    const d = S.data;
    const t = d.target;
    $('brand').textContent = 'Police · Licenses';
    $('title').textContent = `${t.name} (${t.cid})`;
    tabs([]);
    $('body').innerHTML = `
        <div class="list">${t.licenses.map((l) => {
            let acts = '';
            if (l.status === 'valid') {
                acts = `<input placeholder="Reason" data-reason="${esc(l.id)}" style="width:200px">
                    <button class="secondary small" data-set="suspend" data-id="${esc(l.id)}">Suspend</button>
                    <button class="danger small" data-set="revoke" data-id="${esc(l.id)}">Revoke</button>`;
            } else if (l.status !== 'none') {
                acts = d.supervisor ? `<button class="primary small" data-set="reinstate" data-id="${esc(l.id)}">Reinstate</button>` : '<span class="muted">Supervisor can reinstate</span>';
            }
            return `<div class="row"><div class="grow"><div>${esc(l.label)}</div>${l.reason ? `<div class="sub">${esc(l.reason)}</div>` : ''}</div>${pill(l.status)}${acts}</div>`;
        }).join('')}</div>
        <h3>History</h3>
        <div class="list">${t.events.length ? t.events.map((e) => `<div class="row"><span class="grow">${esc(e.action)} · ${esc(e.type)}${e.reason ? ' · ' + esc(e.reason) : ''}</span>
            <span class="sub">${e.by_name ? esc(e.by_name) + ' · ' : ''}${ago(e.at)}</span></div>`).join('') : '<div class="row muted">Nothing yet.</div>'}</div>`;
    $('body').querySelectorAll('[data-set]').forEach((b) => b.addEventListener('click', async () => {
        const reasonEl = document.querySelector(`[data-reason="${CSS.escape(b.dataset.id)}"]`);
        const r = await nui('police', { action: 'set', a: t.id, b: b.dataset.id, c: { action: b.dataset.set, reason: reasonEl ? reasonEl.value : '' } });
        if (r && r.ok) S.data = r;
        setMsg(r && r.ok ? r.message : ((r && r.error) || 'something went wrong'), r && r.ok);
        render();
    }));
}

function renderRequests() {
    const d = S.data;
    $('brand').textContent = 'Police · Supervisor';
    $('title').textContent = 'License reinstatement requests';
    tabs([]);
    $('body').innerHTML = d.requests.length ? `<div class="list">${d.requests.map((r) => `<div class="row">
        <div class="grow"><div><strong>${esc(r.name)}</strong> (${esc(r.cid)}) · ${esc(r.label)}</div>
        <div class="sub">${r.status ? STATUS[r.status] : ''}${r.reason ? ': ' + esc(r.reason) : ''} · asked ${ago(r.at)}</div></div>
        <button class="primary small" data-decide="${r.id}" data-ok="1">Approve</button>
        <button class="ghost small" data-decide="${r.id}">Deny</button></div>`).join('')}</div>` : '<p class="muted">No pending requests.</p>';
    $('body').querySelectorAll('[data-decide]').forEach((b) => b.addEventListener('click', async () => {
        const r = await nui('police', { action: 'decide', a: Number(b.dataset.decide), b: b.dataset.ok === '1' });
        if (r && r.ok) S.data = r;
        setMsg(r && r.ok ? r.message : ((r && r.error) || 'something went wrong'), r && r.ok);
        render();
    }));
}

// ---------------------------------------------------------------------------------------------------

function render() {
    if (S.view === 'cityhall') renderCity();
    else if (S.view === 'dmv') renderDmv();
    else if (S.view === 'police') renderPolice();
    else if (S.view === 'requests') renderRequests();
}

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'open') {
        S.view = m.view;
        S.data = m.data;
        S.tab = m.view === 'cityhall' ? 'welcome' : null;
        setMsg('');
        $('quiz').classList.add('hidden');
        $('backdrop').classList.remove('hidden');
        render();
    } else if (m.action === 'close') {
        $('backdrop').classList.add('hidden');
    }
});
