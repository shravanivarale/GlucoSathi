/// Reliable image-format detection from the file's actual bytes.
///
/// Filename extensions and MIME metadata are unreliable (e.g. the Android
/// Photo Picker may return null or inconsistent MIME, and `image_picker`
/// may materialize a cached filename without a `.jpg`/`.jpeg`/`.png` suffix).
/// The file's magic-byte signature is the authoritative source, matching the
/// backend's `sniff_image_mime` (see `backend/app/api/images.py`).
library;

import 'dart:io';

/// Image types the MVP accepts.
enum ImageFormat { jpeg, png, unknown }

const List<int> _jpegMagic = [0xFF, 0xD8, 0xFF];
const List<int> _pngMagic = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
];

/// Detects the format of [file] from its leading bytes.
///
/// Reads only the 8-byte header synchronously; returns [ImageFormat.unknown]
/// for unreadable, empty, or unsupported files.
ImageFormat detectImageFormat(File file) {
  try {
    final raf = file.openSync();
    try {
      return _matchFormat(raf.readSync(8));
    } finally {
      raf.closeSync();
    }
  } on Object {
    return ImageFormat.unknown;
  }
}

/// Maps [detectImageFormat] to the MIME type the backend expects, or `null`
/// when the file is not a recognized JPEG/PNG.
String? imageMimeType(File file) {
  return switch (detectImageFormat(file)) {
    ImageFormat.jpeg => 'image/jpeg',
    ImageFormat.png => 'image/png',
    ImageFormat.unknown => null,
  };
}

ImageFormat _matchFormat(List<int> data) {
  if (_hasMagic(data, _jpegMagic)) return ImageFormat.jpeg;
  if (_hasMagic(data, _pngMagic)) return ImageFormat.png;
  return ImageFormat.unknown;
}

bool _hasMagic(List<int> data, List<int> magic) {
  if (data.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (data[i] != magic[i]) return false;
  }
  return true;
}