import crypto from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const opt = { auth: { persistSession: false } };
const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, opt);
const anon = createClient(process.env.SUPABASE_URL, process.env.VITE_SUPABASE_ANON_KEY, opt);

// Validasi resmi Telegram: HMAC-SHA256 dengan kunci HMAC("WebAppData", bot_token)
function verify(initData, token) {
  const p = new URLSearchParams(initData);
  const hash = p.get('hash'); p.delete('hash');
  const str = [...p.entries()].map(([k, v]) => k + '=' + v).sort().join('\n');
  const secret = crypto.createHmac('sha256', 'WebAppData').update(token).digest();
  const calc = crypto.createHmac('sha256', secret).update(str).digest('hex');
  if (!hash || hash.length !== calc.length || !crypto.timingSafeEqual(Buffer.from(calc), Buffer.from(hash))) return null;
  if (Date.now() / 1000 - Number(p.get('auth_date')) > 86400) return null;
  try { return JSON.parse(p.get('user')); } catch { return null; }
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method tidak diizinkan' });
  const user = verify(String(req.body?.initData || ''), process.env.TELEGRAM_BOT_TOKEN);
  if (!user?.id) return res.status(401).json({ error: 'initData tidak valid' });
  const email = `tg_${user.id}@telegram.local`;
  // Password hanya diketahui server (HMAC rahasia), tidak pernah dikirim ke klien.
  const password = crypto.createHmac('sha256', process.env.TELEGRAM_LOGIN_SECRET).update('pw' + user.id).digest('hex');
  await admin.auth.admin.createUser({ email, password, email_confirm: true }); // error "sudah ada" diabaikan
  const { data, error } = await anon.auth.signInWithPassword({ email, password });
  if (error) return res.status(500).json({ error: 'Gagal masuk' });
  res.json({ access_token: data.session.access_token, refresh_token: data.session.refresh_token });
}
