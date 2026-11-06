// City Accountant window: advice, stock market and portfolio. The server checks everything.

const $ = (id) => document.getElementById(id);
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'tfc-finance';

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
const money = (n) => (n < 0 ? '-$' : '$') + Math.abs(Math.round(n || 0)).toLocaleString('en-US');
const price = (n) => '$' + Number(n || 0).toFixed(2);
const pct = (n) => `${n >= 0 ? '+' : ''}${(n * 100).toFixed(1)}%`;
const ago = (t) => {
    const s = Math.max(0, Date.now() / 1000 - t);
    if (s < 3600) return `${Math.max(1, Math.floor(s / 60))} min ago`;
    if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
    return `${Math.floor(s / 86400)} d ago`;
};

const S = { data: null, tab: 'advisor', symbol: null, busy: false, timer: null };

function setMsg(text, ok) {
    $('msg').textContent = text || '';
    $('msg').className = 'msg' + (text ? (ok ? ' ok' : ' err') : '');
}

function close() {
    clearInterval(S.timer);
    $('backdrop').classList.add('hidden');
    nui('close');
}
$('close').addEventListener('click', close);
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('backdrop').classList.contains('hidden') && document.activeElement !== $('a-question')) close();
});

function setTab(tab) {
    S.tab = tab;
    document.querySelectorAll('.tab').forEach((t) => t.setAttribute('aria-selected', String(t.dataset.tab === tab)));
    document.querySelectorAll('[data-panel]').forEach((p) => p.classList.toggle('hidden', p.dataset.panel !== tab));
    render();
}
document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => { setMsg(''); setTab(t.dataset.tab); }));

// Charts -----------------------------------------------------------------------------------------

function line(values, w, h, cls) {
    if (!values || values.length < 2) return `<svg class="${cls}" viewBox="0 0 ${w} ${h}"></svg>`;
    const min = Math.min(...values), max = Math.max(...values);
    const span = max - min || 1;
    const pts = values.map((v, i) => `${(i / (values.length - 1) * w).toFixed(1)},${(h - 2 - (v - min) / span * (h - 4)).toFixed(1)}`);
    const up = values[values.length - 1] >= values[0];
    const color = up ? '#4cc38a' : '#e5484d';
    const area = `0,${h} ${pts.join(' ')} ${w},${h}`;
    return `<svg class="${cls}" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
        <polygon points="${area}" fill="${color}" fill-opacity="0.12"/>
        <polyline points="${pts.join(' ')}" fill="none" stroke="${color}" stroke-width="2" vector-effect="non-scaling-stroke" stroke-linejoin="round"/></svg>`;
}

// Advice -------------------------------------------------------------------------------------------

function renderAdvisor() {
    const s = S.data.snapshot;
    $('title').textContent = `Hello, ${s.name.split(' ')[0]}`;
    $('a-cards').innerHTML = [
        ['Net worth', money(s.netWorth), s.netWorth < 0 ? 'down' : ''],
        ['Bank', money(s.bank), ''],
        ['Cash', money(s.cash), ''],
        ['Credit owed', money(s.creditOwed), s.creditOwed > 0 ? 'down' : ''],
        ['Stocks', money(s.portfolio.value), ''],
    ].map(([k, v, c]) => `<div class="card"><div class="k">${k}</div><div class="v ${c}">${v}</div></div>`).join('');
    $('a-list').innerHTML = S.data.advice.map((a) => `<div class="tip ${esc(a.level)}"><div class="tt">${esc(a.title)}</div><div class="tx">${esc(a.text)}</div></div>`).join('');
    $('a-ask').classList.toggle('hidden', !S.data.ai);
}

$('a-send').addEventListener('click', async () => {
    const q = $('a-question').value.trim();
    if (q.length < 3 || S.busy) return;
    S.busy = true;
    $('a-send').disabled = true;
    $('a-send').textContent = 'Thinking…';
    const r = await nui('ask', { question: q });
    S.busy = false;
    $('a-send').disabled = false;
    $('a-send').textContent = 'Ask';
    $('a-answer').classList.remove('hidden');
    $('a-answer').textContent = r && r.ok ? r.answer : `Sorry: ${(r && r.error) || 'something went wrong'}.`;
    $('a-left').textContent = r && r.ok ? `${r.left} question${r.left === 1 ? '' : 's'} left today` : '';
});

