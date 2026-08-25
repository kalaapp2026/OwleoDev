import 'package:nest_fe/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/social/data/post.dart';
import 'package:nest_fe/features/social/domain/post_permission.dart';
import 'package:nest_fe/features/social/presentation/create_post_screen.dart';
import 'package:nest_fe/features/social/presentation/feed_screen.dart';
import 'package:nest_fe/features/social/presentation/post_grid.dart';

final myPostsProvider = FutureProvider.autoDispose((ref) {
  final userId = ref.watch(sessionControllerProvider).user?.id;
  if (userId == null) return Future.value(<Post>[]);
  return ref.watch(socialApiProvider).postsByUser(userId);
});

/// Bottom-nav "My Posts" - every post this person has made, grid view. The upload/compose button
/// only shows for roles the backend actually allows to post (PRD 3.13); for an Artist this is
/// their event/announcement upload.
class MyPostsScreen extends ConsumerWidget {
  const MyPostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final canPost = userCanPost(user);
    final postsAsync = ref.watch(myPostsProvider);

    return Scaffold(
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context).socNewPost),
              onPressed: () async {
                final posted = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                );
                if (posted == true) ref.invalidate(myPostsProvider);
              },
            )
          : null,
      body: AsyncValueView<List<Post>>(
        value: postsAsync,
        onRetry: () => ref.invalidate(myPostsProvider),
        data: (context, posts) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myPostsProvider);
            await ref.read(myPostsProvider.future);
          },
          child: PostGrid(
            posts: posts,
            emptyMessage: canPost ? 'Nothing posted yet - tap New post to share something.' : 'Nothing posted yet.',
            isOwn: true,
            onDeleted: () => ref.invalidate(myPostsProvider),
          ),
        ),
      ),
    );
  }
}
