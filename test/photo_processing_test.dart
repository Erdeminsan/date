import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:playmatch/backend/photo_processing.dart';

void main() {
  test('Normalizes a large PNG to a bounded opaque JPEG', () {
    final source = img.Image(width:1600,height:800,numChannels:4);
    img.fill(source,color:img.ColorRgba8(20,80,160,128));
    source.textData = {'Comment':'private-location-metadata'};
    final output=prepareProfilePhoto(Uint8List.fromList(img.encodePng(source)));
    expect(output.take(2).toList(),[255,216]);
    final decoded=img.decodeJpg(output)!;
    expect(decoded.width,1024);
    expect(decoded.height,512);
    expect(decoded.numChannels,3);
    expect(decoded.textData?.containsValue('private-location-metadata') ?? false,isFalse);
    expect(output.length,lessThanOrEqualTo(2*1024*1024));
  });
  test('Invalid and over-limit files are rejected before upload', () {
    expect(()=>prepareProfilePhoto(Uint8List.fromList([1,2,3])),throwsFormatException);
    expect(()=>prepareProfilePhoto(Uint8List(12*1024*1024+1)),throwsFormatException);
  });
}
