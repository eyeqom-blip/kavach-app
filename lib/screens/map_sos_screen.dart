import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapSosScreen extends StatefulWidget {
  final String baseUrl;
  final bool openSosTab;
  const MapSosScreen({super.key, required this.baseUrl, this.openSosTab = false});

  @override
  State<MapSosScreen> createState() => _MapSosScreenState();
}

class _MapSosScreenState extends State<MapSosScreen> {
  static const _audioChannel = MethodChannel('com.familykavach/sos_audio');
  final MapController _mapCtrl = MapController();
  final AudioPlayer _sirenPlayer = AudioPlayer();
  final Battery _battery = Battery();

  List<dynamic> _members = [];
  List<dynamic> _alerts = [];
  double _myLat = 20.5937;
  double _myLng = 78.9629;
  int _batteryLevel = 100;
  bool _sirenActive = false;
  bool _recording = false;
  bool _syncing = false;
  double? _safeLat;
  double? _safeLng;
  final double _safeRadius = 500;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadGeofence();
    _refreshAll();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refreshAll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sirenPlayer.dispose();
    if (_recording) {
      _audioChannel.invokeMethod('stopRecording').catchError((_) => null);
    }
    super.dispose();
  }

  Future<void> _loadGeofence() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _safeLat = prefs.getDouble('safe_lat');
      _safeLng = prefs.getDouble('safe_lng');
    });
  }

  Future<void> _setSafeZoneHere() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('safe_lat', _myLat);
    await prefs.setDouble('safe_lng', _myLng);
    setState(() {
      _safeLat = _myLat;
      _safeLng = _myLng;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🛡️ Home/Safe Zone (500m radius) yahan set ho gaya!')),
      );
    }
  }

  Future<void> _refreshAll() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      final familyId = prefs.getInt('family_id');

      _batteryLevel = await _battery.batteryLevel;
      final bState = await _battery.batteryState;
      final isCharging = bState == BatteryState.charging || bState == BatteryState.full;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _myLat = pos.latitude;
      _myLng = pos.longitude;

      final queue = prefs.getStringList('offline_locs') ?? [];
      final currentPayload = jsonEncode({
        'userId': userId,
        'latitude': _myLat,
        'longitude': _myLng,
        'batteryLevel': _batteryLevel,
        'isCharging': isCharging,
      });

      try {
        for (final q in queue) {
          await http.post(
            Uri.parse('${widget.baseUrl}/api/location/update'),
            headers: {'Content-Type': 'application/json'},
            body: q,
          );
        }
        await prefs.remove('offline_locs');

        await http.post(
          Uri.parse('${widget.baseUrl}/api/location/update'),
          headers: {'Content-Type': 'application/json'},
          body: currentPayload,
        );

        if (_batteryLevel <= 10 && !isCharging && !(prefs.getBool('low_bat_sent') ?? false)) {
          await http.post(
            Uri.parse('${widget.baseUrl}/api/sos/trigger'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'familyId': familyId,
              'userId': userId,
              'latitude': _myLat,
              'longitude': _myLng,
              'alertType': 'LOW_BATTERY_$_batteryLevel%',
            }),
          );
          await prefs.setBool('low_bat_sent', true);
        } else if (_batteryLevel > 15) {
          await prefs.setBool('low_bat_sent', false);
        }

        if (_safeLat != null && _safeLng != null) {
          final dist = Geolocator.distanceBetween(_safeLat!, _safeLng!, _myLat, _myLng);
          if (dist > _safeRadius && !(prefs.getBool('geo_alert_sent') ?? false)) {
            await http.post(
              Uri.parse('${widget.baseUrl}/api/sos/trigger'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'familyId': familyId,
                'userId': userId,
                'latitude': _myLat,
                'longitude': _myLng,
                'alertType': 'GEOFENCE_OUTSIDE (${dist.toInt()}m)',
              }),
            );
            await prefs.setBool('geo_alert_sent', true);
          } else if (dist <= _safeRadius) {
            await prefs.setBool('geo_alert_sent', false);
          }
        }

        final memRes = await http.get(Uri.parse('${widget.baseUrl}/api/family/$familyId/locations'));
        if (memRes.statusCode == 200) {
          final d = jsonDecode(memRes.body);
          if (d['success'] == true) _members = d['members'];
        }
        final alertRes = await http.get(Uri.parse('${widget.baseUrl}/api/family/$familyId/alerts'));
        if (alertRes.statusCode == 200) {
          final d = jsonDecode(alertRes.body);
          if (d['success'] == true) _alerts = d['alerts'];
        }
      } catch (_) {
        queue.add(currentPayload);
        await prefs.setStringList('offline_locs', queue);
      }

      if (mounted) {
        setState(() {});
        _mapCtrl.move(LatLng(_myLat, _myLng), 14.5);
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Uint8List _buildSirenWav() {
    const sampleRate = 16000;
    const durationSec = 1;
    final numSamples = sampleRate * durationSec;
    final byteData = ByteData(44 + numSamples * 2);

    void writeStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        byteData.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeStr(0, 'RIFF');
    byteData.setUint32(4, 36 + numSamples * 2, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, 1, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    writeStr(36, 'data');
    byteData.setUint32(40, numSamples * 2, Endian.little);

    for (int i = 0; i < numSamples; i++) {
      final freq = (i < numSamples ~/ 2) ? 920.0 : 680.0;
      final sample = (sin(2 * pi * freq * i / sampleRate) * 32000).toInt();
      byteData.setInt16(44 + i * 2, sample, Endian.little);
    }
    return byteData.buffer.asUint8List();
  }

  Future<void> _toggleSosPanic() async {
    if (_sirenActive) {
      await _sirenPlayer.stop();
      if (_recording) {
        try {
          await _audioChannel.invokeMethod('stopRecording');
        } catch (_) {}
        _recording = false;
      }
      setState(() => _sirenActive = false);
      return;
    }

    setState(() => _sirenActive = true);

    await _sirenPlayer.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        usageType: AndroidUsageType.alarm,
        contentType: AndroidContentType.sonification,
        audioFocus: AndroidAudioFocus.gainTransient,
      ),
    ));
    await _sirenPlayer.setReleaseMode(ReleaseMode.loop);
    await _sirenPlayer.play(BytesSource(_buildSirenWav()));

    try {
      if (await Permission.microphone.request().isGranted) {
        await _audioChannel.invokeMethod('startRecording');
        setState(() => _recording = true);
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await http.post(
        Uri.parse('${widget.baseUrl}/api/sos/trigger'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'familyId': prefs.getInt('family_id'),
          'userId': prefs.getInt('user_id'),
          'latitude': _myLat,
          'longitude': _myLng,
          'alertType': 'SOS_PANIC',
        }),
      );
      _refreshAll();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live GPS & SOS Shield'),
        actions: [
          IconButton(onPressed: _setSafeZoneHere, icon: const Icon(Icons.radar_rounded), tooltip: 'Set Safe Zone Here'),
          IconButton(onPressed: _refreshAll, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 290,
            child: FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(initialCenter: LatLng(_myLat, _myLng), initialZoom: 14),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.familykavach.family_kavach',
                ),
                if (_safeLat != null && _safeLng != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LatLng(_safeLat!, _safeLng!),
                        radius: _safeRadius,
                        useRadiusInMeter: true,
                        color: Colors.green.withOpacity(0.18),
                        borderColor: Colors.greenAccent,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: _members.where((m) => m['latitude'] != null).map((m) {
                    final lat = (m['latitude'] as num).toDouble();
                    final lng = (m['longitude'] as num).toDouble();
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 90,
                      height: 60,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              '${m['name']} 🔋${m['battery_level'] ?? '?'}%',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.location_pin, color: cs.primary, size: 32),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _sirenActive ? Colors.orange : Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _toggleSosPanic,
                icon: Icon(_sirenActive ? Icons.stop_circle_rounded : Icons.sos_rounded, size: 30),
                label: Text(
                  _sirenActive
                      ? 'STOP SIREN & REC (${_recording ? "Recording..." : "Siren ON"})'
                      : 'PANIC SOS (Silent-Bypass Ring + Audio)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                const Text('Family Members & Battery Status', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ..._members.map((m) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text((m['name'] ?? 'U')[0].toUpperCase())),
                        title: Text('${m['name']} (${m['role']})'),
                        subtitle: Text(m['latitude'] != null
                            ? 'GPS: ${m['latitude'].toStringAsFixed(4)}, ${m['longitude'].toStringAsFixed(4)}'
                            : 'GPS waiting...'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(m['is_charging'] == true ? Icons.battery_charging_full : Icons.battery_std,
                                color: (m['battery_level'] ?? 100) <= 15 ? Colors.redAccent : Colors.greenAccent),
                            Text('${m['battery_level'] ?? '--'}%', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    )),
                if (_alerts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Recent SOS / Geofence / Low Battery Alerts', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                  ..._alerts.take(5).map((a) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                        title: Text('${a['triggered_by_name']}: ${a['alert_type']}'),
                        subtitle: Text('Location: ${a['latitude']}, ${a['longitude']}'),
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
