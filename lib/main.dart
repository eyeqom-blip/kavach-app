import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

// 👇 YAHAN APNA EXACT RENDER URL DAALEIN (Bina last slash '/' ke)
const String BASE_URL = 'https://YAHAN-APNA-RENDER-URL-LIKHEIN';

void main() {
  runApp(const FamilyKavachApp());
}

class FamilyKavachApp extends StatefulWidget {
  const FamilyKavachApp({super.key});

  @override
  State<FamilyKavachApp> createState() => _FamilyKavachAppState();
}

class _FamilyKavachAppState extends State<FamilyKavachApp> {
  bool _isDark = true; // Default Gen-Z Dark Mode
  bool _loading = true;
  bool _wizardDone = false;
  int? _userId;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDark = prefs.getBool('dark_mode') ?? true;
      _wizardDone = prefs.getBool('wizard_done') ?? false;
      _userId = prefs.getInt('user_id');
      _loading = false;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isDark = !_isDark);
    await prefs.setBool('dark_mode', _isDark);
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0A0E1A),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00E5FF),
        secondary: Color(0xFF7C4DFF),
        surface: Color(0xFF131A2E),
      ),
    );

    final lightTheme = ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF4F7FC),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF0066FF),
        secondary: Color(0xFF6200EA),
        surface: Colors.white,
      ),
    );

    return MaterialApp(
      title: 'Family Kavach',
      debugShowCheckedModeBanner: false,
      theme: _isDark ? darkTheme : lightTheme,
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : !_wizardDone
              ? SetupWizardScreen(
                  onComplete: () => setState(() => _wizardDone = true),
                )
              : _userId == null
                  ? LoginScreen(
                      onLoggedIn: () async {
                        final prefs = await SharedPreferences.getInstance();
                        setState(() => _userId = prefs.getInt('user_id'));
                      },
                    )
                  : DashboardScreen(
                      isDark: _isDark,
                      onToggleTheme: _toggleTheme,
                      onLogout: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('user_id');
                        setState(() => _userId = null);
                      },
                    ),
    );
  }
}

