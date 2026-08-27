"""
اختبارات آلية للأمان والمسار الطبيعي.

لماذا هذا الملف موجود: كل الضوابط الأمنية بالمشروع اختُبرت يدويًا مرة واحدة.
بدون اختبارات آلية، أي تعديل لاحق يقدر يفتح ثغرة مغلقة بصمت — تُحذف
Depends(require_user) بالخطأ أثناء إعادة ترتيب، ولا شيء يصرخ.
كل اختبار هنا يقابل ثغرة حقيقية أُغلقت.

التشغيل:
    cd aman-backend
    DATABASE_URL=postgresql://... pytest tests/ -v
"""
import io
import os
import uuid

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("N8N_CALLBACK_SECRET", "test_secret_for_pytest")
os.environ.setdefault("ALLOWED_ORIGINS", "http://localhost:5173")
os.environ["RATE_LIMIT_ENABLED"] = "false"   # يُفعَّل داخل اختباره الخاص فقط
os.environ["N8N_RETRY_WORKER"] = "false"     # لا نريد عاملًا خلفيًا أثناء الاختبار
os.environ["GEOCODE_ENABLED"] = "false"      # لا نداءات شبكة أثناء الاختبار
# ربط التكرار يُعطَّل افتراضيًا هنا: أغلب الاختبارات تنشئ بلاغات متطابقة عمدًا،
# وتركه فعّالًا يجعلها تُربط كتأكيدات فتختفي من قوائم الموظفين. له صنفه الخاص أدناه.
os.environ["DEDUP_ENABLED"] = "false"

from app.main import app  # noqa: E402
from app.db import get_conn  # noqa: E402

WEBHOOK_SECRET = os.environ["N8N_CALLBACK_SECRET"]


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture
def guest(client):
    """جلسة ضيف جديدة لكل اختبار."""
    body = client.post("/api/auth/guest").json()
    return {"user_id": body["user_id"], "headers": {"x-user-token": body["token"]}}


@pytest.fixture
def staff(client):
    code = f"TEST-{uuid.uuid4().hex[:10]}"
    with get_conn() as conn:
        conn.execute(
            "INSERT INTO staff (access_code, label, department, is_admin) VALUES (%s, %s, NULL, TRUE)",
            (code, "موظف اختبار"),
        )
        conn.commit()
    token = client.post("/api/auth/staff/login", json={"code": code}).json()["token"]
    yield {"headers": {"x-staff-token": token}}
    with get_conn() as conn:
        conn.execute("DELETE FROM staff WHERE access_code = %s", (code,))
        conn.commit()


def make_report(client, guest, **overrides):
    data = {"type": "حريق", "description": "حريق بمستودع", "latitude": 23.5933, "longitude": 58.2844}
    data.update(overrides)
    r = client.post("/api/reports", headers=guest["headers"], data=data)
    assert r.status_code == 200, r.text
    return r.json()["report_id"]


def png_bytes(width=400, height=300):
    """صورة PNG حقيقية.

    كانت هذه الدالة ترجع ترويسة PNG وحدها متبوعة بأصفار — بايتات ليست صورة.
    مرّت طويلًا لأن فشل معالجة الصورة كان يُتجاهل بصمت، وكشفها الفشل المغلق
    فور تفعيله: الخادم صار يرفض أي صورة يتعذّر تمويهها، وهو السلوك الصحيح."""
    from PIL import Image as _Image
    buf = io.BytesIO()
    _Image.new("RGB", (width, height), (90, 110, 160)).save(buf, "PNG")
    return buf.getvalue()


# ============== المصادقة والهوية ==============

class TestIdentity:
    def test_guest_id_comes_from_server(self, client):
        body = client.post("/api/auth/guest").json()
        assert body["user_id"].startswith("GUEST-") and body["token"]

    def test_cannot_impersonate_registered_user(self, client):
        """الثغرة: user_id كان حقلًا نصيًا موثوقًا — أي شخص يبلّغ باسم أي مواطن."""
        r = client.post("/api/reports", data={"user_id": "USR-1234", "description": "منتحل"})
        assert r.status_code == 401

    def test_submitted_user_id_is_ignored(self, client, guest):
        r = client.post("/api/reports", headers=guest["headers"],
                        data={"user_id": "USR-9999", "description": "محاولة تزوير"})
        assert r.json()["user_id"] == guest["user_id"]

    def test_logout_invalidates_token(self, client, guest):
        client.post("/api/auth/logout", headers=guest["headers"])
        assert client.get("/api/reports", headers=guest["headers"]).status_code == 401


