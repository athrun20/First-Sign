import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Shared thumbnail for capture / report photo grids.
class PhotoThumb extends StatelessWidget {
  final XFile photo;

  const PhotoThumb({super.key, required this.photo});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: photo.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            color: const Color(0xFFE2E8F0),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      },
    );
  }
}
