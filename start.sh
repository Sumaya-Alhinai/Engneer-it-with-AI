#!/usr/bin/env bash
set -u

echo ""
echo "========================================"
echo "   أمان AI — التشغيل التلقائي"
echo "========================================"
echo ""

if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker مو شغّال. افتحي Docker Desktop وأعيدي المحاولة."
    exit 1
fi
echo "✅ [1/4] Docker شغّال"

echo "⏳ [2/4] تشغيل قاعدة البيانات والباك-إند و n8n... (أول مرة 3-5 دقائق)"
docker compose up -d --build || { echo "❌ فشل تشغيل الحاويات"; exit 1; }

echo "⏳ [3/4] انتظار جاهزية الباك-إند..."
for i in $(seq 1 60); do
    if curl -sf http://localhost:4000/ > /dev/null 2>&1; then
        echo "✅ الباك-إند جاهز على http://localhost:4000"
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "❌ الباك-إند ما ردّ خلال دقيقتين. شوفي: docker compose logs backend"
        exit 1
    fi
    sleep 2
done

echo "⏳ [4/4] استيراد وركفلو الوكلاء إلى n8n..."
sleep 5
if docker compose exec -T n8n n8n import:workflow --separate --input=/home/node/n8n-workflows > /dev/null 2>&1; then
    echo "✅ تم الاستيراد"
else
    echo "⚠️  الاستيراد التلقائي ما ضبط — استورديها يدويًا من واجهة n8n"
fi

cat << 'MSG'

========================================
   ✅ جاهز
========================================

  الباك-إند:  http://localhost:4000
  n8n:        http://localhost:5678

  باقي عليك بـ n8n (مرة وحدة فقط):
    1. أنشئي حساب محلي — أي إيميل وباسورد
    2. أضيفي مفتاح OpenAI من Settings → Credentials
    3. فعّلي كل وركفلو (مفتاح Active فوق يمين)

  كود دخول الداشبورد:  DEV-ADMIN-7f2a

  لتشغيل الداشبورد بنافذة جديدة:
    cd dashboard && npm install && npm run dev

  لإيقاف كل شي:   docker compose down

MSG
