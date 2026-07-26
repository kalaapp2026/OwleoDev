import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/core/widgets/avatar.dart';
import 'package:nest_fe/features/social/data/people_search_api.dart';
import 'package:nest_fe/features/social/presentation/user_profile_posts_screen.dart';

final peopleSearchApiProvider = Provider((ref) => PeopleSearchApi(ref.watch(dioClientProvider)));

/// Search-by-name/username, tap a result to see that person's posts (Instagram-style profile).
class SearchProfilesScreen extends ConsumerStatefulWidget {
  const SearchProfilesScreen({super.key});

  @override
  ConsumerState<SearchProfilesScreen> createState() => _SearchProfilesScreenState();
}

class _SearchProfilesScreenState extends ConsumerState<SearchProfilesScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PersonResult>? _results;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query.trim()));
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref.read(peopleSearchApiProvider).search(query);
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _error = 'Search failed - try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Search people',
            border: InputBorder.none,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_results == null) {
      return const EmptyState(icon: Icons.search, message: 'Search by name or username.');
    }
    if (_results!.isEmpty) {
      return const EmptyState(icon: Icons.person_search_outlined, message: 'No one found.');
    }
    return ListView.builder(
      itemCount: _results!.length,
      itemBuilder: (context, i) {
        final p = _results![i];
        return ListTile(
          leading: Avatar(name: p.fullName, imageUrl: p.profileImageUrl),
          title: Text(p.fullName),
          subtitle: Text('@${p.username}'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UserProfilePostsScreen(userId: p.id, fullName: p.fullName, username: p.username, profileImageUrl: p.profileImageUrl)),
          ),
        );
      },
    );
  }
}
