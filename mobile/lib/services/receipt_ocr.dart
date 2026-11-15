import 'package:flutter/services.dart';

import '../core/receipt_parser.dart';

/// On-device text recognition for receipt photos. iOS uses Apple Vision
/// (Japanese from iOS 16), Android uses Google ML Kit's bundled Japanese
/// model. Photos never leave the device and there is no per-use cost.
abstract class ReceiptOcr {
  /// Recognized lines with normalized boxes; empty when nothing was read or
  /// OCR is unavailable on this device.
  Future<List<OcrLine>> recognize(String imagePath);
}

class PlatformReceiptOcr implements ReceiptOcr {
  static const _channel = MethodChannel('yenback/receipt_ocr');

  @override
  Future<List<OcrLine>> recognize(String imagePath) async {
    try {
      final result = await _channel.invokeListMethod<Object?>('recognize', {'path': imagePath});
      return [
        for (final m in result ?? const <Object?>[])
          if (m is Map) OcrLine.fromMap(m),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
