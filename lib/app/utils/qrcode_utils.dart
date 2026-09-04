import 'package:flutter/widgets.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:karing/app/runtime/return_result.dart';
import 'package:zxing2/qrcode.dart';

/// QR code helpers: decode from image files, encode to png bytes.
class QrcodeUtils {
  static Future<String?> scanFromFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return scanFromImageData(bytes);
    } catch (_) {
      return null;
    }
  }

  static String? scanFromImageData(Uint8List data) {
    try {
      final image = img.decodeImage(data);
      if (image == null) {
        return null;
      }
      final lum = img.grayscale(image);
      final width = lum.width;
      final height = lum.height;
      final pixels = Int32List(width * height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final p = lum.getPixel(x, y);
          pixels[y * width + x] = p.luminance.round();
        }
      }
      final source = RGBLuminanceSource(width, height, pixels);
      final binarizer = HybridBinarizer(source);
      final reader = QRCodeReader();
      final result = reader.decode(BinaryBitmap(binarizer));
      return result.text;
    } catch (_) {
      return null;
    }
  }

  static ReturnResult<Image> toImage(String content, {int size = 512}) {
    final bytes = _toImageImpl(content, size: size);
    if (bytes == null) {
      return ReturnResult(error: ReturnResultError("generate qrcode failed"));
    }
    return ReturnResult(data: Image.memory(bytes));
  }

  static Future<String?> saveAsImage(String content, String savePath) async {
    final bytes = _toImageImpl(content);
    if (bytes == null) {
      return "generate qrcode failed";
    }
    try {
      final file = File(savePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return null;
    } catch (err) {
      return err.toString();
    }
  }

  static Uint8List? _toImageImpl(String content, {int size = 512}) {
    try {
      final qr = Encoder.encode(
        content,
        ErrorCorrectionLevel.h,
      );
      final matrix = qr.matrix;
      if (matrix == null) {
        return null;
      }
      final mw = matrix.width;
      final mh = matrix.height;
      final scale = size < mw ? 1 : size ~/ mw;
      final dim = mw * scale;
      final image = img.Image(width: dim, height: dim);
      for (int y = 0; y < mh; y++) {
        for (int x = 0; x < mw; x++) {
          final on = matrix.get(x, y) == 1;
          if (!on) {
            continue;
          }
          for (int sy = 0; sy < scale; sy++) {
            for (int sx = 0; sx < scale; sx++) {
              image.setPixelRgba(
                  x * scale + sx, y * scale + sy, 0, 0, 0, 255);
            }
          }
        }
      }
      return Uint8List.fromList(img.encodePng(image));
    } catch (_) {
      return null;
    }
  }
}
