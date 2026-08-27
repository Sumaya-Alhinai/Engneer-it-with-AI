# قواعد أساسية لمكتبات Flutter المستخدمة بالمشروع (flutter_tts, geolocator, speech_to_text..).
# أضف استثناءات إضافية هنا لو واجهت كراش بعد التصغير (minify) بنسخة release.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
