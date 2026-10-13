import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'animations.dart';
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

/// The content type of the bytes we are actually holding.
///
/// Sniffed from the file's magic number rather than taken from the filename or
/// the picker's `mimeType`. `image_picker` transcodes a HEIC to JPEG when it
/// resizes but keeps the original `.heic` name, so trusting the extension
/// uploaded JPEG bytes labelled `image/heic` — which Storage then served with
/// that type, and nothing could render it. The stored type has to describe the
/// data, not where it came from.
String _contentTypeFor(Uint8List bytes, String name, String? mime) {
  bool starts(List<int> magic, {int at = 0}) {
    if (bytes.length < at + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[at + i] != magic[i]) return false;
    }
    return true;
  }

  if (starts([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  // "RIFF....WEBP"
  if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], at: 8)) {
    return 'image/webp';
  }
  if (starts([0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  // "ftypheic" / "ftypheix" / "ftypmif1" inside an ISO-BMFF box header
  if (starts([0x66, 0x74, 0x79, 0x70], at: 4)) return 'image/heic';

  // Unrecognised header: fall back to what we were told, then to the extension.
  if (mime != null && mime.isNotEmpty) return mime;
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

/// The filename to store, with its extension matched to the real content type,
/// so `photo.heic` holding JPEG bytes is not saved under a lie.
String _filenameFor(String name, String contentType) {
  final ext = switch (contentType) {
    'image/png'  => 'png',
    'image/webp' => 'webp',
    'image/gif'  => 'gif',
    'image/heic' => 'heic',
    _            => 'jpg',
  };
  final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
  return '${base.isEmpty ? 'photo' : base}.$ext';
}

/// True while a pick is in flight. `image_picker` throws
/// `PlatformException(already_active)` if it is called again before the first
/// pick returns, and on Android the camera activity can take a second to come
/// up — which is exactly long enough for an impatient second tap. Every entry
/// point funnels through here, so one flag covers them all.
bool _picking = false;

/// Does this buffer actually decode into an image on this platform?
///
/// `Image.memory` throws *during layout* when handed something it cannot
/// decode, which surfaces as a crash rather than a broken-image box — no
/// `errorBuilder` can catch a codec that fails this way on some platforms. A
/// HEIC/HEIF frame from an iPhone gallery is the usual culprit: `image_picker`
/// transcodes to JPEG when it resizes, but not on every path and not on every
/// OS version. So the bytes are decoded once, here, before any widget sees
/// them — a photo that cannot be shown is reported as such instead of taking
/// the screen down mid-upload.
Future<bool> _decodes(Uint8List bytes) async {
  if (bytes.isEmpty) return false;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    frame.image.dispose();
    codec.dispose();
    return true;
  } catch (_) {
    return false;
  }
}

/// Ask for a photo: camera or gallery.
///
/// Downscaled and re-compressed on the device — build sites have bad signal and
/// a raw 12 MP photo is a slow, expensive upload for no extra useful detail.
/// Returns null if the user backs out, denies permission, or picks a file this
/// device cannot decode.
Future<PickedPhoto?> pickPhoto(BuildContext context) async {
  if (_picking) return null;
  final source = await showModalBottomSheet<ImageSource>(
      sheetAnimationStyle: sheetMotion,
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

  _picking = true;
  try {
    final x = await ImagePicker().pickImage(
      source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
    if (x == null) return null;
    final bytes = await x.readAsBytes();

    // Resizing normally re-encodes to JPEG, but not on every platform path, and
    // a 0-byte read happens when the OS reclaims the camera activity. Either
    // way, never hand bytes we haven't decoded to the widget tree.
    if (!await _decodes(bytes)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.coral,
          content: Text('That photo could not be read. Try taking it again, '
                        'or pick a JPEG or PNG from the gallery.')));
      }
      return null;
    }
    // The bytes decoded, so they are a format this device renders — label them
    // from the data itself rather than from a name the data no longer matches.
    final type = _contentTypeFor(bytes, x.name, x.mimeType);
    return PickedPhoto(bytes, _filenameFor(x.name, type), type);
  } catch (e) {
    // Almost always a denied camera/photos permission.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: BT.coral,
        content: Text('Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}. '
                      'Check the app\'s permissions.')));
    }
    return null;
  } finally {
    _picking = false;
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
        // pickPhoto decodes the bytes before returning them, so this should
        // always render — errorBuilder is the belt to that braces, because an
        // uncaught decode failure here takes down the whole screen.
        child: Image.memory(photo.bytes, width: 54, height: 54, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(width: 54, height: 54,
            alignment: Alignment.center, color: BT.card2,
            child: const Icon(Icons.broken_image_outlined, size: 20, color: BT.mut2))),
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
