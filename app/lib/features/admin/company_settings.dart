import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Admin — the buyer identity printed at the top of every PO document.
/// (Company name, address, GSTIN, state, phone, email.)
class CompanySettingsScreen extends ConsumerStatefulWidget {
  const CompanySettingsScreen({super.key});
  @override
  ConsumerState<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends ConsumerState<CompanySettingsScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _gstin = TextEditingController();
  final _state = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _seeded = false;
  bool _saving = false;
  String? _error;

  void _seed(CompanySettings c) {
    if (_seeded) return;
    _seeded = true;
    _name.text = c.name;
    _address.text = c.address ?? '';
    _gstin.text = c.gstin ?? '';
    _state.text = c.state ?? '';
    _phone.text = c.phone ?? '';
    _email.text = c.email ?? '';
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _gstin, _state, _phone, _email]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Company name is required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await ref.read(procurementRepoProvider).saveCompanySettings(
        name: _name.text.trim(),
        address: t(_address), gstin: t(_gstin), state: t(_state),
        phone: t(_phone), email: t(_email),
      );
      ref.invalidate(companySettingsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink, content: Text('Company details saved.')));
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(companySettingsProvider);
    return Scaffold(
      body: SafeArea(child: settings.when(
        loading: () => const Center(child: CircularProgressIndicator(color: BT.ink)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24),
          child: Text('Could not load company details.\n${friendlyError(e)}',
            textAlign: TextAlign.center, style: const TextStyle(color: BT.coral, fontSize: 13)))),
        data: (c) {
          _seed(c);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
            children: [
              Row(children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context),
                  child: Container(width: 42, height: 42, alignment: Alignment.center,
                    decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                    child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
                ),
              ]),
              const SizedBox(height: 14),
              Text('Company details', style: display(29, w: FontWeight.w500)),
              const SizedBox(height: 4),
              const Text('This is the buyer block printed on every purchase order.',
                style: TextStyle(color: BT.mut, fontSize: 12.5)),
              const SizedBox(height: 20),
              _field('COMPANY NAME', _name, hint: 'Azimuth Business on Wheels'),
              const SizedBox(height: 11),
              _field('ADDRESS', _address, hint: 'Street, city, PIN', lines: 2),
              const SizedBox(height: 11),
              _field('GSTIN', _gstin, hint: '27ABCDE1234F1Z5'),
              const SizedBox(height: 11),
              _field('STATE', _state, hint: 'Maharashtra'),
              const SizedBox(height: 6),
              const Padding(padding: EdgeInsets.only(left: 4),
                child: Text('Used to decide CGST + SGST (same state as the vendor) vs IGST on the PO.',
                  style: TextStyle(color: BT.mut2, fontSize: 11))),
              const SizedBox(height: 11),
              _field('PHONE', _phone, hint: '+91 …'),
              const SizedBox(height: 11),
              _field('EMAIL', _email, hint: 'orders@company.com'),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
                child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),
              const SizedBox(height: 22),
              _saving
                ? const Center(child: CircularProgressIndicator(color: BT.ink))
                : PrimaryButton('Save', icon: Icons.check, onTap: _save),
            ],
          );
        },
      )),
    );
  }

  Widget _field(String label, TextEditingController c, {String? hint, int lines = 1}) => Container(
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      TextField(
        controller: c, maxLines: lines,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BT.ink),
        decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero,
          hintText: hint, hintStyle: const TextStyle(color: BT.mut2, fontWeight: FontWeight.w500)),
      ),
    ]),
  );
}
