"""
إرسال رموز التحقق عبر مزوّد حقيقي (بريد أو SMS) بدل الطباعة بالسجلات.

⚠️ لماذا كانت الطباعة بالسجلات مشكلة حقيقية وليست مجرد "غير مكتمل":
1. الرمز يظهر نصًّا صريحًا بسجلات Render، وكل من يملك وصولًا للوحة (أي عضو
   بالفريق، أو أي خدمة تجميع سجلات) يقدر يقرأ رمز تفعيل أي حساب ويستولي عليه.
2. المواطن لا يستلم شيئًا إطلاقًا، أي أن التسجيل لا يعمل بالإنتاج أصلًا.

المزوّد يُختار بمتغير البيئة NOTIFY_PROVIDER:
  console (افتراضي) — طباعة بالسجلات، للتطوير المحلي فقط
  resend           — بريد إلكتروني عبر Resend
  twilio           — رسائل SMS عبر Twilio

لا يحتاج أي منها مكتبة إضافية: كلاهما REST عادي عبر httpx الموجودة أصلًا.
"""
import os

import httpx

PROVIDER = os.getenv("NOTIFY_PROVIDER", "console").lower()
TIMEOUT = float(os.getenv("NOTIFY_TIMEOUT", "10"))

# Resend
RESEND_API_KEY = os.getenv("RESEND_API_KEY", "")
RESEND_FROM = os.getenv("RESEND_FROM", "Aman AI <onboarding@resend.dev>")

# Twilio
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN", "")
TWILIO_FROM = os.getenv("TWILIO_FROM", "")


class NotificationError(Exception):
    """يُرفع عند فشل الإرسال — يلتقطه المستدعي ويحوّله لخطأ 502 للمستخدم."""


def _send_via_resend(destination: str, code: str) -> None:
    if not RESEND_API_KEY:
        raise NotificationError("RESEND_API_KEY غير مضبوط")
    html = f"""
    <div dir="rtl" style="font-family:system-ui,sans-serif;max-width:480px;margin:auto">
      <h2 style="color:#0f3d5c">أمان AI</h2>
      <p>رمز التحقق الخاص بك:</p>
      <p style="font-size:32px;letter-spacing:8px;font-weight:700;color:#0f3d5c">{code}</p>
      <p style="color:#666;font-size:14px">صالح لمدة 15 دقيقة. إذا لم تطلب هذا الرمز، تجاهل الرسالة.</p>
    </div>
    """
    resp = httpx.post(
        "https://api.resend.com/emails",
        headers={"Authorization": f"Bearer {RESEND_API_KEY}"},
        json={"from": RESEND_FROM, "to": [destination],
              "subject": f"رمز التحقق: {code}", "html": html},
        timeout=TIMEOUT,
    )
    if resp.status_code >= 400:
        raise NotificationError(f"Resend رفض الإرسال {resp.status_code}: {resp.text[:200]}")


def _send_via_twilio(destination: str, code: str) -> None:
    if not (TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN and TWILIO_FROM):
        raise NotificationError("بيانات اعتماد Twilio غير مكتملة")
    resp = httpx.post(
        f"https://api.twilio.com/2010-04-01/Accounts/{TWILIO_ACCOUNT_SID}/Messages.json",
        auth=(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN),
        data={"From": TWILIO_FROM, "To": destination,
              "Body": f"رمز التحقق لتطبيق أمان AI: {code}\nصالح 15 دقيقة."},
        timeout=TIMEOUT,
    )
    if resp.status_code >= 400:
        raise NotificationError(f"Twilio رفض الإرسال {resp.status_code}: {resp.text[:200]}")


def send_verification_code(channel: str, destination: str, code: str) -> None:
    """channel: 'email' | 'phone'. يرفع NotificationError عند الفشل."""
    if PROVIDER == "console":
        print(f"📩 [{channel}] رمز التحقق لـ {destination}: {code}")
        return

    if PROVIDER == "resend":
        _send_via_resend(destination, code)
    elif PROVIDER == "twilio":
        _send_via_twilio(destination, code)
    else:
        raise NotificationError(f"مزوّد غير معروف: {PROVIDER}")

    # نسجّل الوجهة فقط — الرمز نفسه لا يُطبع أبدًا خارج وضع console
    print(f"📩 [{channel}] أُرسل رمز التحقق إلى {destination} عبر {PROVIDER}")


def provider_health() -> dict:
    """يُستخدم بفحص الإقلاع للتنبيه على إعداد ناقص قبل أن يكتشفه مستخدم حقيقي."""
    if PROVIDER == "console":
        return {"provider": "console", "ready": True,
                "warning": "الرموز تُطبع بالسجلات — للتطوير فقط، لا تستخدمه بالإنتاج"}
    if PROVIDER == "resend":
        return {"provider": "resend", "ready": bool(RESEND_API_KEY),
                "warning": None if RESEND_API_KEY else "RESEND_API_KEY فارغ"}
    if PROVIDER == "twilio":
        ready = bool(TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN and TWILIO_FROM)
        return {"provider": "twilio", "ready": ready,
                "warning": None if ready else "بيانات اعتماد Twilio ناقصة"}
    return {"provider": PROVIDER, "ready": False, "warning": f"مزوّد غير معروف: {PROVIDER}"}
