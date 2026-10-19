import { useEffect, useState } from 'react';
import { supabase } from './lib/supabase.js';
import './styles.css';

async function api(action, arg) {
  const { data: { session } } = await supabase.auth.getSession();
  const r = await fetch('/api/game', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + session.access_token },
    body: JSON.stringify({ action, arg }),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(j.error || 'Terjadi kesalahan');
  return j;
}

function mood(c) {
  if (c.sleep_start) return 'tidur';
  if (c.health < 30) return 'sakit';
  if (c.hunger < 25) return 'lapar';
  if (c.energy < 25) return 'ngantuk';
  if (c.happy < 25) return 'sedih';
  return 'senang';
}

const EYES = [
  <><circle cx="84" cy="88" r="5" fill="#333"/><circle cx="116" cy="88" r="5" fill="#333"/></>,
  <><circle cx="84" cy="88" r="9" fill="#fff" stroke="#333" strokeWidth="2"/><circle cx="116" cy="88" r="9" fill="#fff" stroke="#333" strokeWidth="2"/><circle cx="85" cy="89" r="4" fill="#333"/><circle cx="117" cy="89" r="4" fill="#333"/></>,
  <><ellipse cx="84" cy="88" rx="4" ry="8" fill="#333"/><ellipse cx="116" cy="88" rx="4" ry="8" fill="#333"/></>,
  <path d="M76 90q8-10 16 0M108 90q8-10 16 0" stroke="#333" strokeWidth="3" fill="none"/>,
];

function Character({ c }) {
  const m = mood(c);
  const eyes = m === 'tidur' || m === 'ngantuk'
    ? <path d="M78 88q6 5 12 0M110 88q6 5 12 0" stroke="#333" strokeWidth="3" fill="none"/>
    : EYES[c.eye_style || 0];
  const mouth = { senang: 'M85 108q15 14 30 0', sedih: 'M85 114q15-12 30 0', sakit: 'M88 112h24', lapar: 'M92 110q8 10 16 0', ngantuk: 'M92 112h16', tidur: 'M92 112h16' }[m];
  return (
    <svg viewBox="0 0 200 280" className={'char ' + (m === 'tidur' ? 'sleep' : '')}>
      <rect x="72" y="200" width="22" height="60" rx="8" fill="#4a5a78"/><rect x="106" y="200" width="22" height="60" rx="8" fill="#4a5a78"/>
      <ellipse cx="83" cy="264" rx="16" ry="8" fill="#fff"/><ellipse cx="117" cy="264" rx="16" ry="8" fill="#fff"/>
      <rect x="62" y="140" width="76" height="75" rx="18" fill={c.shirt}/>
      <rect x="44" y="144" width="20" height="60" rx="10" fill={c.shirt}/><rect x="136" y="144" width="20" height="60" rx="10" fill={c.shirt}/>
      <circle cx="54" cy="208" r="9" fill={c.skin}/><circle cx="146" cy="208" r="9" fill={c.skin}/>
      <rect x="90" y="125" width="20" height="22" fill={c.skin}/>
      {c.hair_style === 2 && <rect x="48" y="70" width="104" height="100" rx="34" fill={c.hair}/>}<circle cx="100" cy="90" r="48" fill={c.skin}/>
      {c.hair_style === 1 ? <path d="M52 84l8-40 16 20 12-32 12 32 16-20 8 40q-16-24-48-24t-48 24z" fill={c.hair}/> : <path d="M52 88q0-52 48-52t48 52q-16-26-48-26t-48 26z" fill={c.hair}/>}{c.hair_style === 3 && <circle cx="100" cy="30" r="14" fill={c.hair}/>}
      {c.accessory && <text x="100" y="42" fontSize="38" textAnchor="middle">{c.accessory}</text>}{eyes}<path d={mouth} stroke="#333" strokeWidth="3" fill="none" strokeLinecap="round"/>
      {m === 'sakit' && <rect x="60" y="62" width="80" height="8" rx="4" fill="#fff" opacity=".8"/>}
    </svg>
  );
}

const BARS = [['hunger', 'Lapar', '🍽️', '#f6a04d'], ['energy', 'Energi', '⚡', '#f4d03f'], ['clean', 'Bersih', '🛁', '#5dade2'],
  ['happy', 'Senang', '😊', '#f78fb3'], ['health', 'Sehat', '❤️', '#e74c3c'], ['social', 'Sosial', '💬', '#58d68d']];

