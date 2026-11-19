import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/payment_screen.dart';
import 'screens/map_sos_screen.dart';
import 'screens/chat_tasks_screen.dart';
import 'screens/kids_antitheft_screen.dart';

const String BASE_URL = 'https://kavach-backend-8hjz.onrender.com';
const String APP_VERSION = '1.0.2';

void main() {
  runApp(const FamilyKavachApp());
}

class FamilyKavachApp extends StatefulWidget {
  const FamilyKavachApp({super.key});

  @override
  State<FamilyKavachApp> createState() => _FamilyKavachAppState();
}

class _FamilyKavachAppState extends State<FamilyKavachApp> {
  bool _isDark = true;
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
      colorScheme: const ColorScheme.dark(primary: Color(0xFF00E5FF), secondary: Color(0xFF7C4DFF), surface: Color(0xFF131A2E)),
    );
    final lightTheme = ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF4F7FC),
      colorScheme: const ColorScheme.light(primary: Color(0xFF0066FF), secondary: Color(0xFF6200EA), surface: Colors.white),
    );

    return MaterialApp(
      title: 'Family Kavach',
      debugShowCheckedModeBanner: false,
      theme: _isDark ? darkTheme : lightTheme,
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : !_wizardDone
              ? SetupWizardScreen(onComplete: () => setState(() => _wizardDone = true))
              : _userId == null
                  ? LoginScreen(onLoggedIn: () async {
                      final prefs = await SharedPreferences.getInstance();
                      setState(() => _userId = prefs.getInt('user_id'));
                    })
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

class SetupWizardScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SetupWizardScreen({super.key, required this.onComplete});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  int _step = 0;
  final List<Map<String, dynamic>> _steps = [
    {'title': 'Kavach Suraksha Me Swagat Hai!', 'desc': 'Ghar ke sabhi logo ko 24x7 safe rakhne ke liye bas 3 aasan permissions on karein.', 'icon': Icons.shield_rounded, 'perm': null},
    {'title': 'Step 1: Live GPS Location', 'desc': '1-click live location aur phone band hone se pehle last location bhejne ke liye.', 'icon': Icons.location_on_rounded, 'perm': Permission.location},
    {'title': 'Step 2: SOS Alerts & Notifications', 'desc': 'SOS alarm, low battery warning, aur naye updates dikhane ke liye.', 'icon': Icons.notifications_active_rounded, 'perm': Permission.notification},
    {'title': 'Step 3: Mic & Camera (SOS / Anti-Theft)', 'desc': 'Panic button par audio recording aur intruder photo capture ke liye.', 'icon': Icons.camera_alt_rounded, 'perm': Permission.camera},
  ];

  Future<void> _handleNext() async {
    final perm = _steps[_step]['perm'] as Permission?;
    if (perm != null) {
      await perm.request();
      if (perm == Permission.camera) await Permission.microphone.request();
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
              LinearProgressIndicator(value: (_step + 1) / _steps.length, borderRadius: BorderRadius.circular(10), minHeight: 8),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [cs.primary, cs.secondary])),
                child: Icon(current['icon'], size: 72, color: Colors.black),
              ),
              const SizedBox(height: 32),
              Text(current['title'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(current['desc'], textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey.shade400, height: 1.5)),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _handleNext,
                  child: Text(_step == 0 ? 'Setup Shuru Karein →' : _step == _steps.length - 1 ? 'Allow & Finish ✓' : 'Allow Permission →',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
  final _refCtrl = TextEditingController();
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
          'referralCode': _joinMode ? null : _refCtrl.text.trim(),
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', data['user']['id']);
        await prefs.setString('user_name', data['user']['name']);
        await prefs.setInt('family_id', data['family']['id']);
        await prefs.setString('invite_code', data['family']['invite_code']);
        await prefs.setString('referral_code', data['user']['referral_code'] ?? '');
        widget.onLoggedIn();
      } else {
        setState(() => _error = data['message'] ?? 'Login failed');
      }
    } catch (_) {
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
              Text('5 Members = ₹20/mo • ₹80/6mo | Extra ₹5/person', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
              const SizedBox(height: 22),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Naya Parivar Banayein')),
                  ButtonSegment(value: true, label: Text('Invite Code Se Judein')),
                ],
                selected: {_joinMode},
                onSelectionChanged: (s) => setState(() => _joinMode = s.first),
              ),
              const SizedBox(height: 18),
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Aapka Naam', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile Number', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (Safety Link ke liye)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              if (_joinMode)
                TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: 'Family Invite Code (e.g. KVC8X2A)', border: OutlineInputBorder()))
              else
                TextField(controller: _refCtrl, decoration: const InputDecoration(labelText: 'Friend Referral Code (Optional: REFxxxx)', border: OutlineInputBorder())),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
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
  String _referralCode = '';
  int _discountCredits = 0;
  int _maxMembers = 5;
  int _currentMembers = 1;
  String _planStatus = 'FREE_TRIAL';
  List<dynamic> _referredFriends = [];
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
      _referralCode = prefs.getString('referral_code') ?? 'REF----';
    });
    _fetchConfigAndStatus();
  }

  bool _isNewerVersion(String latest, String current) {
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  Future<void> _fetchConfigAndStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final familyId = prefs.getInt('family_id');
      final userId = prefs.getInt('user_id');

      final cfgRes = await http.get(Uri.parse('$BASE_URL/api/config'));
      if (cfgRes.statusCode == 200) {
        final data = jsonDecode(cfgRes.body);
        if (data['success'] == true && mounted) {
          setState(() => _config = Map<String, dynamic>.from(data['config']));
          final latestVer = (_config['latest_version'] ?? APP_VERSION).toString();
          final updateUrl = (_config['update_url'] ?? '').toString();
          final msg = (_config['announcement'] ?? '').toString();

          if (_isNewerVersion(latestVer, APP_VERSION) && updateUrl.startsWith('http')) {
            _showUpdateDialog(latestVer, updateUrl);
          } else if (msg.isNotEmpty) {
            _showAppOpenDialog(msg);
          }
        }
      }

      if (familyId != null) {
        final stRes = await http.get(Uri.parse('$BASE_URL/api/family/$familyId/status'));
        if (stRes.statusCode == 200) {
          final s = jsonDecode(stRes.body);
          if (s['success'] == true && mounted) {
            setState(() {
              _maxMembers = s['max_members'] ?? 5;
              _currentMembers = s['current_members'] ?? 1;
              _planStatus = s['subscription'] != null ? (s['subscription']['status'] ?? 'TRIAL') : 'TRIAL';
            });
          }
        }
      }

      if (userId != null) {
        final refRes = await http.get(Uri.parse('$BASE_URL/api/referrals/$userId'));
        if (refRes.statusCode == 200) {
          final r = jsonDecode(refRes.body);
          if (r['success'] == true && mounted) {
            setState(() {
              _referralCode = r['referral_code'] ?? _referralCode;
              _discountCredits = r['discount_credits'] ?? 0;
              _referredFriends = r['referred_friends'] ?? [];
            });
          }
        }
      }
    } catch (_) {}
  }

  void _showUpdateDialog(String ver, String apkUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.system_update_rounded, color: Colors.cyanAccent), SizedBox(width: 8), Text('Naya Update Taiyar!')]),
        content: Text('Family Kavach v$ver aa gaya hai. 1-Tap me download & update karein!'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Baad Me')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication);
            },
            child: const Text('Update Now 🚀'),
          ),
        ],
      ),
    );
  }

  void _showAppOpenDialog(String announcement) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.campaign_rounded, color: Colors.amber), SizedBox(width: 8), Text('Kavach Update')]),
        content: Text(announcement),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _shareAppToFriends();
            },
            child: const Text('Refer & Earn ₹1'),
          ),
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  void _shareWithFamily() {
    final link = _config['update_url'] ?? 'https://github.com/eyeqom-blip/kavach-releases/releases';
    Share.share(
      '🛡️ Ghar ke sabhi log *Family Kavach* install karein aur hamare family circle se judein!\n\n'
      '🔑 Mera Family Invite Code: *$_inviteCode*\n'
      '📲 App Download: $link',
    );
  }

  void _shareAppToFriends() {
    final link = _config['update_url'] ?? 'https://github.com/eyeqom-blip/kavach-releases/releases';
    Share.share(
      '🛡️ Apne parivar ki 24x7 safety ke liye *Family Kavach* try karein!\n'
      'Live GPS, Silent-Breaking SOS, aur Kids Guard sirf ₹20/mo (5 Members) me.\n\n'
      '🎁 Signup karte waqt mera Referral Code daalein: *$_referralCode*\n'
      '📲 Download Link:\n$link',
    );
  }

  void _showReferralsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('My Referrals (Credits: ₹$_discountCredits)'),
        content: SizedBox(
          width: double.maxFinite,
          child: _referredFriends.isEmpty
              ? const Text('Abhi tak kisi friend ne aapke referral code se join nahi kiya. Niche button se share karein — har paid friend & har renewal par ₹1 discount milega!')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _referredFriends.length,
                  itemBuilder: (_, i) {
                    final f = _referredFriends[i];
                    final paid = f['plan_status'] == 'ACTIVE';
                    return ListTile(
                      dense: true,
                      title: Text('${f['name']} (${f['masked_phone']})'),
                      subtitle: Text(paid ? '✅ Active Paid (+₹1 Earned)' : '⏳ Payment Pending', style: TextStyle(color: paid ? Colors.greenAccent : Colors.orangeAccent)),
                      trailing: paid
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.notifications_active_rounded, color: Colors.amber),
                              onPressed: () => Share.share(
                                'Namaste ${f['name']}! 🛡️ Apni family ki safety ke liye *Family Kavach* plan activate/renew kar lein (sirf ₹20/month)!',
                              ),
                            ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton(onPressed: () { Navigator.pop(ctx); _shareAppToFriends(); }, child: const Text('Share Code')),
        ],
      ),
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
            const SizedBox(width: 6),
            Text('v$APP_VERSION', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ],
        ),
        actions: [
          IconButton(icon: Icon(widget.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded), onPressed: widget.onToggleTheme),
          IconButton(icon: const Icon(Icons.logout_rounded), onPressed: widget.onLogout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchConfigAndStatus,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
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
                  Text('Family Invite Code: $_inviteCode ($_currentMembers/$_maxMembers Members)',
                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _shareWithFamily,
                    icon: const Icon(Icons.family_restroom_rounded),
                    label: const Text('Ghar Ke Members Ko Invite Karein'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(backgroundColor: Colors.amber.withOpacity(0.2), child: const Icon(Icons.workspace_premium_rounded, color: Colors.amber)),
                title: Text('Kavach Plan: $_planStatus ($_maxMembers Limit)', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('₹20/mo (5 Members) • Extra ₹5/mo • Pro ₹10/person\nReferral Credits: ₹$_discountCredits'),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PaymentScreen(baseUrl: BASE_URL, config: _config, discountCredits: _discountCredits)),
                    );
                    _fetchConfigAndStatus();
                  },
                  child: const Text('Pay / Add'),
                ),
              ),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: [
                _featureCard(Icons.my_location_rounded, 'Live GPS Track', '1-Click Map & Battery', Colors.cyan,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapSosScreen(baseUrl: BASE_URL)))),
                _featureCard(Icons.sos_rounded, 'Emergency SOS', 'Silent Ring + Audio', Colors.redAccent,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapSosScreen(baseUrl: BASE_URL, openSosTab: true)))),
                _featureCard(Icons.lock_rounded, 'E2EE Chat & Tasks', 'Encrypted + Chatbot', Colors.purpleAccent,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatTasksScreen(baseUrl: BASE_URL)))),
                _featureCard(Icons.child_care_rounded, 'Kids & Anti-Theft', 'Person-Wise Guard', Colors.amber,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KidsAntiTheftScreen(baseUrl: BASE_URL)))),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('🎁 Refer Friends & Save ₹1/Month', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Chip(label: Text('₹$_discountCredits Saved', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Code: $_referralCode • Har paid friend & har renewal par ₹1 kam!', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: OutlinedButton(onPressed: _showReferralsDialog, child: Text('Friends List (${_referredFriends.length})'))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(onPressed: _shareAppToFriends, icon: const Icon(Icons.share_rounded, size: 18), label: const Text('Refer App')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureCard(IconData icon, String title, String sub, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Card(
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
      ),
    );
  }
}
