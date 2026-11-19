import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ChatTasksScreen extends StatefulWidget {
  final String baseUrl;
  const ChatTasksScreen({super.key, required this.baseUrl});

  @override
  State<ChatTasksScreen> createState() => _ChatTasksScreenState();
}

class _ChatTasksScreenState extends State<ChatTasksScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _msgCtrl = TextEditingController();
  final _taskCtrl = TextEditingController();
  final _dueCtrl = TextEditingController();

  List<dynamic> _messages = [];
  List<dynamic> _tasks = [];
  String _botReply = '';
  int? _userId;
  int? _familyId;
  String _inviteCode = 'KVC';
  String _e2eePin = 'KAVACH2026';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _init();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _loadAll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt('user_id');
    _familyId = prefs.getInt('family_id');
    _inviteCode = prefs.getString('invite_code') ?? 'KVC';
    _e2eePin = prefs.getString('e2ee_pin') ?? _inviteCode;
    _loadAll();
  }

  enc.Key _deriveFamilyKey() {
    final bytes = sha256.convert(utf8.encode('KAVACH_${_inviteCode}_$_e2eePin')).bytes;
    return enc.Key(Uint8List.fromList(bytes));
  }

  String _decryptMsg(String cipherB64, String ivB64) {
    try {
      final encrypter = enc.Encrypter(enc.AES(_deriveFamilyKey()));
      return encrypter.decrypt64(cipherB64, iv: enc.IV.fromBase64(ivB64));
    } catch (_) {
      return '🔒 [Encrypted - Check Family E2EE PIN]';
    }
  }

  Future<void> _loadAll() async {
    if (_familyId == null) return;
    try {
      final cRes = await http.get(Uri.parse('${widget.baseUrl}/api/chat/$_familyId'));
      if (cRes.statusCode == 200) {
        final d = jsonDecode(cRes.body);
        if (d['success'] == true && mounted) setState(() => _messages = d['messages']);
      }
      final tRes = await http.get(Uri.parse('${widget.baseUrl}/api/tasks/$_familyId'));
      if (tRes.statusCode == 200) {
        final d = jsonDecode(tRes.body);
        if (d['success'] == true && mounted) setState(() => _tasks = d['tasks']);
      }
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _familyId == null) return;
    _msgCtrl.clear();

    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(_deriveFamilyKey()));
    final encrypted = encrypter.encrypt(text, iv: iv);

    try {
      await http.post(
        Uri.parse('${widget.baseUrl}/api/chat/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'familyId': _familyId,
          'senderId': _userId,
          'ciphertext': encrypted.base64,
          'iv': iv.base64,
        }),
      );
      _loadAll();
    } catch (_) {}
  }

  void _askKavachBot(String topic) {
    String reply;
    if (topic == 'EMERGENCY') {
      reply = '🚨 India Helplines:\nPolice: 112 | Women: 1091 | Child: 1098 | Ambulance: 108 | Cyber Fraud: 1930';
    } else if (topic == 'TASKS') {
      final pending = _tasks.where((t) => t['is_done'] != true).length;
      reply = '📋 Ghar ke $pending tasks abhi pending hain. Tasks tab me jakar check karein!';
    } else {
      reply = '🛡️ Kavach Tip: Bachho ke phone me Pro Guard ON rakhein aur Safe Zone geofence set karein!';
    }
    setState(() => _botReply = reply);
  }

  Future<void> _addTask() async {
    if (_taskCtrl.text.trim().isEmpty || _familyId == null) return;
    await http.post(
      Uri.parse('${widget.baseUrl}/api/tasks/add'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'familyId': _familyId,
        'title': _taskCtrl.text.trim(),
        'dueDate': _dueCtrl.text.trim(),
        'assignedTo': 'Family',
      }),
    );
    _taskCtrl.clear();
    _dueCtrl.clear();
    _loadAll();
  }

  Future<void> _toggleTask(int id, bool done) async {
    await http.post(
      Uri.parse('${widget.baseUrl}/api/tasks/toggle'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'taskId': id, 'isDone': done}),
    );
    _loadAll();
  }

  void _changePinDialog() {
    final pinCtrl = TextEditingController(text: _e2eePin);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Family E2EE Secret Key'),
        content: TextField(controller: pinCtrl, decoration: const InputDecoration(labelText: 'Shared Secret PIN (Sirf family ko batayein)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('e2ee_pin', pinCtrl.text.trim());
              setState(() => _e2eePin = pinCtrl.text.trim());
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Save Key'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('E2EE Chat & Family Tasks'),
        actions: [IconButton(onPressed: _changePinDialog, icon: const Icon(Icons.vpn_key_rounded), tooltip: 'E2EE Key')],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.lock_rounded), text: 'Encrypted Chat'),
            Tab(icon: Icon(Icons.checklist_rounded), text: 'Tasks & Calendar'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    ActionChip(label: const Text('🤖 Kavach Helplines'), onPressed: () => _askKavachBot('EMERGENCY')),
                    const SizedBox(width: 8),
                    ActionChip(label: const Text('🤖 Pending Tasks'), onPressed: () => _askKavachBot('TASKS')),
                    const SizedBox(width: 8),
                    ActionChip(label: const Text('🤖 Safety Tip'), onPressed: () => _askKavachBot('TIP')),
                  ],
                ),
              ),
              if (_botReply.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: cs.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Expanded(child: Text(_botReply, style: const TextStyle(fontSize: 12))),
                      IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => _botReply = '')),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    final isMe = m['sender_id'] == _userId;
                    final plain = _decryptMsg(m['ciphertext'] ?? '', m['iv'] ?? '');
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? cs.primary.withOpacity(0.25) : cs.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['sender_name'] ?? 'Member', style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(plain, style: const TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _msgCtrl,
                        decoration: const InputDecoration(hintText: '🔒 E2EE Message likhein...', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: _sendMessage, icon: const Icon(Icons.send_rounded)),
                  ],
                ),
              ),
            ],
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: TextField(controller: _taskCtrl, decoration: const InputDecoration(labelText: 'Ghar ka Task (e.g. Ration / Fees)', border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _dueCtrl, decoration: const InputDecoration(labelText: 'Date/Time', border: OutlineInputBorder()))),
                    IconButton.filled(onPressed: _addTask, icon: const Icon(Icons.add)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _tasks.length,
                  itemBuilder: (_, i) {
                    final t = _tasks[i];
                    final done = t['is_done'] == true;
                    return CheckboxListTile(
                      value: done,
                      title: Text(t['title'] ?? '', style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
                      subtitle: Text('Due: ${t['due_date'] ?? 'Anytime'}'),
                      onChanged: (v) => _toggleTask(t['id'], v ?? false),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
