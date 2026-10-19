export default async function handler(req, res) {
  if (req.headers['x-telegram-bot-api-secret-token'] !== process.env.TELEGRAM_WEBHOOK_SECRET) return res.status(401).end();
  const msg = req.body?.message;
  if (msg?.text?.startsWith('/start')) {
    await fetch(`https://api.telegram.org/bot${process.env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: msg.chat.id, text: 'Selamat datang di Human Life Simulator! 🏠',
        reply_markup: { inline_keyboard: [[{ text: '🎮 Main', web_app: { url: process.env.APP_URL } }]] } }),
    });
  }
  res.status(200).json({ ok: true });
}