# ============== قراءة البلاغات ==============

class TestReportAccess:
    def test_listing_requires_auth(self, client):
        """الثغرة الأخطر: كان يرجع آخر 200 بلاغ لكل المستخدمين بلا مصادقة."""
        assert client.get("/api/reports").status_code == 401

    def test_listing_scoped_to_token_owner(self, client, guest):
        make_report(client, guest)
        rows = client.get("/api/reports?user_id=USR-1234", headers=guest["headers"]).json()
        assert all(r["user_id"] == guest["user_id"] for r in rows)

    def test_idor_blocked(self, client, guest):
        """قراءة بلاغ شخص آخر برقمه."""
        code = make_report(client, guest)
        other = client.post("/api/auth/guest").json()
        r = client.get(f"/api/reports/{code}", headers={"x-user-token": other["token"]})
        assert r.status_code == 404, "يجب 404 لا 403 حتى لا نؤكد وجود الرقم"

    def test_owner_can_read(self, client, guest):
        code = make_report(client, guest)
        assert client.get(f"/api/reports/{code}", headers=guest["headers"]).status_code == 200

    def test_detail_requires_auth(self, client, guest):
        code = make_report(client, guest)
        assert client.get(f"/api/reports/{code}").status_code == 401


class TestReportCodes:
    def test_codes_are_not_sequential(self, client, guest):
        """الصيغة القديمة AMN-1001/1002 كانت تسرّب عدد البلاغات ومعدّل ورودها."""
        codes = [make_report(client, guest) for _ in range(3)]
        assert len(set(codes)) == 3
        suffixes = [c.split("-")[1] for c in codes]
        assert not all(s.isdigit() for s in suffixes)
        assert all(len(s) == 8 for s in suffixes)


class TestPublicFeed:
    def test_feed_is_redacted(self, client, guest):
        make_report(client, guest, description="اسم صريح وتفاصيل حساسة", latitude=23.67891)
        feed = client.get("/api/reports/public").json()
        assert feed, "الخلاصة فارغة"
        for item in feed:
            assert "description" not in item
            assert "user_id" not in item
            assert "media_paths" not in item

    def test_coordinates_are_coarse(self, client, guest):
        make_report(client, guest, latitude=23.67891, longitude=58.18234)
        located = [f for f in client.get("/api/reports/public").json() if f["latitude"]]
        assert located and located[0]["latitude"] == round(located[0]["latitude"], 2)


# ============== رفع الملفات ==============

