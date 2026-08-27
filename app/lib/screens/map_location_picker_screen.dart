import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_colors.dart';
import '../core/app_text_styles.dart';

/// الموقع الذي يختاره المستخدم من الخريطة، يُعاد إلى شاشة إرسال البلاغ.
class PickedLocation {
  final double latitude;
  final double longitude;
  final String address;

  const PickedLocation({required this.latitude, required this.longitude, required this.address});
}

const _fallbackCenter = ll.LatLng(23.5859, 58.4059); // مسقط
const _nominatimUserAgent = 'AmanAI-CitizenApp/1.0';

class MapLocationPickerScreen extends StatefulWidget {
  const MapLocationPickerScreen({super.key});

  @override
  State<MapLocationPickerScreen> createState() => _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  ll.LatLng _center = _fallbackCenter;
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  bool _confirming = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _goToCurrentLocation(silent: true);
  }

  Future<void> _goToCurrentLocation({bool silent = false}) async {
    if (!silent) setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final target = ll.LatLng(position.latitude, position.longitude);
      setState(() => _center = target);
      _mapController.move(target, 16);
    } catch (_) {
      // تجاهل أخطاء الموقع (صلاحية مرفوضة/خدمة معطّلة) والبقاء على المركز الافتراضي
    } finally {
      if (!silent && mounted) setState(() => _locating = false);
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '6',
        'accept-language': 'ar',
      });
      final res = await http.get(uri, headers: {'User-Agent': _nominatimUserAgent});
      if (res.statusCode == 200) {
        final list = (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map<String, dynamic>>();
        setState(() => _searchResults = list);
      }
    } catch (_) {
      // تجاهل فشل البحث (لا اتصال إنترنت مثلاً) — يبقى للمستخدم خيار السحب اليدوي
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectSearchResult(Map<String, dynamic> result) {
    final lat = double.tryParse(result['lat']?.toString() ?? '');
    final lon = double.tryParse(result['lon']?.toString() ?? '');
    if (lat == null || lon == null) return;
    final target = ll.LatLng(lat, lon);
    setState(() {
      _center = target;
      _searchResults = [];
      _searchController.text = result['display_name']?.toString() ?? '';
    });
    _mapController.move(target, 16);
    FocusScope.of(context).unfocus();
  }

  Future<String> _reverseGeocode(ll.LatLng point) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'format': 'jsonv2',
        'accept-language': 'ar',
      });
      final res = await http.get(uri, headers: {'User-Agent': _nominatimUserAgent});
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final name = body['display_name']?.toString();
        if (name != null && name.isNotEmpty) return name;
      }
    } catch (_) {
      // تجاهل فشل الجلب العكسي للعنوان — استخدم الإحداثيات كنص بديل
    }
    return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
  }

  Future<void> _confirmLocation() async {
    setState(() => _confirming = true);
    try {
      final address = _searchController.text.trim().isNotEmpty
          ? _searchController.text.trim()
          : await _reverseGeocode(_center);
      if (!mounted) return;
      Navigator.of(context).pop(
        PickedLocation(latitude: _center.latitude, longitude: _center.longitude, address: address),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.black.withOpacity(0.25)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: _center,
                              initialZoom: 15,
                              onPositionChanged: (position, hasGesture) {
                                if (hasGesture) _center = position.center;
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.aman_ai.citizen_app',
                              ),
                              const RichAttributionWidget(
                                attributions: [
                                  TextSourceAttribution('© OpenStreetMap contributors'),
                                ],
                              ),
                            ],
                          ),
                          // مربع البحث العلوي
                          Positioned(
                            top: 14,
                            left: 14,
                            right: 14,
                            child: Column(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4)),
                                    ],
                                  ),
                                  child: TextField(
                                    controller: _searchController,
                                    textAlign: TextAlign.right,
                                    style: AppTextStyles.body,
                                    onChanged: _search,
                                    decoration: InputDecoration(
                                      hintText: 'ابحث عن موقع...',
                                      hintStyle: AppTextStyles.subtitle,
                                      prefixIcon: _searching
                                          ? const Padding(
                                              padding: EdgeInsets.all(14),
                                              child: SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              ),
                                            )
                                          : const Icon(Icons.search_rounded, color: AppColors.textLight),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                  ),
                                ),
                                if (_searchResults.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(top: 6),
                                    constraints: const BoxConstraints(maxHeight: 220),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4)),
                                      ],
                                    ),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      itemCount: _searchResults.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (_, i) {
                                        final r = _searchResults[i];
                                        return ListTile(
                                          dense: true,
                                          leading: const Icon(Icons.place_outlined, color: AppColors.primaryBlue, size: 20),
                                          title: Text(
                                            r['display_name']?.toString() ?? '',
                                            textAlign: TextAlign.right,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTextStyles.body.copyWith(fontSize: 13),
                                          ),
                                          onTap: () => _selectSearchResult(r),
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // الدبوس الثابت في المنتصف
                          const Padding(
                            padding: EdgeInsets.only(bottom: 34),
                            child: Icon(Icons.location_on_rounded, color: AppColors.emergencyRed, size: 46),
                          ),
                          // زر الموقع الحالي
                          Positioned(
                            bottom: 16,
                            left: 16,
                            child: GestureDetector(
                              onTap: _locating ? null : () => _goToCurrentLocation(),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 3)),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: _locating
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.my_location_rounded, color: AppColors.primaryBlue, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _confirming ? null : _confirmLocation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emergencyRed,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _confirming
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                            )
                          : Text('تأكيد الموقع', style: AppTextStyles.button),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