// Stocks ---------------------------------------------------------------------------------------------

function stock(sym) { return S.data.market.stocks.find((x) => x.symbol === sym); }
function holding(sym) { return S.data.portfolio.holdings.find((x) => x.symbol === sym); }
function fee(amount) { return Math.max(S.data.market.minFee, Math.ceil(amount * S.data.market.fee)); }

function renderStocks() {
    const m = S.data.market;
    if (!S.symbol || !stock(S.symbol)) S.symbol = m.stocks[0] && m.stocks[0].symbol;
    $('s-rows').innerHTML = m.stocks.map((s) => `<tr class="click${s.symbol === S.symbol ? ' current' : ''}" data-sym="${esc(s.symbol)}">
        <td><span class="sym">${esc(s.symbol)}</span>${esc(s.name)}<div class="sector">${esc(s.sector)}</div></td>
        <td class="num">${price(s.price)}</td>
        <td class="num ${s.change >= 0 ? 'up' : 'down'}">${pct(s.change)}</td>
        <td>${line(s.spark, 130, 30, 'spark')}</td></tr>`).join('');
    $('s-rows').querySelectorAll('[data-sym]').forEach((tr) => tr.addEventListener('click', () => { S.symbol = tr.dataset.sym; setMsg(''); renderStocks(); }));
    renderDetail();
}

function renderDetail() {
    const s = stock(S.symbol);
    if (!s) { $('s-detail').innerHTML = ''; return; }
    const h = holding(s.symbol);
    const news = S.data.market.news.filter((n) => n.symbol === s.symbol).slice(0, 4);
    const allNews = news.length ? news : S.data.market.news.slice(0, 4);
    $('s-detail').innerHTML = `
        <div><span class="sym">${esc(s.symbol)}</span><strong>${esc(s.name)}</strong> <span class="sector">· ${esc(s.sector)}</span></div>
        <div class="big">${price(s.price)} <span class="${s.change >= 0 ? 'up' : 'down'}" style="font-size:15px">${pct(s.change)} today</span></div>
        ${line(s.week, 320, 130, 'chart')}
        <div class="muted small">Last 7 days</div>
        <p class="muted" style="margin:10px 0 0">You own <strong>${h ? h.shares : 0}</strong> share${h && h.shares === 1 ? '' : 's'}${h ? ` worth ${money(h.value)}` : ''}.</p>
        <div class="trade">
            <input id="d-shares" type="number" min="1" value="1" ${S.data.canTrade ? '' : 'disabled'}>
            <button class="primary" id="d-buy" ${S.data.canTrade ? '' : 'disabled'}>Buy</button>
            <button class="secondary" id="d-sell" ${S.data.canTrade && h ? '' : 'disabled'}>Sell</button>
        </div>
        <div class="trade-sum" id="d-sum"></div>
        <h3>${news.length ? 'News' : 'Market news'}</h3>
        ${allNews.length ? allNews.map((n) => `<div class="news"><span class="${n.change >= 0 ? 'up' : 'down'}">${pct(n.change)}</span> ${esc(n.text)} <div class="when">${ago(n.at)}</div></div>`).join('') : '<p class="muted">No news yet.</p>'}`;
    const sum = () => {
        const n = Math.max(0, Math.floor(Number($('d-shares').value) || 0));
        const cost = Math.ceil(s.price * n);
        $('d-sum').textContent = n ? `Buy: about ${money(cost + fee(cost))} incl. ${money(fee(cost))} fee · Sell: about ${money(Math.max(0, Math.floor(s.price * n) - fee(Math.floor(s.price * n))))}` : '';
    };
    $('d-shares').addEventListener('input', sum);
    sum();
    $('d-buy').addEventListener('click', () => trade('buy', s.symbol, Number($('d-shares').value)));
    $('d-sell').addEventListener('click', () => trade('sell', s.symbol, Number($('d-shares').value)));
}