class TestUploads:
    def test_path_traversal_blocked(self, client, guest, tmp_path):
        """اسم مثل ../../app/main.py كان يكتب خارج مجلد الرفع."""
        r = client.post("/api/reports", headers=guest["headers"], data={"description": "مسار"},
                        files={"media": ("../../app/main.py", io.BytesIO(png_bytes()), "image/png")})
        assert r.status_code == 200
        names = os.listdir("uploads/evidence")
        assert all(".." not in n and "/" not in n for n in names)

    def test_iphone_heic_is_converted_and_blurred(self, client, guest):
        """صور آيفون: كانت تُحفظ بلا تمويه لأن OpenCV لا يكتب ‎.heic،
        والخادم يرد بنجاح — فشل صامت للخصوصية."""
        from PIL import Image as _Image
        buf = io.BytesIO()
        _Image.new("RGB", (600, 400), (80, 100, 150)).save(buf, "HEIF")
        before = set(os.listdir("uploads/evidence"))
        r = client.post("/api/reports", headers=guest["headers"], data={"description": "من آيفون"},
                        files={"media": ("IMG_1.heic", io.BytesIO(buf.getvalue()), "image/heic")})
        assert r.status_code == 200
        added = [n for n in set(os.listdir("uploads/evidence")) - before]
        assert added and added[0].endswith(".jpg"), "يجب التحويل إلى JPG"

    def test_unprocessable_image_rejected_not_stored(self, client, guest):
        """فشل مغلق: صورة تعذّر تمويهها لا تُحفظ إطلاقًا."""
        before = set(os.listdir("uploads/evidence"))
        r = client.post("/api/reports", headers=guest["headers"], data={"description": "تالف"},
                        files={"media": ("bad.jpg", io.BytesIO(b"NOT_AN_IMAGE" * 50), "image/jpeg")})
        assert r.status_code == 422
        assert set(os.listdir("uploads/evidence")) == before

    def test_camera_exif_survives_conversion(self, client, guest, staff):
        """بيانات الكاميرا يجب أن تنجو من التوحيد إلى JPEG — هي أساس التحقق."""
        import piexif
        from PIL import Image as _Image
        buf = io.BytesIO()
        exif = piexif.dump({
            "0th": {piexif.ImageIFD.Make: b"Apple", piexif.ImageIFD.Model: b"iPhone 15"},
            "Exif": {piexif.ExifIFD.DateTimeOriginal: b"2026:08:27 01:55:00"},
        })
        _Image.new("RGB", (800, 600), (100, 120, 160)).save(buf, "JPEG", exif=exif)
        r = client.post("/api/reports", headers=guest["headers"],
                        data={"description": "بصورة كاميرا", "latitude": 23.5933, "longitude": 58.2844},
                        files={"media": ("IMG.jpg", io.BytesIO(buf.getvalue()), "image/jpeg")})
        assert r.status_code == 200
        rows = client.get("/api/reports/staff", headers=staff["headers"]).json()
        row = next(x for x in rows if x["report_id"] == r.json()["report_id"])
        check = row["media_verification"][0]
        assert check["has_exif"] is True, "بيانات الكاميرا ضاعت أثناء المعالجة"
        assert any("iPhone" in f["message"] for f in check["flags"])

    def test_disallowed_type_rejected(self, client, guest):
        r = client.post("/api/reports", headers=guest["headers"], data={"description": "x"},
                        files={"media": ("shell.php", io.BytesIO(b"<?php ?>"), "application/x-php")})
        assert r.status_code == 400

    def test_oversized_rejected(self, client, guest):
        big = png_bytes(4000, 3000) + b"\x00" * (6 * 1024 * 1024)
        r = client.post("/api/reports", headers=guest["headers"], data={"description": "كبير"},
                        files={"media": ("big.png", io.BytesIO(big), "image/png")})
        assert r.status_code == 413

    def test_rejected_upload_leaves_no_file(self, client, guest):
        before = set(os.listdir("uploads/evidence"))
        client.post("/api/reports", headers=guest["headers"], data={"description": "كبير"},
                    files={"media": ("leak.png", io.BytesIO(png_bytes(4000, 3000) + b"\x00" * (6 * 1024 * 1024)), "image/png")})
        assert not [n for n in set(os.listdir("uploads/evidence")) - before if "leak" in n]

    def test_arabic_filename_preserved(self, client, guest):
        r = client.post("/api/reports", headers=guest["headers"], data={"description": "عربي"},
                        files={"media": ("حادث.png", io.BytesIO(png_bytes()), "image/png")})
        code = r.json()["report_id"]
        paths = client.get(f"/api/reports/{code}", headers=guest["headers"]).json()["media_paths"]
        assert "حادث" in paths[0]

    def test_too_many_files_rejected(self, client, guest):
        files = [("media", (f"f{i}.png", io.BytesIO(png_bytes()), "image/png")) for i in range(6)]
        r = client.post("/api/reports", headers=guest["headers"], data={"description": "كثير"}, files=files)
        assert r.status_code == 400


# ============== مسار n8n ==============

