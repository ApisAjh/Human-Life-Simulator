import { createClient } from '@supabase/supabase-js';

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method tidak diizinkan' });
  const token = (req.headers.authorization || '').replace('Bearer ', '');
  const { data, error } = await sb.auth.getUser(token);
  if (error || !data?.user) return res.status(401).json({ error: 'Belum login' });
  const { action, arg } = req.body || {};
  const { data: out, error: e } = await sb.rpc('game_action', {
    p_user: data.user.id,
    p_action: String(action || ''),
    p_arg: arg == null ? null : String(arg),
  });
  if (e) return res.status(400).json({ error: e.message });
  res.status(200).json(out);
}
