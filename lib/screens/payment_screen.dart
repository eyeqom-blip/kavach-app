import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentScreen extends StatefulWidget {
  final String baseUrl;
  final Map<String, dynamic> config;
  final int discountCredits;
  const PaymentScreen({super.key, required this.baseUrl, required this.config, this.discountCredits = 0});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  int _members = 5;
  String _planType = '6_MONTHS';
  final _utrCtrl = TextEditingController();
  String? _screenshotBase64;
  String? _screenshotName;
  bool _submitting = false;

  int get _extra => _members > 5 ? _members - 5 : 0;
  int get _price1M => 20 + (_extra * 5);
  int get _price6M => 80 + (_extra * 20);
  int get _baseAmount => _planType == '6_MONTHS' ? _price6M : _price1M;
  int get _appliedDiscount => widget.discountCredits > _baseAmount ? _baseAmount : widget.discountCredits;
  int get _finalPayable => _baseAmount - _appliedDiscount;

  Future<void> _openUpiApp() async {
    final upiId = widget.config['upi_id'] ?? 'aapka_upi@okaxis';
    final upiName = Uri.encodeComponent(widget.config['upi_name'] ?? 'Family Kavach');
    final note = Uri.encodeComponent('Kavach $_planType $_members Members');
    final uri = Uri.parse('upi://pay?pa=$upiId&pn=$upiName&am=$_finalPayable&cu=INR&tn=$note');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('UPI App nahi khula. Direct is ID par ₹$_finalPayable bhejein: $upiId')),
        );
      }
    }
  }

  Future<void> _pickScreenshot() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 55);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _screenshotBase64 = base64Encode(bytes);
        _screenshotName = file.name;
      });
    }
  }

  Future<void> _submitPayment() async {
    if (_finalPayable > 0 && _utrCtrl.text.trim().length < 6 && _screenshotBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please UTR/Transaction ID daalein ya Screenshot upload karein')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/api/payment/submit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'familyId': prefs.getInt('family_id'),
          'userId': prefs.getInt('user_id'),
          'planType': _planType,
          'requestedMembers': _members,
          'utrNumber': _finalPayable == 0
              ? 'FREE_BY_REFERRAL_CREDITS'
              : (_utrCtrl.text.trim().isEmpty ? 'SCREENSHOT_UPLOADED' : _utrCtrl.text.trim()),
          'screenshotBase64': _screenshotBase64,
        }),
      );
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Request Sent! ✅'),
            content: Text('₹$_finalPayable (Discount: ₹$_appliedDiscount) ki request Admin ko bhej di gayi hai!'),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error!')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final upiId = widget.config['upi_id'] ?? 'aapka_upi@okaxis';

    return Scaffold(
      appBar: AppBar(title: const Text('Kavach Suraksha Plan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Family Members Kitne Hain?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Default 5 (User + 4) = ₹20/mo | Extra person +₹5/mo', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(onPressed: _members > 5 ? () => setState(() => _members--) : null, icon: const Icon(Icons.remove)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text('$_members Persons', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.primary)),
                      ),
                      IconButton.filledTonal(onPressed: _members < 20 ? () => setState(() => _members++) : null, icon: const Icon(Icons.add)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _planTile('1_MONTH', '1 Month Plan', '₹$_price1M', '₹20 base + ₹5/extra')),
              const SizedBox(width: 10),
              Expanded(child: _planTile('6_MONTHS', '6 Months Saver', '₹$_price6M', 'Best Value!')),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.green.withOpacity(0.15),
              border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
            ),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Plan Price:'), Text('₹$_baseAmount')]),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Referral Discount (${widget.discountCredits} Credits):', style: const TextStyle(color: Colors.greenAccent)),
                    Text('- ₹$_appliedDiscount', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Final Payable:', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('₹$_finalPayable', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.primary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_finalPayable > 0) ...[
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Step 1: Pay ₹$_finalPayable via UPI (0% Fee)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    SelectableText('UPI ID: $upiId', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.black),
                        onPressed: _openUpiApp,
                        icon: const Icon(Icons.account_balance_wallet_rounded),
                        label: Text('Pay ₹$_finalPayable via GPay / PhonePe', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Step 2: Payment Verify Karein', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    TextField(controller: _utrCtrl, decoration: const InputDecoration(labelText: '12-Digit UTR / Transaction ID', border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _pickScreenshot,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(_screenshotName ?? 'Upload Payment Screenshot (Optional)'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
              onPressed: _submitting ? null : _submitPayment,
              child: _submitting
                  ? const CircularProgressIndicator(color: Colors.black)
                  : Text(
                      _finalPayable == 0 ? 'Activate FREE with Referral Credits 🎉' : 'Submit Payment For Approval →',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planTile(String code, String title, String price, String sub) {
    final selected = _planType == code;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _planType = code),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected ? cs.primary.withOpacity(0.18) : Theme.of(context).colorScheme.surface,
          border: Border.all(color: selected ? cs.primary : Colors.grey.shade700, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(price, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.primary)),
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
