import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Registration-time "add a photo" control - a circular preview (picked image, or a camera icon
/// placeholder until something's chosen) plus a text button, shared by the Student and Trainer
/// forms. Reads bytes rather than a file path so it works the same on web (no filesystem access)
/// and Android/iOS.
class ProfileImagePicker extends StatefulWidget {
  const ProfileImagePicker({super.key, required this.onPicked});

  final void Function(XFile? file, Uint8List? bytes) onPicked;

  @override
  State<ProfileImagePicker> createState() => _ProfileImagePickerState();
}

class _ProfileImagePickerState extends State<ProfileImagePicker> {
  XFile? _picked;
  Uint8List? _bytes;

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _picked = file;
      _bytes = bytes;
    });
    widget.onPicked(file, bytes);
  }

  void _clear() {
    setState(() {
      _picked = null;
      _bytes = null;
    });
    widget.onPicked(null, null);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: colorScheme.primaryContainer,
          backgroundImage: _bytes != null ? MemoryImage(_bytes!) : null,
          child: _bytes == null ? Icon(Icons.camera_alt_outlined, color: colorScheme.onPrimaryContainer) : null,
        ),
        const SizedBox(width: 12),
        TextButton(onPressed: _pick, child: Text(_picked == null ? 'Add photo (optional)' : 'Change photo')),
        if (_picked != null) IconButton(onPressed: _clear, icon: const Icon(Icons.close, size: 18), tooltip: 'Remove'),
      ],
    );
  }
}