// ================= 1. STEP-BY-STEP SETUP & PERMISSION WIZARD =================
class SetupWizardScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SetupWizardScreen({super.key, required this.onComplete});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  int _step = 0;

  final List<Map<String, dynamic>> _steps = [
    {
      'title': 'Kavach Suraksha Me Swagat Hai!',
      'desc': 'Ghar ke sabhi logo ko 24x7 safe rakhne ke liye bas 3 aasan permissions on karein. Koi galti nahi hogi!',
      'icon': Icons.shield_rounded,
      'perm': null,
    },
    {
      'title': 'Step 1: Live GPS Location',
      'desc': 'Emergency me 1-click live location aur phone band hone se pehle last location bhejne ke liye zaroori hai.',
      'icon': Icons.location_on_rounded,
      'perm': Permission.location,
    },
    {
      'title': 'Step 2: SOS Alerts & Notifications',
      'desc': 'SOS bajne, low battery warning, aur naye updates turant screen par dikhane ke liye.',
      'icon': Icons.notifications_active_rounded,
      'perm': Permission.notification,
    },
    {
      'title': 'Step 3: Mic & Camera (Anti-Theft / SOS)',
      'desc': 'Panic button par audio recording aur chori ke waqt intruder photo capture ke liye.',
      'icon': Icons.camera_alt_rounded,
      'perm': Permission.camera,
    },
  ];

  Future<void> _handleNext() async {
    final perm = _steps[_step]['perm'] as Permission?;
    if (perm != null) {
      await perm.request();
      if (perm == Permission.camera) {
        await Permission.microphone.request();
      }
    }
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wizard_done', true);
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _steps[_step];
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: (_step + 1) / _steps.length,
                borderRadius: BorderRadius.circular(10),
                minHeight: 8,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
                ),
                child: Icon(current['icon'], size: 72, color: Colors.black),
              ),
              const SizedBox(height: 32),
              Text(
                current['title'],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                current['desc'],
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade400, height: 1.5),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _handleNext,
                  child: Text(
                    _step == 0
                        ? 'Setup Shuru Karein →'
                        : _step == _steps.length - 1
                            ? 'Allow & Finish ✓'
                            : 'Allow Permission →',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= 2. LOGIN / JOIN FAMILY (5 PERSON LIMIT) =================
class LoginScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _joinMode = false;
  bool _busy = false;
  String? _error;

  Future<String> _getDeviceId() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      return '${a.brand}_${a.model}_${a.id}';
    }
    return 'KAVACH_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().length < 10) {
      setState(() => _error = 'Sahi Naam aur 10-digit Mobile Number daalein');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final deviceId = await _getDeviceId();
      final res = await http.post(
        Uri.parse('$BASE_URL/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'deviceId': deviceId,
          'inviteCode': _joinMode ? _codeCtrl.text.trim() : null,
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', data['user']['id']);
        await prefs.setString('user_name', data['user']['name']);
        await prefs.setInt('family_id', data['family']['id']);
        await prefs.setString('invite_code', data['family']['invite_code']);
        widget.onLoggedIn();
      } else {
        setState(() => _error = data['message'] ?? 'Login failed');
      }
    } catch (e) {
      setState(() => _error = 'Server se connect nahi ho paya. Internet check karein.');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.shield_moon_rounded, color: cs.primary, size: 36),
                  const SizedBox(width: 10),
                  const Text('Family Kavach', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Text('1 Login = 5 Family Members | ₹20/mo • ₹80/6mo', style: TextStyle(color: Colors.grey.shade400)),
              const SizedBox(height: 28),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Naya Parivar Banayein')),
                  ButtonSegment(value: true, label: Text('Invite Code Se Judein')),
                ],
                selected: {_joinMode},
                onSelectionChanged: (s) => setState(() => _joinMode = s.first),
              ),
              const SizedBox(height: 20),
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Aapka Naam', border: OutlineInputBorder())),
              const SizedBox(height: 14),
              TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile Number', border: OutlineInputBorder())),
              const SizedBox(height: 14),
              TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (Safety Link ke liye)', border: OutlineInputBorder())),
              if (_joinMode) ...[
                const SizedBox(height: 14),
                TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: 'Family Invite Code (e.g. KVC8X2A)', border: OutlineInputBorder())),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(_joinMode ? 'Family Join Karein' : 'Kavach Shuru Karein', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= 3. GEN-Z DASHBOARD + APP OPEN DIALOG + WHATSAPP SHARE =================
class DashboardScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;
  const DashboardScreen({super.key, required this.isDark, required this.onToggleTheme, required this.onLogout});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _name = '';
  String _inviteCode = '';
  Map<String, dynamic> _config = {};

  @override
  void initState() {
    super.initState();
    _initDashboard();
  }

  Future<void> _initDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('user_name') ?? 'Member';
      _inviteCode = prefs.getString('invite_code') ?? 'KVC----';
    });
    _fetchConfigAndShowDialog();
  }

  Future<void> _fetchConfigAndShowDialog() async {
    try {
      final res = await http.get(Uri.parse('$BASE_URL/api/config'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          setState(() => _config = Map<String, dynamic>.from(data['config']));
          final msg = _config['announcement'];
          if (msg != null && msg.toString().isNotEmpty) {
            _showAppOpenDialog(msg.toString());
          }
        }
      }
    } catch (_) {}
  }

  void _showAppOpenDialog(String announcement) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.campaign_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Text('Kavach Update'),
          ],
        ),
        content: Text(announcement),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _shareApp();
            },
            child: const Text('Share With Family'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK, Got It'),
          ),
        ],
      ),
    );
  }

  void _shareApp() {
    final link = _config['update_url'] ?? 'https://familykavach.app';
    Share.share(
      '🛡️ Apne parivar ki safety ke liye *Family Kavach* download karein!\n\n'
      'Mera Family Code: *$_inviteCode*\nDownload Link: $link\n\n'
      '(Sirf ₹20/month me 5 family members safe!)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.shield_rounded, color: cs.primary),
            const SizedBox(width: 8),
            const Text('Family Kavach', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(widget.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: widget.onToggleTheme,
          ),
          IconButton(icon: const Icon(Icons.logout_rounded), onPressed: widget.onLogout),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(colors: [cs.primary.withOpacity(0.25), cs.secondary.withOpacity(0.25)]),
              border: Border.all(color: cs.primary.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Namaste, $_name 👋', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('Family Invite Code: $_inviteCode (Max 5 Members)', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _shareApp,
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('1-Click WhatsApp / SMS Share'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: [
              _featureCard(Icons.my_location_rounded, 'Live GPS Track', 'Phase 3 me judega', Colors.cyan),
              _featureCard(Icons.sos_rounded, 'Emergency SOS', 'Silent Ring + Audio', Colors.redAccent),
              _featureCard(Icons.lock_rounded, 'E2EE Family Chat', 'Private Encrypted', Colors.purpleAccent),
              _featureCard(Icons.child_care_rounded, 'Kids Control', 'Screen & App Guard', Colors.amber),
            ],
          ),
        ],
      ),
    );
  }

  Widget _featureCard(IconData icon, String title, String sub, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey.shade400), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
