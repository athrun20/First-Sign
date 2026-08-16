import 'dart:io';
import 'dart:ui' as ui;

Future<void> main() async {
  final paths = [
    'assets/calibration/healthy_multi_angle/00_front.jpg',
    'assets/calibration/severe_roof_damage/01_roof.jpg',
    'assets/calibration/severe_roof_damage/02_closeup.jpg',
  ];
  for (final p in paths) {
    final sw = Stopwatch()..start();
    final bytes = await File(p).readAsBytes();
    print('read $p ${bytes.length} in ${sw.elapsedMilliseconds}ms');
    sw.reset();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160, targetHeight: 160);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final bd = await img.toByteData();
    print('decode $p ${img.width}x${img.height} rgba=${bd?.lengthInBytes} in ${sw.elapsedMilliseconds}ms');
    img.dispose();
  }
}
