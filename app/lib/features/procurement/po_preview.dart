import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/animations.dart';
import '../../shared/widgets.dart';
import 'po_document.dart';

/// The purchase order as a document you can read, with printing one tap away.
///
/// "View / print PO document" used to go straight to the OS print sheet. That
/// is the right destination for *print*, and the wrong one for *view*: most
/// times this button is pressed the question is "what does this PO say" — to
/// check a rate before signing, or to read it back to a vendor on the phone —
/// and being dropped into a printer picker to answer it is a dead end you have
/// to back out of.
///
/// So the document comes first, full page and scrollable, and print, share and
/// save sit in a bar underneath it.
class PoPreviewScreen extends ConsumerStatefulWidget {
  final String poId;
  final String? poNumber; // for an instant title while the data loads
  const PoPreviewScreen({super.key, required this.poId, this.poNumber});

  @override
  ConsumerState<PoPreviewScreen> createState() => _PoPreviewScreenState();
}

class _PoPreviewScreenState extends ConsumerState<PoPreviewScreen> {
  PoDocData? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(procurementRepoProvider).poDocData(widget.poId);
      if (!mounted) return;
      setState(() { _data = d; _error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _data?.detail.po.poNumber ?? widget.poNumber ?? 'Purchase order';
    return Scaffold(
      backgroundColor: BT.bg,
      body: SafeArea(child: Column(children: [
        // The header stays put while the document loads, so the screen can
        // always be left — including from the error state.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Row(children: [
            const BackChip(),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Eyebrow('Purchase order'),
              const SizedBox(height: 2),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: display(22, w: FontWeight.w600)),
            ])),
          ]),
        ),
        Expanded(child: _body()),
      ])),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: ErrorCard('Could not build the document.\n$_error',
          onRetry: () { setState(() => _error = null); _load(); }),
      );
    }
    final d = _data;
    if (d == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: SkeletonList(count: 4, leading: false, trailingPill: false));
    }

    return ContentReveal(child: PdfPreview(
      build: (format) => buildPoDocument(d, format),
      // A GST purchase order is A4 portrait. Offering page size and orientation
      // would be offering to produce a document nobody would accept.
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      initialPageFormat: PdfPageFormat.a4,
      pdfFileName: '${d.detail.po.poNumber}.pdf',
      // Print and share are the only two things to do with it; both are real
      // OS sheets, not in-app approximations.
      allowPrinting: true,
      allowSharing: true,
      loadingWidget: const Center(
        child: SizedBox(width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: BT.mut2))),
      scrollViewDecoration: const BoxDecoration(color: BT.bg),
      pdfPreviewPageDecoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      previewPageMargin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: EdgeInsets.zero,
      actionBarTheme: const PdfActionBarTheme(
        backgroundColor: BT.card,
        iconColor: BT.ink,
        elevation: 0,
      ),
    ));
  }
}
