import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'lodepng_flutter_bindings_generated.dart';

const String _libName = 'lodepng_flutter';

/// The dynamic library in which the symbols for [LodepngFlutterBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final LodepngFlutterBindings _bindings = LodepngFlutterBindings(_dylib);

class Image {
  /// The image data. Each pixel is represented by four bytes in the order of RGBA.
  final Uint8List data;

  final int width;

  final int height;

  /// Creates an image with the given [data], [width], and [height].
  const Image(this.data, this.width, this.height);
}

/// Decodes a PNG image from [data].
Image decodePng(Uint8List data) {
  final buffer = decodePngToPointer(data);
  final data1 = Pointer<Uint8>
      .fromAddress(buffer.address)
      .asTypedList(buffer.length);
  final image = Image(data1, buffer.length ~/ 4, buffer.length ~/ 4);
  _bindings.freePtr(Pointer.fromAddress(buffer.address));
  return image;
}

ByteBuffer decodePngToPointer(Uint8List data) {
  Pointer<Pointer<UnsignedChar>> out = malloc.allocate(sizeOf<Pointer>());
  Pointer<UnsignedInt> w = malloc.allocate(sizeOf<UnsignedInt>());
  Pointer<UnsignedInt> h = malloc.allocate(sizeOf<UnsignedInt>());
  final insize = data.length;
  final in1 = malloc.allocate<Uint8>(insize);
  in1.asTypedList(insize).setAll(0, data);
  _bindings.lodepng_decode32(out, w, h, in1.cast(), insize);
  final width = w.value;
  final height = h.value;
  malloc.free(w);
  malloc.free(h);
  malloc.free(in1);
  final out1 = out.value;
  malloc.free(out);
  return ByteBuffer(out1.address, width * height * 4);
}

/// Encodes [image] to a PNG image.
Uint8List encodePng(Image image) {
  final buffer = encodePngToPointer(image);
  final data = Pointer<Uint8>
      .fromAddress(buffer.address)
      .asTypedList(buffer.length);
  _bindings.freePtr(Pointer.fromAddress(buffer.address));
  return data;
}

class ByteBuffer {
  final int address;

  final int length;

  ByteBuffer(this.address, this.length);

  static Pointer<NativeFinalizerFunction> get finalizer => _dylib.lookup('freePtr');
}

ByteBuffer encodePngToPointer(Image image) {
  Pointer<Pointer<UnsignedChar>> out = malloc.allocate(sizeOf<Pointer>());
  Pointer<Size> outsize = malloc.allocate(sizeOf<Size>());
  final insize = image.data.length;
  final in1 = malloc.allocate<Uint8>(insize);
  in1.asTypedList(insize).setAll(0, image.data);
  _bindings.lodepng_encode32(
    out,
    outsize,
    in1.cast(),
    image.width,
    image.height,
  );
  final size = outsize.value;
  final out1 = out.value;
  malloc.free(out);
  malloc.free(outsize);
  malloc.free(in1);
  return ByteBuffer(out1.address, size);
}
