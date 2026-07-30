import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';

/// A photo the user picked, ready to upload.
class PickedPhoto {
  final Uint8List bytes;
  final String filename, contentType;
  const PickedPhoto(this.bytes, this.filename, this.contentType);

  /// Rough size for the "1.2 MB" hint next to a selected photo.
  String get sizeLabel {
    final kb = bytes.length / 1024;
    return kb < 1024 ? '${kb.round()} KB' : '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

String _contentTypeFor(String name, String? mime) {
  if (mime != null && mime.isNotEmpty) return mime;
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.heic') || n.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}

/// Ask for a photo: camera or gallery.
///
/// Downscaled and re-compressed on the device — build sites have bad signal and
/// a raw 12 MP photo is a slow, expensive upload for no extra useful detail.
/// Returns null if the user backs out or denies permission.
Future<PickedPhoto?> pickPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(color: BT.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
        _option(ctx, Icons.photo_camera_rounded, 'Take a photo', ImageSource.camera),
        const SizedBox(height: 10),
        _option(ctx, Icons.photo_library_rounded, 'Choose from gallery', ImageSource.gallery),
      ]),
    ),
  );
  if (source == null) return null;

  try {
    final x = await ImagePicker().pickImage(
      source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    return PickedPhoto(bytes, x.name, _contentTypeFor(x.name, x.mimeType));
  } catch (e) {
    // Almost always a denied camera/photos permission.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: BT.coral,
        content: Text('Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}. '
                      'Check the app\'s permissions.')));
    }
    return null;
  }
}

Widget _option(BuildContext ctx, IconData icon, String label, ImageSource source) =>
  GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.pop(ctx, source),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BT.line)),
      child: Row(children: [
        Container(width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: BT.ink)),
        const SizedBox(width: 14),
        Expanded(child: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
        const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
      ]),
    ),
  );

/// Thumbnail + size + remove, for a photo that's been picked but not yet sent.
class PhotoPreview extends StatelessWidget {
  final PickedPhoto photo;
  final VoidCallback onRemove;
  const PhotoPreview({super.key, required this.photo, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BT.line)),
    child: Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.memory(photo.bytes, width: 54, height: 54, fit: BoxFit.cover),
      ),
      const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Photo attached',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        const SizedBox(height: 2),
        Text(photo.sizeLabel, style: const TextStyle(color: BT.mut, fontSize: 11.5)),
      ])),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRemove,
        child: Container(width: 34, height: 34, alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFFFBE4E0),
            borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.close_rounded, size: 17, color: BT.coral)),
      ),
    ]),
  );
}
