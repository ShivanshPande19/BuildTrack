import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/theme.dart';

/// Full-screen camera scanner. Pops the scanned string, or null if cancelled.
///
/// Used for reading a part's serial off its QR/barcode label at install time —
/// typing a 12-character serial on a workshop floor is slow and error-prone.
/// There's a manual-entry escape hatch for damaged or missing labels.
class BarcodeScannerScreen extends StatefulWidget {
  final String title, hint;
  const BarcodeScannerScreen({
    super.key,
    this.title = 'Scan serial',
    this.hint = 'Point the camera at the part\'s barcode or QR label',
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  // noDuplicates: one hit per label, so a steady camera doesn't fire repeatedly.
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _handled = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && v.isNotEmpty) {
        _handled = true;                 // guard against a second frame landing
        Navigator.pop(context, v);
        return;
      }
    }
  }

  Future<void> _manualEntry() async {
    final c = TextEditingController();
    final v = await showDialog<String>(context: context, builder: (dctx) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Enter serial', style: display(18, w: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('For a damaged or missing label.',
            style: TextStyle(color: BT.mut, fontSize: 12.5)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(controller: c, autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'SN-88213-KD', border: InputBorder.none)),
          ),
        ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx),
          child: const Text('Cancel', style: TextStyle(color: BT.mut))),
        TextButton(onPressed: () => Navigator.pop(dctx, c.text.trim()),
          child: const Text('Find', style: TextStyle(color: BT.ink, fontWeight: FontWeight.w700))),
      ],
    ));
    if (v != null && v.isNotEmpty && mounted) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          // A denied permission or no camera must not show a black void.
          errorBuilder: (context, error) => _cameraUnavailable(error),
        )),

        // viewfinder
        Positioned.fill(child: IgnorePointer(child: Center(
          child: Container(
            width: 250, height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: BT.lime, width: 3),
              borderRadius: BorderRadius.circular(24)),
          ),
        ))),

        // top bar
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _circleBtn(Icons.close_rounded, () => Navigator.pop(context)),
            _circleBtn(_torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
              () async {
                await _controller.toggleTorch();
                if (mounted) setState(() => _torch = !_torch);
              }),
          ]),
        )),

        // bottom hint + manual fallback
        Positioned(left: 0, right: 0, bottom: 0, child: SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.title, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(widget.hint, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
            const SizedBox(height: 16),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _manualEntry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                decoration: BoxDecoration(color: BT.card,
                  borderRadius: BorderRadius.circular(999)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.keyboard_rounded, size: 17, color: BT.ink),
                  SizedBox(width: 8),
                  Text('Enter serial manually',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: BT.ink)),
                ]),
              ),
            ),
          ]),
        ))),
      ]),
    );
  }

  Widget _cameraUnavailable(Object error) => Container(
    color: BT.bg,
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 58, height: 58, alignment: Alignment.center,
        decoration: BoxDecoration(color: BT.coral, shape: BoxShape.circle),
        child: const Icon(Icons.no_photography_rounded, size: 26, color: BT.ink)),
      const SizedBox(height: 16),
      Text('Camera not available', textAlign: TextAlign.center,
        style: display(19, w: FontWeight.w600)),
      const SizedBox(height: 8),
      const Text(
        'Allow camera access in your device settings, or enter the serial by hand.',
        textAlign: TextAlign.center,
        style: TextStyle(color: BT.mut, fontSize: 13, height: 1.4)),
      const SizedBox(height: 20),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _manualEntry,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(color: BT.ink, borderRadius: BorderRadius.circular(999)),
          child: const Text('Enter serial manually',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
        ),
      ),
      const SizedBox(height: 12),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(context),
        child: const Text('Go back', style: TextStyle(color: BT.mut, fontSize: 13)),
      ),
    ]),
  );

  Widget _circleBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(width: 44, height: 44, alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
      child: Icon(icon, size: 22, color: Colors.white)),
  );
}