class TestPipelineCallback:
    def test_requires_secret(self, client, guest):
        code = make_report(client, guest)
        r = client.patch(f"/api/reports/{code}/classification", json={"status": "rejected"})
        assert r.status_code == 401

    def test_wrong_secret_rejected(self, client, guest):
        code = make_report(client, guest)
        r = client.patch(f"/api/reports/{code}/classification",
                         headers={"x-webhook-secret": "wrong"}, json={"priority": "low"})
        assert r.status_code == 401

    @pytest.mark.parametrize("sent,expected", [
        (1, 1),        # ⚠️ كانت تُحوَّل إلى 100 — انقلاب كامل للمعنى
        (0.9, 1),      # كسر صغير يبقى صغيرًا
        (8, 8),        # كانت تُحوَّل إلى 80
        (60, 60),
        (75, 75),
        (100, 100),
        (150, 100),    # خارج المدى يُقصّ
        ("55", 55),
        (-5, 0),
    ])
    def test_risk_score_normalised(self, client, guest, sent, expected):
        """المقياس موحّد 0-100 بلا إعادة قياس.

        الاختبار يحرس ضد خطأ حقيقي وقع: قيمة 1 (لا خطر تقريبًا) كانت تُعرض
        بـ 100% (خطورة قصوى) لأن الدالة افترضت أن 0-1 نسبة كسرية."""
        code = make_report(client, guest)
        r = client.patch(f"/api/reports/{code}/classification",
                         headers={"x-webhook-secret": WEBHOOK_SECRET}, json={"risk_score": sent})
        assert r.json()["risk_score"] == expected

    def test_callback_closes_pipeline(self, client, guest, staff):
        code = make_report(client, guest)
        client.patch(f"/api/reports/{code}/classification",
                     headers={"x-webhook-secret": WEBHOOK_SECRET},
                     json={"department": "Police", "priority": "high"})
        rows = client.get("/api/reports/staff", headers=staff["headers"]).json()
        row = next(r for r in rows if r["report_id"] == code)
        assert row["pipeline_status"] == "completed"


# ============== صلاحيات الموظفين ==============

class TestStaffAccess:
    def test_staff_routes_require_token(self, client):
        assert client.get("/api/reports/staff").status_code == 401
        assert client.get("/api/reports/needs-review").status_code == 401

    def test_response_unit_locations_protected(self, client):
        """مواقع الدوريات والإسعاف كانت مكشوفة للجميع."""
        assert client.get("/nearest-unit?lat=23.6&lng=58.3").status_code == 401

    def test_staff_can_query_units(self, client, staff):
        r = client.get("/nearest-unit?lat=23.6&lng=58.3", headers=staff["headers"])
        assert r.status_code in (200, 404)

    def test_exif_only_for_staff(self, client, guest, staff):
        code = make_report(client, guest)
        citizen_view = client.get(f"/api/reports/{code}", headers=guest["headers"]).json()
        assert "media_exif" not in citizen_view
        staff_rows = client.get("/api/reports/staff", headers=staff["headers"]).json()
        assert "media_exif" in next(r for r in staff_rows if r["report_id"] == code)

    def test_unknown_status_rejected(self, client, guest, staff):
        code = make_report(client, guest)
        r = client.patch(f"/api/reports/{code}/status",
                         headers=staff["headers"], json={"status": "اختراق"})
        assert r.status_code == 400


# ============== المسارات القديمة ==============

class TestLegacyRemoved:
    @pytest.mark.parametrize("method,path", [
        ("post", "/reports"), ("post", "/reports-with-image"), ("get", "/image-info"),
    ])
    def test_removed(self, client, method, path):
        assert getattr(client, method)(path).status_code == 404


# ============== ترويسات وحدود ==============

class TestHardening:
    def test_security_headers(self, client):
        h = client.get("/").headers
        assert h["x-content-type-options"] == "nosniff"
        assert h["x-frame-options"] == "DENY"

    def test_empty_report_rejected(self, client, guest):
        r = client.post("/api/reports", headers=guest["headers"], data={"description": "  "})
        assert r.status_code == 400

    def test_short_password_rejected(self, client):
        r = client.post("/api/auth/register",
                        json={"name": "ت", "email": f"{uuid.uuid4().hex}@x.com", "password": "123"})
        assert r.status_code == 400

    def test_rate_limit_enforced(self, client, guest, monkeypatch):
        monkeypatch.setenv("RATE_LIMIT_ENABLED", "true")
        codes = [client.post("/api/reports", headers=guest["headers"],
                             data={"description": f"سيل {i}"}).status_code for i in range(9)]
        assert 429 in codes

    def test_verification_code_attempts_capped(self, client):
        email = f"{uuid.uuid4().hex}@x.com"
        client.post("/api/auth/register", json={"name": "ت", "email": email, "password": "password123"})
        codes = [client.post("/api/auth/verify-email",
                             json={"email": email, "code": "000000"}).status_code for _ in range(7)]
        assert 429 in codes


