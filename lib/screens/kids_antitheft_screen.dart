import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KidsAntiTheftScreen extends StatefulWidget {
  final String baseUrl;
  const KidsAntiTheftScreen({super.key, required this.baseUrl});

  @override
  State<KidsAntiTheftScreen> createState() => _KidsAntiTheftScreenState();
}

class _KidsAntiTheftScreenState extends State<KidsAntiTheftScreen> with SingleTickerProviderStateMixin {
  static const _guard = MethodChannel('com.familykavach/kavach_guard');
  late TabController _tabCtrl;

  List<dynamic> _members = [];
  int _maxProSlots = 0;
  List<dynamic> _reports = [];
  List<dynamic> _hiddenApps = [];
  List<dynamic> _socialApps = [];
  List<dynamic> _screenTime = [];
  List<dynamic> _callLogs = [];
  bool _powerGuardOn = false;
  bool _capturing = false;
  int _wrongPins = 0;
  int _screenLimitMin = 120;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadServerData();
    _loadLocalSecurity();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadServerData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final famId = prefs.getInt('family_id');
      if (famId == null) return;

      final stRes = await http.get(Uri.parse('${widget.baseUrl}/api/family/$famId/status'));
      if (stRes.statusCode == 200) {
        final d = jsonDecode(stRes.body);
        if (d['success'] == true && mounted) {
          setState(() {
            _maxProSlots = d['max_pro_guard'] ?? 0;
            _members = d['members'] ?? [];
          });
        }
      }
      final repRes = await http.get(Uri.parse('${widget.baseUrl}/api/reports/$famId'));
      if (repRes.statusCode == 200) {
        final d = jsonDecode(repRes.body);
        if (d['success'] == true && mounted) setState(() => _reports = d['reports'] ?? []);
      }
    } catch (_) {}
  }

  Future<void> _loadLocalSecurity() async {
    try {
      final tamper = await _guard.invokeMethod('getTamperStatus');
      if (tamper is Map && mounted) {
        setState(() {
          _powerGuardOn = tamper['powerGuardEnabled'] == true;
          _wrongPins = (tamper['wrongPinCount'] ?? 0) as int;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleMemberPro(int targetUserId, bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    final famId = prefs.getInt('family_id');
    final res = await http.post(
      Uri.parse('${widget.baseUrl}/api/family/$famId/pro-guard/toggle'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'targetUserId': targetUserId, 'enable': enable}),
    );
    final d = jsonDecode(res.body);
    if (d['success'] == true) {
      _loadServerData();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(d['message'] ?? 'Slot limit full!')));
    }
  }

  Future<void> _scanAppsAndUsage() async {
    try {
      final appsJson = await _guard.invokeMethod('getInstalledApps');
      final apps = jsonDecode(appsJson as String) as Map<String, dynamic>;
      final usageJson = await _guard.invokeMethod('getScreenTime');
      final usage = jsonDecode(usageJson as String) as List<dynamic>;

      setState(() {
        _hiddenApps = apps['hidden'] ?? [];
        _socialApps = apps['social'] ?? [];
        _screenTime = usage;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan error: $e')));
    }
  }

  Future<void> _scanCallSummary() async {
    if (!await Permission.phone.request().isGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call Log permission allow karein')));
      return;
    }
    try {
      final jsonStr = await _guard.invokeMethod('getCallSummary');
      setState(() => _callLogs = jsonDecode(jsonStr as String) as List<dynamic>);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call Log error: $e')));
    }
  }

  Future<void> _sendReportToFamily(String type, String details, {String? photoB64}) async {
    final prefs = await SharedPreferences.getInstance();
    await http.post(
      Uri.parse('${widget.baseUrl}/api/reports/submit'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'familyId': prefs.getInt('family_id'),
        'userId': prefs.getInt('user_id'),
        'reportType': type,
        'details': details,
        'photoBase64': photoB64,
      }),
    );
    _loadServerData();
  }

  Future<void> _captureIntruderFrontBack() async {
    if (_capturing) return;
    if (!await Permission.camera.request().isGranted) return;
    setState(() => _capturing = true);
    try {
      final cams = await availableCameras();
      String? frontB64;
      String? backB64;

      for (final dir in [CameraLensDirection.front, CameraLensDirection.back]) {
        final match = cams.where((c) => c.lensDirection == dir);
        if (match.isEmpty) continue;
        final ctrl = CameraController(match.first, ResolutionPreset.medium, enableAudio: false);
        try {
          await ctrl.initialize();
          final xfile = await ctrl.takePicture();
          final b64 = base64Encode(await xfile.readAsBytes());
          if (dir == CameraLensDirection.front) frontB64 = b64;
          if (dir == CameraLensDirection.back) backB64 = b64;
        } finally {
          await ctrl.dispose();
        }
      }

      if (frontB64 != null) {
        await _sendReportToFamily('INTRUDER_FRONT_CAM', 'Anti-Theft Front Camera Capture', photoB64: frontB64);
      }
      if (backB64 != null) {
        await _sendReportToFamily('INTRUDER_BACK_CAM', 'Anti-Theft Back Camera Capture', photoB64: backB64);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📸 Front & Back Intruder Photos Captured & Sent to Cloud/Telegram!')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera error: $e')));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usedSlots = _members.where((m) => m['pro_guard_enabled'] == true).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kids Control & Anti-Theft'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'Person Select'),
            Tab(text: 'Kids Monitor'),
            Tab(text: 'Anti-Theft'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // TAB 1: Person-Wise Pro Guard Control
          ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Card(
                color: Colors.amber.withOpacity(0.15),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    '🔒 Privacy Rule: Call Summary & Extra Monitoring sirf selected logo par chalegi.\n'
                    'Paid Slots: $usedSlots / $_maxProSlots Used (Pay / Add me ₹10/mo per person add karein)',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ..._members.map((m) => SwitchListTile(
                    title: Text('${m['name']} (${m['role']})'),
                    subtitle: Text(m['pro_guard_enabled'] == true ? '🛡️ Pro Kids Guard ON' : 'Basic GPS + SOS Only'),
                    value: m['pro_guard_enabled'] == true,
                    onChanged: (v) => _toggleMemberPro(m['id'], v),
                  )),
              if (_reports.isNotEmpty) ...[
                const Divider(),
                const Text('Family Kids / Security Alerts', style: TextStyle(fontWeight: FontWeight.bold)),
                ..._reports.take(10).map((r) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.security_rounded, color: Colors.amber),
                      title: Text('${r['user_name']}: ${r['report_type']}'),
                      subtitle: Text(r['details'] ?? ''),
                    )),
              ],
            ],
          ),

          // TAB 2: Kids Monitor (Hidden Apps, Screen Time, Call Summary, DNS Filter)
          ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Row(
                children: [
                  Expanded(child: ElevatedButton.icon(onPressed: _scanAppsAndUsage, icon: const Icon(Icons.search), label: const Text('Scan Apps & Time'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: _scanCallSummary, icon: const Icon(Icons.call), label: const Text('Call Summary'))),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _guard.invokeMethod('openUsageSettings'),
                child: const Text('Usage Access Permission On Karein (Screen Time ke liye)'),
              ),
              const SizedBox(height: 10),
              Text('Daily Screen Limit: $_screenLimitMin mins'),
              Slider(
                min: 30,
                max: 360,
                divisions: 11,
                value: _screenLimitMin.toDouble(),
                onChanged: (v) => setState(() => _screenLimitMin = v.toInt()),
              ),
              if (_hiddenApps.isNotEmpty) ...[
                Text('🚨 Hidden / No-Icon Apps (${_hiddenApps.length})', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ..._hiddenApps.take(10).map((a) => ListTile(dense: true, title: Text(a['name'] ?? ''), subtitle: Text(a['pkg'] ?? ''))),
              ],
              if (_socialApps.isNotEmpty) ...[
                Text('📱 Social / Games Installed (${_socialApps.length})', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                ..._socialApps.map((a) => ListTile(dense: true, title: Text(a['name'] ?? ''), subtitle: Text(a['pkg'] ?? ''))),
              ],
              if (_screenTime.isNotEmpty) ...[
                const Text('⏱️ Aaj Ka Screen Time', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                ..._screenTime.map((u) => ListTile(dense: true, title: Text(u['pkg'] ?? ''), trailing: Text('${u['minutes']} min'))),
              ],
              if (_callLogs.isNotEmpty) ...[
                const Text('📞 Recent Call Summary', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                ..._callLogs.map((c) => ListTile(dense: true, title: Text('${c['number']} (${c['type']})'), trailing: Text('${c['duration']}s'))),
              ],
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () => _sendReportToFamily('KIDS_SCAN', 'Hidden: ${_hiddenApps.length}, Social: ${_socialApps.length}, Calls: ${_callLogs.length}'),
                icon: const Icon(Icons.cloud_upload_rounded),
                label: const Text('Parent Dashboard Par Report Sync Karein'),
              ),
            ],
          ),

          // TAB 3: Anti-Theft Shield
          ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Card(
                child: SwitchListTile(
                  title: const Text('Bina Lock Shutdown Guard (Power-Menu Block)'),
                  subtitle: const Text('Phone lock hone par koi Power Off / Restart dabaye to menu turant band hoga'),
                  value: _powerGuardOn,
                  onChanged: (v) async {
                    await _guard.invokeMethod('setPowerGuard', {'enabled': v});
                    setState(() => _powerGuardOn = v);
                    if (v) await _guard.invokeMethod('openAccessibilitySettings');
                  },
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => _guard.invokeMethod('enableDeviceAdmin'),
                icon: const Icon(Icons.admin_panel_settings_rounded),
                label: const Text('Uninstall Lock & Wrong-PIN Guard On Karein'),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.warning_rounded, color: Colors.orange),
                title: Text('Wrong Lock PIN Attempts: $_wrongPins'),
                subtitle: const Text('Device Admin ON hone par galat PIN dalte hi count badhta hai'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                  onPressed: _capturing ? null : _captureIntruderFrontBack,
                  icon: const Icon(Icons.camera_front_rounded),
                  label: Text(_capturing ? 'Capturing Front + Back...' : '📸 Intruder Front + Back Capture Test'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
