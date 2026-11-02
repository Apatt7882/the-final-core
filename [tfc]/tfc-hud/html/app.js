'use strict';

const IN_GAME = typeof GetParentResourceName === 'function';
const $ = (id) => document.getElementById(id);

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const config = { timeSource: 'game', use24Hour: true, showLocation: true, showPostal: false };
let realClock = null;

// Formatting ------------------------------------------------------------------------

function money(n) {
    const abs = Math.abs(Math.trunc(n)).toLocaleString('en-US');
    return `${n < 0 ? '-' : ''}$${abs}`;
}

function pad(n) {
    return String(n).padStart(2, '0');
}

function renderTime(t) {
    let hour = t.hour;
    let suffix = '';
    if (!config.use24Hour) {
        suffix = hour >= 12 ? ' PM' : ' AM';
        hour = hour % 12 || 12;
    }
    $('time').textContent = `${config.use24Hour ? pad(hour) : hour}:${pad(t.minute)}${suffix}`;
    $('date').textContent = `${DAYS[t.weekday]} ${t.day} ${MONTHS[t.month]} ${t.year}`;
}

function startRealClock() {
    const tick = () => {
        const d = new Date();
        renderTime({ hour: d.getHours(), minute: d.getMinutes(), day: d.getDate(), month: d.getMonth(), year: d.getFullYear(), weekday: d.getDay() });
    };
    tick();
    clearInterval(realClock);
    realClock = setInterval(tick, 1000);
}

// Fields ------------------------------------------------------------------------------

function setMoney(account, value) {
    $(account).textContent = money(value);
    if (account === 'credit') {
        // Only worth showing while the player owes something.
        document.querySelector('.row.credit').classList.toggle('hidden', !(value < 0));
    }
}

function moneyChanged(account, value, delta) {
    setMoney(account, value);
    if (!delta) return;

    const row = document.querySelector(`.row[data-account="${account}"]`);
    const label = $(`${account}-delta`);
    // credit going up (less negative) is good news too
    const good = delta > 0;

    row.classList.remove('up', 'down');
    label.classList.remove('show', 'good', 'bad');
    void row.offsetWidth; // restart the animations

    row.classList.add(good ? 'up' : 'down');
    label.textContent = `${good ? '+' : '-'}${money(Math.abs(delta))}`;
    label.classList.add('show', good ? 'good' : 'bad');
}

function setJob(job) {
    $('job-label').textContent = job.label || '';
    $('job-grade').textContent = job.grade || '';
    const duty = $('duty');
    duty.className = 'duty';
    if (job.onDuty === true) duty.classList.add('on');
    else if (job.onDuty === false) duty.classList.add('off');
    duty.title = job.onDuty === true ? 'On duty' : job.onDuty === false ? 'Off duty' : '';
}

function setLocation(loc) {
    $('dir').textContent = loc.dir;
    const street = $('street');
    street.textContent = loc.street || '';
    if (loc.cross) {
        const cross = document.createElement('span');
        cross.className = 'cross';
        cross.textContent = ` / ${loc.cross}`;
        street.appendChild(cross);
    }
    $('zone').textContent = loc.zone || '';
}

// Who's on: [{ key, label, icon, count }]
const COUNT_ICONS = {
    staff: '<path d="M12 3 4.5 6v5.5c0 4.4 3.1 8.2 7.5 9.5 4.4-1.3 7.5-5.1 7.5-9.5V6z"/><path d="m9 12 2 2 4-4"/>',
    leo: '<path d="M12 2.8 14.6 8l5.7.8-4.1 4 1 5.7L12 15.8l-5.2 2.7 1-5.7-4.1-4 5.7-.8z"/>',
    ems: '<path d="M9.5 3.5h5v6h6v5h-6v6h-5v-6h-6v-5h6z"/>',
    fire: '<path d="M12 21c3.6 0 6-2.5 6-6 0-3.7-3-6-3.5-9.5C12.5 7 10 9.5 10 12c-1-.5-1.8-1.6-2-3-1.3 1.5-2 3.6-2 6 0 3.5 2.4 6 6 6z"/>',
};

