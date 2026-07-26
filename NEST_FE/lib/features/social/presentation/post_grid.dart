import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/social/data/post.dart';
import 'package:nest_fe/features/social/presentation/feed_screen.dart';

/// Instagram-style square thumbnail grid - tap a tile to see the full post. A post with no image
/// (text-only) gets a text-snippet tile instead of a broken image. [isOwn] shows the "more" menu
/// (delete) on each tile's detail view - only meaningful on My Posts, never on someone else's profile.
class PostGrid extends StatelessWidget {
  const PostGrid({super.key, required this.posts, this.emptyMessage = 'No posts yet.', this.isOwn = false, this.onDeleted});

  final List<Post> posts;
  final String emptyMessage;
  final bool isOwn;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      // Wrapped in a scrollable so a pull-to-refresh above this still works on an empty grid.
      return ListView(children: [EmptyState(icon: Icons.grid_on_outlined, message: emptyMessage)]);
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: posts.length,
      itemBuilder: (context, i) => _PostThumbnail(post: posts[i], isOwn: isOwn, onDeleted: onDeleted),
    );
  }
}

class _PostThumbnail extends StatelessWidget {
  const _PostThumbnail({required this.post, required this.isOwn, this.onDeleted});
  final Post post;
  final bool isOwn;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final imageUrl = post.mediaUrls.isNotEmpty ? ApiConfig.resolveMediaUrl(post.mediaUrls.first) : null;
    return InkWell(
      onTap: () async {
        final deleted = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => PostDetailScreen(post: post, isOwn: isOwn)),
        );
        if (deleted == true) onDeleted?.call();
      },
      child: imageUrl != null
          ? Image.network(imageUrl, fit: BoxFit.cover)
          : Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(6),
              alignment: Alignment.center,
              child: Text(
                post.content ?? '',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
    );
  }
}

/// Full post view opened from a grid tile - every image full-width, then the caption. [isOwn]
/// (My Posts only) adds a "more" menu with Delete; pops `true` if the post was deleted so the
/// caller can refresh its list.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.post, this.isOwn = false});
  final Post post;
  final bool isOwn;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  bool _deleting = false;

  Future<void> _confirmDelete() async {
    final confirmed = await AppNotice.confirm(
      context,
      title: 'Delete post?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    setState(() => _deleting = true);
    try {
      await ref.read(socialApiProvider).deletePost(widget.post.id);
      ref.invalidate(feedProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return Scaffold(
      appBar: AppBar(
        title: Text(post.type == 'EVENT_REF' ? 'Event' : 'Post'),
        actions: [
          if (widget.isOwn)
            _deleting
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) {
                      if (v == 'delete') _confirmDelete();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
        ],
      ),
      body: ListView(
        children: [
          for (final url in post.mediaUrls)
            if (ApiConfig.resolveMediaUrl(url) case final resolved?) Image.network(resolved, fit: BoxFit.cover),
          if (post.content != null && post.content!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(post.content!, style: Theme.of(context).textTheme.bodyLarge),
            ),
        ],
      ),
    );
  }
}