# ============== ربط البلاغات المكررة ==============

class TestDeduplication:
    """حريق واحد يولّد عدة بلاغات — يجب أن يظهر كحادث واحد مؤكَّد."""

    @pytest.fixture(autouse=True)
    def enable_dedup(self, monkeypatch):
        import app.deduplication as dedup
        monkeypatch.setattr(dedup, "DEDUP_ENABLED", True)

    @pytest.fixture
    def spot(self):
        """إحداثيات عشوائية لكل اختبار.

        بدونها تتداخل الاختبارات: قاعدة الاختبار تحتفظ ببلاغات التشغيلات
        السابقة، وبلاغ "بعيد" قد يصادف بلاغًا قديمًا بنفس النقطة فيُربط به —
        وهو سلوك صحيح للنظام لكنه يُفشل الاختبار لسبب لا علاقة له بالمنطق.
        """
        import random
        return {"latitude": round(random.uniform(20.0, 22.0), 5),
                "longitude": round(random.uniform(54.0, 56.0), 5)}

    def test_nearby_same_type_is_linked(self, client, spot):
        base = {"type": "fire", "description": "حريق", **spot}
        first = client.post("/api/reports", headers=self._guest(client), data=base).json()
        second = client.post("/api/reports", headers=self._guest(client),
                             data={**base, "latitude": spot["latitude"] + 0.0003}).json()
        assert first["is_confirmation"] is False
        assert second["is_confirmation"] is True
        assert second["linked_to"] == first["report_id"]

    def test_different_type_not_linked(self, client, spot):
        base = spot
        client.post("/api/reports", headers=self._guest(client),
                    data={**base, "type": "fire", "description": "حريق"})
        other = client.post("/api/reports", headers=self._guest(client),
                            data={**base, "type": "medical", "description": "إغماء"}).json()
        assert other["is_confirmation"] is False

    def test_far_away_not_linked(self, client, spot):
        client.post("/api/reports", headers=self._guest(client),
                    data={"type": "fire", "description": "حريق", **spot})
        far = client.post("/api/reports", headers=self._guest(client),
                          data={"type": "fire", "description": "حريق",
                                "latitude": spot["latitude"] + 1.5,      # ~165 كم
                                "longitude": spot["longitude"] + 1.5}).json()
        assert far["is_confirmation"] is False

    def test_confirmations_raise_credibility(self, client, staff, spot):
        base = {"type": "flood", "description": "انحباس مياه", **spot}
        parent = client.post("/api/reports", headers=self._guest(client), data=base).json()
        for i in range(3):
            client.post("/api/reports", headers=self._guest(client),
                        data={**base, "latitude": spot["latitude"] + i * 0.0005})
        rows = client.get("/api/reports/staff", headers=staff["headers"]).json()
        row = next(r for r in rows if r["report_id"] == parent["report_id"])
        assert row["confirmation_count"] == 3
        assert row["credibility"]["level"] in ("high", "very_high")

    def test_duplicates_hidden_from_staff_list(self, client, staff, spot):
        """غرفة العمليات ترى حادثًا واحدًا لا عدة بطاقات لنفس الموقع."""
        base = {"type": "road_block", "description": "إغلاق طريق", **spot}
        parent = client.post("/api/reports", headers=self._guest(client), data=base).json()
        children = [client.post("/api/reports", headers=self._guest(client),
                                data={**base, "latitude": spot["latitude"] + i * 0.0004}).json()
                    for i in range(3)]
        rows = client.get("/api/reports/staff", headers=staff["headers"]).json()
        codes = {r["report_id"] for r in rows}
        assert parent["report_id"] in codes
        for child in children:
            assert child["report_id"] not in codes

    def test_duplicates_skip_agent_pipeline(self, client, spot):
        """التأكيد لا يستدعي الوكلاء — الحادث مُصنَّف أصلًا."""
        base = {"type": "fire", "description": "حريق", **spot}
        client.post("/api/reports", headers=self._guest(client), data=base)
        child = client.post("/api/reports", headers=self._guest(client),
                            data={**base, "latitude": spot["latitude"] + 0.0002}).json()
        with get_conn() as conn:
            row = conn.execute("SELECT pipeline_status FROM reports WHERE public_code = %s",
                               (child["report_id"],)).fetchone()
        assert row["pipeline_status"] == "skipped_duplicate"

    @staticmethod
    def _guest(client):
        return {"x-user-token": client.post("/api/auth/guest").json()["token"]}


