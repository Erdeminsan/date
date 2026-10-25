import 'dart:typed_data';
import 'package:image/image.dart' as img;

// Run through compute() off the UI thread. Re-encoding a fresh pixel image
// strips EXIF/location metadata instead of uploading the original file.
Uint8List prepareProfilePhoto(Uint8List input) {
  if (input.length > 12 * 1024 * 1024) throw const FormatException('Fotoğraf çok büyük. Daha küçük bir fotoğraf seç.');
  final decoder = img.findDecoderForData(input);
  final info = decoder?.startDecode(input);
  if (info == null || info.width * info.height > 20000000) {
    throw const FormatException('Bu fotoğraf okunamadı. JPEG veya PNG seç.');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('Bu fotoğraf okunamadı. JPEG veya PNG seç.');
  final oriented = img.bakeOrientation(decoded);
  final scaled = oriented.width > 1024 || oriented.height > 1024
    ? (oriented.width >= oriented.height ? img.copyResize(oriented, width: 1024) : img.copyResize(oriented, height: 1024)) : oriented;
  final clean = img.Image(width: scaled.width, height: scaled.height, numChannels: 3);
  img.fill(clean, color: img.ColorRgb8(255,255,255));
  img.compositeImage(clean, scaled);
  final output = Uint8List.fromList(img.encodeJpg(clean, quality: 85));
  if (output.length > 2 * 1024 * 1024) throw const FormatException('Fotoğraf çok büyük. Daha küçük bir fotoğraf seç.');
  return output;
}