function Auth() {
  const [email, setEmail] = useState(''); const [pw, setPw] = useState(''); const [msg, setMsg] = useState(''); const [up, setUp] = useState(false);
  async function submit(e) {
    e.preventDefault(); setMsg('');
    const { error, data } = up ? await supabase.auth.signUp({ email, password: pw }) : await supabase.auth.signInWithPassword({ email, password: pw });
    if (error) setMsg(error.message); else if (up && !data.session) setMsg('Cek email untuk konfirmasi, lalu masuk.');
  }
  return (
    <form className="auth card" onSubmit={submit}>
      <h1>Human Life Simulator</h1><p>Rawat karakter, bekerja, dan kembangkan hidupmu.</p>
      <input type="email" placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} required />
      <input type="password" placeholder="Kata sandi (min. 6)" value={pw} onChange={e => setPw(e.target.value)} minLength={6} required />
      <button className="big">{up ? 'Daftar' : 'Masuk'}</button>
      <a onClick={() => setUp(!up)}>{up ? 'Sudah punya akun? Masuk' : 'Belum punya akun? Daftar'}</a>
      {msg && <p className="err">{msg}</p>}
    </form>
  );
}

function Game() {
  const [s, setS] = useState(null); const [items, setItems] = useState([]); const [jobs, setJobs] = useState([]);
  const [tab, setTab] = useState('home'); const [d, setD] = useState(null); const [now, setNow] = useState(Date.now()); const [busy, setBusy] = useState(false); const [toast, setToast] = useState('');
  async function act(action, arg) {
    if (busy) return; setBusy(true);
    try { const r = await api(action, arg); setS(r); if (r.data) setD(r.data); setToast(''); } catch (e) { setToast(e.message); }
    setBusy(false);
  }
  useEffect(() => { const t = setInterval(() => setNow(Date.now()), 1000); return () => clearInterval(t); }, []);
  function go(k) { setTab(k); if (k === 'mission') act('missions'); if (k === 'social') act('friends'); }
  useEffect(() => {
    act('state');
    supabase.from('items').select('*').order('price').then(r => setItems(r.data || []));
    supabase.from('jobs').select('*').order('level_req').then(r => setJobs(r.data || []));
  }, []);
  if (!s) return <div className="load">Memuat…</div>;
  const room = s.room || [], c = s.character, inv = s.inventory, sleeping = !!c.sleep_start;
  const cd = Math.max(0, Math.ceil((new Date(c.work_ready_at) - now) / 1000));
  const left = c.work_end ? Math.max(0, Math.ceil((new Date(c.work_end) - now) / 1000)) : 0;
  return (
    <div className="app">
      <header><b>{c.name}</b><span>Lv {c.level} · {c.xp % 100}/100 XP · Hari {Math.floor((Date.now() - new Date(c.created_at)) / 864e5) + 1}</span><span>💰 {c.money}</span></header>
      <div className="bars">{BARS.map(([k, l, i, col]) => (
        <div key={k} className="bar"><span>{i} {l}</span><div><i style={{ width: c[k] + '%', background: col }} /></div></div>))}</div>
      <main>
        <Character c={c} /><p className="mood">Kondisi: {mood(c)}</p>
        {toast && <p className="err">{toast}</p>}
        {tab === 'home' && <div className="grid">
          {sleeping ? <button className="big" onClick={() => act('wake')}>☀️ Bangun</button> : <>
            <button onClick={() => act('sleep')}>😴 Tidur</button><button onClick={() => act('bathe')}>🛁 Mandi</button>
            <button onClick={() => act('play')}>🎮 Main</button><button onClick={() => act('social')}>💬 Ngobrol</button></>}
          {!sleeping && items.filter(i => i.kind === 'food' && inv[i.id]).map(i => (
            <button key={i.id} className="food" onClick={() => act('eat', i.id)}>{i.icon} {i.name} ×{inv[i.id]}</button>))}
        </div>}
        {tab === 'shop' && <div className="list">{items.map(i => (
          <div key={i.id} className="card row"><span>{i.icon} {i.name}<small>{i.kind === 'food' ? '+' + i.hunger + ' lapar' : i.kind === 'clothing' ? 'Pakaian' : 'Furnitur'}</small></span>
            <button disabled={busy || c.money < i.price} onClick={() => act('buy', i.id)}>💰 {i.price}</button></div>))}</div>}
        {tab === 'work' && <div className="list">
          {c.work_job && <div className="card">💼 Sedang bekerja: {jobs.find(j => j.id === c.work_job)?.name}<br />{left > 0 ? 'Selesai dalam ' + left + ' dtk' : 'Selesai!'}
            <button disabled={busy || left > 0} onClick={() => act('work_done')}>Ambil gaji</button></div>}
          {!c.work_job && cd > 0 && <p>Cooldown {cd} dtk</p>}
          {jobs.map(j => (<div key={j.id} className="card row"><span>{j.name}<small>Lv{j.level_req} · {j.duration_sec} dtk · ⚡{j.energy_cost} · +{j.pay} · {j.xp}XP</small></span>
            <button disabled={busy || sleeping || !!c.work_job || cd > 0 || c.level < j.level_req} onClick={() => act('work', j.id)}>Kerja</button></div>))}</div>}
        {tab === 'room' && <div className="list">
          <div className="card roombox">{items.filter(i => room.includes(i.id)).map(i => <span key={i.id}>{i.icon}</span>)}{!room.length && 'Kamar masih kosong'}</div>
          <div className="card list">{items.filter(i => i.kind !== 'food' && inv[i.id]).map(i => (
            <div key={i.id} className="row"><span>{i.icon} {i.name}</span>
              {i.kind === 'clothing' ? <button onClick={() => act('equip', i.id)}>Pakai</button>
                : <button onClick={() => act('place', i.id)}>{room.includes(i.id) ? 'Lepas' : 'Pasang'}</button>}</div>))}
            <button onClick={() => act('equip', 'none')}>Lepas aksesori</button></div>
          <div className="card list">{[['skin', 'Kulit'], ['hair', 'Rambut'], ['shirt', 'Baju']].map(([k, l]) => (
            <label key={k} className="row">{l}<input type="color" value={c[k]} onChange={e => act('style', k + ':' + e.target.value)} /></label>))}
            <button onClick={() => act('style', 'hair_style:' + (((c.hair_style || 0) + 1) % 4))}>💇 Gaya rambut</button>
            <button onClick={() => act('style', 'eye_style:' + (((c.eye_style || 0) + 1) % 4))}>👀 Gaya mata</button>
            <input defaultValue={c.name} maxLength={20} onBlur={e => e.target.value !== c.name && act('rename', e.target.value)} />
            <button onClick={() => supabase.auth.signOut()}>Keluar</button></div></div>}
        {tab === 'mission' && d?.missions && <div className="list">
          <button onClick={() => act('daily')}>🎁 Hadiah login harian (+50)</button>
          {d.missions.map(m => (<div key={m.id} className="card row"><span>{m.title}<small>{m.kind === 'daily' ? 'Harian' : 'Mingguan'} · {Math.min(m.progress, m.target)}/{m.target} · 💰{m.money} · {m.xp}XP</small></span>
            <button disabled={busy || m.claimed || m.progress < m.target} onClick={() => act('claim', m.id)}>{m.claimed ? '✓' : 'Klaim'}</button></div>))}
          <h3>Achievement</h3>
          {d.achievements.map(a => (<div key={a.id} className="card row"><span>{a.title}<small>{Math.min(a.n, a.target)}/{a.target} · 💰{a.money}</small></span>
            <button disabled={busy || a.claimed || a.n < a.target} onClick={() => act('claim_ach', a.id)}>{a.claimed ? '✓' : 'Klaim'}</button></div>))}</div>}
        {tab === 'social' && d?.friends && <div className="list">
          <div className="card">Kode temanmu: <b>{d.code}</b></div>
          <form className="card row" onSubmit={e => { e.preventDefault(); act('friend_add', e.target.k.value); e.target.reset(); }}>
            <input name="k" placeholder="Kode teman" required /><button>Tambah</button></form>
          {d.friends.map(f => (<div key={f.code} className="card"><b>{f.name}</b> · Lv {f.level}<div className="roombox">{f.room.join(' ') || 'Kamar kosong'}</div>
            {items.filter(i => i.kind === 'food' && inv[i.id]).map(i => <button key={i.id} onClick={() => act('gift', f.code + ':' + i.id)}>Kirim {i.icon}</button>)}</div>))}
          <h3>Papan peringkat</h3>
          {d.board.map((b, n) => <div key={n} className="card row"><span>#{n + 1} {b.name}</span><span>Lv {b.level}</span></div>)}</div>}
      </main>
      <nav>{[['home', '🏠', 'Rumah'], ['shop', '🛒', 'Toko'], ['work', '💼', 'Kerja'], ['mission', '🎯', 'Misi'], ['room', '🛏️', 'Kamar'], ['social', '👥', 'Sosial']].map(([k, i, l]) => (
        <button key={k} className={tab === k ? 'on' : ''} onClick={() => go(k)}>{i}<small>{l}</small></button>))}</nav>
    </div>
  );
}

export default function App() {
  const [session, setSession] = useState(undefined);
  useEffect(() => {
    const tg = window.Telegram?.WebApp;
    if (tg?.initData) {
      tg.ready(); tg.expand();
      fetch('/api/telegram-auth', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ initData: tg.initData }) })
        .then(r => (r.ok ? r.json() : null)).then(t => t && supabase.auth.setSession(t));
    }
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => data.subscription.unsubscribe();
  }, []);
  if (session === undefined) return <div className="load">Memuat…</div>;
  return session ? <Game key={session.user.id} /> : <Auth />;
}
