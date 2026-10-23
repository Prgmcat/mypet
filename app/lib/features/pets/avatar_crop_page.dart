import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../../core/toast.dart';

/// Full-screen avatar editor: the circle stays fixed while the photo can be
/// dragged and pinch-zoomed underneath, so any part of the picture can be
/// framed as the avatar.
class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  final _controller = CropController();
  bool _ready = false;
  bool _cropping = false;

  void _confirm() {
    if (!_ready || _cropping) return;
    setState(() => _cropping = true);
    _controller.cropCircle();
  }

  void _onCropped(CropResult result) {
    if (!mounted) return;
    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop<Uint8List>(croppedImage);
      case CropFailure():
        setState(() => _cropping = false);
        showToast(context, '裁剪失败，请重试', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('调整头像'),
        actions: [
          TextButton(
            onPressed: _ready && !_cropping ? _confirm : null,
            child: Text(
              _cropping ? '处理中…' : '完成',
              style: TextStyle(
                color: _ready && !_cropping ? Colors.white : Colors.white38,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Crop(
            image: widget.imageBytes,
            controller: _controller,
            onCropped: _onCropped,
            onStatusChanged: (status) {
              if (!mounted) return;
              setState(() => _ready = status == CropStatus.ready);
            },
            interactive: true,
            fixCropRect: true,
            withCircleUi: true,
            maskColor: const Color(0x99000000),
            baseColor: Colors.black,
            filterQuality: FilterQuality.high,
          ),
          if (_cropping)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '拖动照片调整位置，双指缩放',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