async function trade(side, symbol, shares) {
    if (S.busy) return;
    S.busy = true;
    const r = await nui('trade', { side, symbol, shares });
    S.busy = false;
    if (r && r.snapshot) S.data = r;
    setMsg(r && r.ok ? r.message : ((r && r.error) || 'something went wrong'), r && r.ok);
    render();
}

// Portfolio -----------------------------------------------------------------------------------------

function renderPortfolio() {
    const p = S.data.portfolio;
    const gain = p.value - p.cost;
    $('p-cards').innerHTML = [
        ['Value', money(p.value), ''],
        ['Invested', money(p.cost), ''],
        ['Gain / loss', `${gain >= 0 ? '+' : ''}${money(gain)}`, gain >= 0 ? 'up' : 'down'],
        ['Return', p.cost > 0 ? pct(gain / p.cost) : '–', gain >= 0 ? 'up' : 'down'],
        ['Companies', String(p.holdings.length), ''],
    ].map(([k, v, c]) => `<div class="card"><div class="k">${k}</div><div class="v ${c}">${v}</div></div>`).join('');
    $('p-empty').classList.toggle('hidden', p.holdings.length > 0);
    $('p-rows').innerHTML = p.holdings.map((h) => {
        const g = h.value - h.cost;
        return `<tr><td><span class="sym">${esc(h.symbol)}</span>${esc(h.name)}</td>
            <td class="num">${h.shares}</td><td class="num">${price(h.avg)}</td><td class="num">${price(h.price)}</td>
            <td class="num">${money(h.value)}</td>
            <td class="num ${g >= 0 ? 'up' : 'down'}">${g >= 0 ? '+' : ''}${money(g)} (${h.cost > 0 ? pct(g / h.cost) : '–'})</td>
            <td class="num"><input class="sell-in" type="number" min="1" max="${h.shares}" value="${h.shares}" data-sellqty="${esc(h.symbol)}" ${S.data.canTrade ? '' : 'disabled'}>
                <button class="secondary small" data-sell="${esc(h.symbol)}" ${S.data.canTrade ? '' : 'disabled'}>Sell</button></td></tr>`;
    }).join('');
    $('p-rows').querySelectorAll('[data-sell]').forEach((b) => b.addEventListener('click', () => {
        const n = Number(document.querySelector(`[data-sellqty="${CSS.escape(b.dataset.sell)}"]`).value);
        trade('sell', b.dataset.sell, n);
    }));
    $('p-trades').innerHTML = p.trades.length ? p.trades.map((t) => `<div class="trade-row">
        <span>${t.side === 'buy' ? 'Bought' : 'Sold'} ${t.shares} <span class="sym">${esc(t.symbol)}</span> @ ${price(t.price)}</span>
        <span class="${t.side === 'buy' ? 'down' : 'up'}">${t.side === 'buy' ? '-' : '+'}${money(t.total)} <span class="muted small">· ${ago(t.at)}</span></span></div>`).join('')
        : '<p class="empty">No trades yet.</p>';
}

// ---------------------------------------------------------------------------------------------------

function render() {
    $('trade-note').textContent = S.data.canTrade ? 'You can trade here' : 'View only: trade at a bank or the City Accountant';
    if (S.tab === 'advisor') renderAdvisor();
    else if (S.tab === 'stocks') renderStocks();
    else renderPortfolio();
}

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'open') {
        S.data = m.data;
        setMsg('');
        $('a-answer').classList.add('hidden');
        $('a-left').textContent = '';
        $('backdrop').classList.remove('hidden');
        setTab(m.tab || 'advisor');
        clearInterval(S.timer);
        // Keep prices fresh while the window is open.
        S.timer = setInterval(async () => {
            if ($('backdrop').classList.contains('hidden') || S.busy || S.tab === 'advisor') return;
            const r = await nui('refresh');
            if (r && r.ok) { S.data = r; if (document.activeElement && document.activeElement.tagName === 'INPUT') return; render(); }
        }, 30000);
    } else if (m.action === 'close') {
        clearInterval(S.timer);
        $('backdrop').classList.add('hidden');
    }
});
