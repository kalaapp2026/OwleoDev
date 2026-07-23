import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/social/data/post.dart';
import 'package:nest_fe/features/social/data/social_api.dart';

final socialApiProvider = Provider((ref) => SocialApi(ref.watch(dioClientProvider)));
final feedProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(socialApiProvider).feed();
});

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(feedProvider.future),
      child: AsyncValueView<List<Post>>(
        value: feed,
        onRetry: () => ref.invalidate(feedProvider),
        data: (context, posts) {
          if (posts.isEmpty) {
            return ListView(
              children: const [EmptyState(icon: Icons.dynamic_feed_outlined, message: 'No posts yet - academy and artist posts will show up here.')],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: posts.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _PostCard(post: posts[index]),
          );
        },
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEvent = post.type == 'EVENT_REF';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isEvent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('EVENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: colorScheme.secondary)),
                  ),
              ],
            ),
            if (isEvent) const SizedBox(height: 8),
            Text(post.content ?? '', style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
