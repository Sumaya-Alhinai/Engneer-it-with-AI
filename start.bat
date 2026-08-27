@echo off
chcp 65001 > nul
setlocal

echo.
echo ========================================
echo    أمان AI - التشغيل التلقائي
echo ========================================
echo.

REM ---------- فحص Docker ----------
docker info > nul 2>&1
if errorlevel 1 (
    echo [خطأ] Docker مو شغّال.
    echo افتحي Docker Desktop وانتظري لين يصير أخضر، ثم أعيدي تشغيل هذا الملف.
    pause
    exit /b 1
)
echo [1/4] Docker شغّال

REM ---------- تشغيل الخدمات ----------
echo [2/4] تشغيل قاعدة البيانات والباك-إند و n8n...
echo       (أول مرة تاخذ 3-5 دقائق)
docker compose up -d --build
if errorlevel 1 (
    echo [خطأ] فشل تشغيل الحاويات. شوفي الرسالة فوق.
    pause
    exit /b 1
)

REM ---------- انتظار جاهزية الباك-إند ----------
echo [3/4] انتظار جاهزية الباك-إند...
set /a tries=0
:waitloop
set /a tries+=1
curl -s -o nul http://localhost:4000/ 2>nul
if not errorlevel 1 goto ready
if %tries% geq 60 (
    echo [خطأ] الباك-إند ما ردّ خلال دقيقتين.
    echo شوفي السجلات:  docker compose logs backend
    pause
    exit /b 1
)
timeout /t 2 /nobreak > nul
goto waitloop

:ready
echo       الباك-إند جاهز على http://localhost:4000

REM ---------- استيراد وركفلو n8n ----------
echo [4/4] استيراد وركفلو الوكلاء إلى n8n...
timeout /t 5 /nobreak > nul
docker compose exec -T n8n n8n import:workflow --separate --input=/home/node/n8n-workflows 2>nul
if errorlevel 1 (
    echo       [تنبيه] الاستيراد التلقائي ما ضبط - استورديها يدويًا من واجهة n8n
) else (
    echo       تم الاستيراد
)

echo.
echo ========================================
echo    جاهز
echo ========================================
echo.
echo   الباك-إند:  http://localhost:4000
echo   n8n:        http://localhost:5678
echo.
echo   باقي عليك خطوتين بـ n8n (مرة وحدة فقط):
echo     1. أنشئي حساب محلي - أي إيميل وباسورد
echo     2. أضيفي مفتاح OpenAI من Settings ثم Credentials
echo     3. فعّلي كل وركفلو - مفتاح Active فوق يمين
echo.
echo   كود دخول الداشبورد:  DEV-ADMIN-7f2a
echo.
echo   لتشغيل الداشبورد بنافذة جديدة:
echo     cd dashboard ^&^& npm install ^&^& npm run dev
echo.
echo   لإيقاف كل شي:   docker compose down
echo.
pause
