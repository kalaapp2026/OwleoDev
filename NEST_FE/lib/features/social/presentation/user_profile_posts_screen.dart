import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/core/widgets/avatar.dart';
import 'package:nest_fe/features/social/data/post.dart';
import 'package:nest_fe/features/social/presentation/feed_screen.dart';
import 'package:nest_fe/features/social/presentation/post_grid.dart';

final _profilePostsProvider = FutureProvider.autoDispose.family<List<Post>, String>((ref, userId) {
  return ref.watch(socialApiProvider).postsByUser(userId);
});

/// Someone else's profile, opened from Search - a header (photo/name/username) over a grid of
/// their posts, same layout Instagram uses for any profile you visit.
class UserProfilePostsScreen extends ConsumerWidget {
  const UserProfilePostsScreen({
    super.key,
    required this.userId,
    required this.fullName,
    required this.username,
    required this.profileImageUrl,
  });

  final String userId;
  final String fullName;
  final String username;
  final String? profileImageUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(_profilePostsProvider(userId));

    return Scaffold(
      appBar: AppBar(title: Text('@$username')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Avatar(name: fullName, imageUrl: profileImageUrl, radius: 36),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fullName, style: Theme.of(context).textTheme.titleMedium),
                      Text('@$username', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<List<Post>>(
              value: postsAsync,
              onRetry: () => ref.invalidate(_profilePostsProvider(userId)),
              data: (context, posts) => PostGrid(posts: posts, emptyMessage: 'No posts yet.'),
            ),
          ),
        ],
      ),
    );
  }
}
