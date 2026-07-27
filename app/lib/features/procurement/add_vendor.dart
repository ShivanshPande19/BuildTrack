import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Procurement — add a new vendor.
class AddVendorScreen extends ConsumerStatefulWidget {
  const AddVendorScreen({super.key});
  @override
  ConsumerState<AddVendorScreen> createState() => _AddVendorScreenState();
}

class _AddVendorScreenState extends ConsumerState<AddVendorScreen> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _lead = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Vendor name is required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(procurementRepoProvider).addVendor(
        name: _name.text.trim(),
        category: _category.text.trim().isEmpty ? null : _category.text.trim(),
        avgLead: int.tryParse(_lead.text.trim()) ?? 0,
      );
      ref.invalidate(vendorsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink, content: Text('${_name.text.trim()} added.')));
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: ListView(
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
          Text('New vendor', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 20),
          _field('VENDOR NAME', _name, hint: 'Sharma Traders'),
          const SizedBox(height: 11),
          _field('CATEGORY', _category, hint: 'Electronics / Fabrication …'),
          const SizedBox(height: 11),
          _field('AVERAGE LEAD TIME (DAYS)', _lead, hint: '4', number: true),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),
          const SizedBox(height: 22),
          _saving
            ? const Center(child: CircularProgressIndicator(color: BT.ink))
            : PrimaryButton('Add vendor', icon: Icons.check, onTap: _submit),
        ],
      )),
    );
  }

  Widget _field(String label, TextEditingController c, {String? hint, bool number = false}) => Container(
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      TextField(
        controller: c, keyboardType: number ? TextInputType.number : null,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BT.ink),
        decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero,
          hintText: hint, hintStyle: const TextStyle(color: BT.mut2, fontWeight: FontWeight.w500)),
      ),
    ]),
  );
}