function setCounts(list) {
    const box = $('counts');
    if (!Array.isArray(list) || list.length === 0) {
        box.classList.add('hidden');
        return;
    }
    box.innerHTML = list.map((c) => {
        const icon = COUNT_ICONS[c.icon] || COUNT_ICONS[c.key] || COUNT_ICONS.staff;
        const n = Number(c.count) || 0;
        return `<span class="count ${String(c.key).replace(/[^a-z0-9_-]/gi, '')}${n === 0 ? ' zero' : ''}" title="${String(c.label)}">
            <svg viewBox="0 0 24 24">${icon}</svg><span class="n">${n}</span><span class="l">${String(c.label).replace(/[<>&]/g, '')}</span>
        </span>`;
    }).join('');
    box.classList.remove('hidden');
}

function setAnchor(a) {
    // a.* are 0-1 fractions of the screen; place the location just right of the minimap,
    // vertically centred on its lower half.
    const el = $('corner');
    el.style.left = `calc(${(a.right * 100).toFixed(3)}vw + 1.2vh)`;
    el.style.bottom = `${((1 - a.bottom) * 100).toFixed(3)}vh`;
}

// Messages from the client --------------------------------------------------------------

const setters = {
    cash: (v) => setMoney('cash', v),
    bank: (v) => setMoney('bank', v),
    credit: (v) => setMoney('credit', v),
    job: setJob,
    time: (v) => { if (config.timeSource === 'game') renderTime(v); },
    location: setLocation,
    anchor: setAnchor,
    counts: setCounts,
    postal: (code) => {
        $('postal-box').classList.toggle('hidden', !config.showPostal || !code);
        if (code) $('postal').textContent = code;
    },
};

let hideTimer = null;

function setVisible(show) {
    const hud = $('hud');
    clearTimeout(hideTimer);
    if (show) {
        hud.classList.remove('hidden');
        requestAnimationFrame(() => hud.classList.remove('fading'));
    } else {
        hud.classList.add('fading');
        hideTimer = setTimeout(() => hud.classList.add('hidden'), 250);
    }
}

window.addEventListener('message', (event) => {
    const msg = event.data || {};
    switch (msg.action) {
        case 'init':
            Object.assign(config, msg.config || {});
            $('location').classList.toggle('hidden', !config.showLocation);
            $('postal-box').classList.toggle('hidden', !config.showPostal);
            if (msg.anchor) setAnchor(msg.anchor);
            if (config.timeSource === 'real') startRealClock();
            else clearInterval(realClock);
            break;
        case 'set':
            if (setters[msg.field]) setters[msg.field](msg.value);
            break;
        case 'money':
            moneyChanged(msg.account, msg.value, msg.delta);
            break;
        case 'visible':
            setVisible(msg.value);
            break;
    }
});

// Browser preview (never runs in game) -----------------------------------------------------

if (!IN_GAME) {
    document.body.style.background = 'linear-gradient(160deg, #6d8fb3 0%, #b9a27c 55%, #4b5a3c 100%)';
    const post = (data) => window.postMessage(data, '*');
    post({ action: 'init', config: { timeSource: 'game', use24Hour: true, showLocation: true, showPostal: true }, anchor: { left: 0.0185, right: 0.159, bottom: 0.967, top: 0.791 } });
    post({ action: 'set', field: 'time', value: { hour: 14, minute: 32, day: 1, month: 10, year: 2026, weekday: 0 } });
    post({ action: 'set', field: 'cash', value: 1250 });
    post({ action: 'set', field: 'bank', value: 48320 });
    post({ action: 'set', field: 'credit', value: -1200 });
    post({ action: 'set', field: 'job', value: { label: 'Police', grade: 'Sergeant', onDuty: true } });
    post({ action: 'set', field: 'location', value: { dir: 'NW', street: 'Vinewood Blvd', cross: 'Las Lagunas Blvd', zone: 'Downtown Vinewood' } });
    post({ action: 'set', field: 'postal', value: '7041' });
    post({ action: 'set', field: 'counts', value: [
        { key: 'staff', label: 'Staff', icon: 'staff', count: 2 },
        { key: 'leo', label: 'LEO', icon: 'leo', count: 4 },
        { key: 'ems', label: 'EMS', icon: 'ems', count: 0 },
    ] });
    post({ action: 'visible', value: true });
    setTimeout(() => post({ action: 'money', account: 'cash', value: 1500, delta: 250 }), 400);
}
