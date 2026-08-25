import 'package:nest_fe/l10n/app_localizations.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/social/presentation/feed_screen.dart';

/// Compose a new post - caption + any number of photos. Visibility is always PUBLIC: the only
/// place Social posts are consumed today is the public feed, and an Artist (the primary poster)
/// has no academy to scope an ACADEMY_ONLY post to anyway.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _contentController = TextEditingController();
  final _picked = <(XFile, Uint8List)>[];
  bool _isPosting = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final files = await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 85);
    if (files.isEmpty) return;
    final withBytes = await Future.wait(files.map((f) async => (f, await f.readAsBytes())));
    setState(() => _picked.addAll(withBytes));
  }

  Future<void> _post() async {
    if (_contentController.text.trim().isEmpty && _picked.isEmpty) {
      AppNotice.error(context, AppLocalizations.of(context).socNeedCaptionOrPhoto);
      return;
    }
    setState(() => _isPosting = true);
    try {
      final api = ref.read(socialApiProvider);
      final post = await api.createPost(content: _contentController.text.trim(), visibility: 'PUBLIC');

      String? mediaWarning;
      for (final (file, bytes) in _picked) {
        try {
          await api.addMedia(post.id, bytes, file.name);
        } on ApiException catch (e) {
          mediaWarning = ' (one photo failed to upload: ${e.message})';
        }
      }

      if (!mounted) return;
      ref.invalidate(feedProvider);
      AppNotice.success(context, 'Posted.${mediaWarning ?? ''}');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).socNewPost),
        actions: [
          TextButton(
            onPressed: _isPosting ? null : _post,
            child: _isPosting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(AppLocalizations.of(context).socPost),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _contentController,
            maxLines: 5,
            decoration: InputDecoration(labelText: AppLocalizations.of(context).fieldCaption, alignLabelWithHint: true),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          if (_picked.isNotEmpty)
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _picked.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_picked[i].$2, width: 90, height: 90, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: () => setState(() => _picked.removeAt(i)),
                        child: const CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_picked.isEmpty ? 'Add photos' : 'Add more photos'),
          ),
        ],
      ),
    );
  }
}
