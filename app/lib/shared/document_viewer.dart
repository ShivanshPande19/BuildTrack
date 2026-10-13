import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import 'widgets.dart';

/// Open one of a build's documents (contract, invoice, warranty pack, handover
/// certificate) from wherever it is listed.
///
/// The client's document list used to answer a tap with an "Opening document…"
/// snackbar and nothing else — the one row a client is most likely to press did
/// nothing at all. This actually opens the file:
///
///   • a **PDF** goes to the OS preview sheet (`printing`), which also offers
///     print, share and save-to-files — more useful than a browser tab, and it
///     needs no extra dependency;
///   • an **image** opens in a full-screen in-app viewer, the same one the stage
///     photos and bills use;
///   • anything else falls back to copying the link, with a message that says so
///     rather than pretending.
///
/// The bytes are fetched through the Supabase client rather than a bare URL, so
/// this keeps working if the buckets are made private later (a signed URL or an
/// authenticated download replaces one call here, not every call site).
Future<void> openDocument(BuildContext context, {
  required String? fileUrl,
  required String title,
}) async {
  final url = fileUrl?.trim();
  if (url == null || url.isEmpty) {
    _say(context, 'That document has not been uploaded yet.', error: true);
    return;
  }

  final bar = ScaffoldMessenger.of(context);
  bar.showSnackBar(SnackBar(
    backgroundColor: BT.ink,
    duration: const Duration(minutes: 1),
    content: Row(children: [
      const SizedBox(width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: BT.lime)),
      const SizedBox(width: 12),
      Expanded(child: Text('Opening $title…')),
    ])));

  try {
    final bytes = await downloadFromUrl(url);
    bar.clearSnackBars();
    if (!context.mounted) return;

    final lower = url.toLowerCase().split('?').first;
    final isPdf = lower.endsWith('.pdf') || _looksLikePdf(bytes);
    final isImage = ['.png', '.jpg', '.jpeg', '.webp', '.gif'].any(lower.endsWith);

    if (isPdf) {
      // Native preview sheet: scroll, print, share, save to Files.
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: _filename(title, 'pdf'),
      );
      return;
    }
    if (isImage) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _ImageViewer(bytes: bytes, title: title)));
      return;
    }
    // An unknown type: don't guess at a viewer, hand over the link.
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      _say(context, 'This file type can\'t be previewed here — the link is copied '
                    'to your clipboard, open it in a browser.');
    }
  } catch (e) {
    bar.clearSnackBars();
    if (context.mounted) _say(context, 'Could not open $title. ${friendlyError(e)}', error: true);
  }
}

/// "%PDF" — trust the bytes over the extension, the way the photo picker does.
bool _looksLikePdf(List<int> b) =>
    b.length > 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46;

String _filename(String title, String ext) {
  final safe = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  return '${safe.isEmpty ? 'document' : safe}.$ext';
}

void _say(BuildContext context, String msg, {bool error = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? BT.coral : BT.ink, content: Text(msg)));

/// Full-screen image document, pinch to zoom, with the same dark backdrop the
/// stage-photo and bill viewers use.
class _ImageViewer extends StatelessWidget {
  final Uint8List bytes;
  final String title;
  const _ImageViewer({required this.bytes, required this.title});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
        child: Row(children: [
          const BackChip(icon: Icons.close_rounded),
          const SizedBox(width: 12),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15))),
        ]),
      ),
      Expanded(child: InteractiveViewer(
        minScale: 1, maxScale: 5,
        child: Center(child: Image.memory(bytes, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Text('Could not display this document',
            style: TextStyle(color: Colors.white70)))),
      )),
    ])),
  );
}