# ============== تحليل البيانات الوصفية للصور ==============

class TestExifAnalysis:
    def test_recent_matching_photo_scores_high(self):
        from image_processor import analyse_exif
        from datetime import datetime
        now = datetime(2026, 8, 26, 17, 0, 0)
        result = analyse_exif(
            {"captured_at": "2026:08:26 16:52:00", "gps_latitude": 23.5933,
             "gps_longitude": 58.2844, "device": "Apple iPhone 15"},
            23.5933, 58.2844, now)
        assert result["consistency_score"] == 100
        assert all(f["level"] == "ok" for f in result["flags"])

    def test_old_photo_flagged(self):
        from image_processor import analyse_exif
        from datetime import datetime
        result = analyse_exif({"captured_at": "2026:08:22 10:00:00", "device": "X"},
                              23.59, 58.28, datetime(2026, 8, 26, 17, 0, 0))
        assert result["consistency_score"] < 70
        assert any(f["level"] == "warning" for f in result["flags"])

    def test_distant_photo_flagged(self):
        from image_processor import analyse_exif
        from datetime import datetime
        result = analyse_exif(
            {"captured_at": "2026:08:26 16:50:00", "gps_latitude": 24.3,
             "gps_longitude": 56.7, "device": "X"},
            23.5933, 58.2844, datetime(2026, 8, 26, 17, 0, 0))
        assert any("كم عن موقع البلاغ" in f["message"] for f in result["flags"])

    def test_edited_photo_flagged(self):
        from image_processor import analyse_exif
        from datetime import datetime
        result = analyse_exif({"captured_at": "2026:08:26 16:55:00", "software": "Adobe Photoshop 2024"},
                              23.59, 58.28, datetime(2026, 8, 26, 17, 0, 0))
        assert any("تحرير" in f["message"] for f in result["flags"])

    def test_missing_exif_is_not_an_accusation(self):
        """غياب البيانات شائع (واتساب يحذفها) — لا يجوز أن يُعامل كتزوير."""
        from image_processor import analyse_exif
        result = analyse_exif({}, 23.59, 58.28, None)
        assert result["has_exif"] is False
        assert all(f["level"] != "warning" for f in result["flags"])
        assert result["consistency_score"] >= 80


# ============== المسار الطبيعي الكامل ==============

class TestHappyPath:
    def test_full_journey(self, client, guest, staff):
        """مواطن يبلّغ بصورة → n8n يصنّف → الموظف يشوف ويحدّث."""
        r = client.post("/api/reports", headers=guest["headers"],
                        data={"type": "حريق", "description": "حريق بالخوض",
                              "latitude": 23.5933, "longitude": 58.2844},
                        files={"media": ("حادث.png", io.BytesIO(png_bytes()), "image/png")})
        assert r.status_code == 200
        code = r.json()["report_id"]

        assert client.get("/api/reports", headers=guest["headers"]).status_code == 200

        client.patch(f"/api/reports/{code}/classification",
                     headers={"x-webhook-secret": WEBHOOK_SECRET},
                     json={"confirmed_incident_type": "حريق", "department": "Civil Defense",
                           "priority": "high", "risk_score": 80, "status": "verified"})

        rows = client.get("/api/reports/staff", headers=staff["headers"]).json()
        row = next(r for r in rows if r["report_id"] == code)
        assert row["department"] == "Civil Defense"
        # المقياس 0-100 مباشرة: 80 تبقى 80 ولا تُعاد قياسها
        assert row["risk_score"] == 80

        upd = client.patch(f"/api/reports/{code}/status",
                           headers=staff["headers"], json={"status": "dispatched"})
        assert upd.json()["status"] == "dispatched"

        citizen = client.get(f"/api/reports/{code}", headers=guest["headers"]).json()
        assert citizen["status"] == "dispatched"
