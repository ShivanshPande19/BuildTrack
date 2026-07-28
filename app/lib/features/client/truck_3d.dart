import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../core/theme.dart';

/// Demo asset for the prototype — a public-domain truck (.glb) served with
/// proper CORS + content-type via jsDelivr. In production this URL comes from
/// the approved design version (design_versions.file_url) per project.
const String kDemoTruckGlb =
    'https://cdn.jsdelivr.net/gh/KhronosGroup/glTF-Sample-Models@master/2.0/CesiumMilkTruck/glTF-Binary/CesiumMilkTruck.glb';

/// A small interactive 3D preview of an approved truck design.
/// Wraps Google's <model-viewer> web component (auto-rotate, drag to spin,
/// pinch to zoom, and AR on supported devices).
class Truck3DPreview extends StatelessWidget {
  final String glbUrl;
  final String label;
  final double height;

  /// When true, tapping the "expand" button opens a full-screen viewer.
  final bool expandable;

  const Truck3DPreview({
    super.key,
    required this.glbUrl,
    this.label = 'Design preview',
    this.height = 200,
    this.expandable = true,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(children: [
          Positioned.fill(
            child: ModelViewer(
              key: ValueKey(glbUrl),
              src: glbUrl,
              alt: 'A 3D model of $label',
              ar: true,
              autoRotate: true,
              autoRotateDelay: 0,
              rotationPerSecond: '20deg',
              cameraControls: true,
              disableZoom: false,
              backgroundColor: const Color(0xFFF1EEE7),
            ),
          ),
          // "3D" badge — top-left.
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: BT.ink, borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.view_in_ar_rounded, size: 13, color: Colors.white),
                SizedBox(width: 5),
                Text('3D preview',
                    style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
              ]),
            ),
          ),
          // Expand button — top-right.
          if (expandable)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Truck3DFullScreen(glbUrl: glbUrl, label: label),
                )),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: const Icon(Icons.fullscreen_rounded, size: 20, color: BT.ink),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Full-screen 3D viewer — bigger canvas to inspect the design.
class Truck3DFullScreen extends StatelessWidget {
  final String glbUrl;
  final String label;
  const Truck3DFullScreen({super.key, required this.glbUrl, this.label = 'Design preview'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1EEE7),
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(
            child: ModelViewer(
              key: ValueKey('full-$glbUrl'),
              src: glbUrl,
              alt: 'A 3D model of $label',
              ar: true,
              autoRotate: true,
              autoRotateDelay: 1200,
              rotationPerSecond: '18deg',
              cameraControls: true,
              disableZoom: false,
              backgroundColor: const Color(0xFFF1EEE7),
            ),
          ),
          Positioned(
            top: 8,
            left: 12,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: const Icon(Icons.close_rounded, size: 22, color: BT.ink),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 22,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(color: BT.ink, borderRadius: BorderRadius.circular(22)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.threesixty_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 7),
                  Text('Drag to rotate · pinch to zoom',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
