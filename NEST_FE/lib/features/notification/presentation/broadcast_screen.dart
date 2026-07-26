import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_onboarding_api.dart';
import 'package:nest_fe/features/academy/presentation/academy_onboarding_screen.dart';
import 'package:nest_fe/features/notification/data/notification_api.dart';
import 'package:nest_fe/features/notification/presentation/notifications_screen.dart';

/// The Super Admin announcement console. Compose one message, pick which bell it lands in (Social
/// vs ERP) and who gets it (everyone, or one academy's members), and send.
class BroadcastScreen extends ConsumerStatefulWidget {
  const BroadcastScreen({super.key, required this.initialModule});

  final NotificationModule initialModule;

  @override
  ConsumerState<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends ConsumerState<BroadcastScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  late NotificationModule _module = widget.initialModule;
  String _audience = 'EVERYONE';
  String? _academyId;
  bool _isSending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_titleController.text.trim().isEmpty || _bodyController.text.trim().isEmpty) {
      AppNotice.error(context, 'Give the announcement a title and a message.');
      return;
    }
    if (_audience == 'ACADEMY' && _academyId == null) {
      AppNotice.error(context, 'Pick which academy to notify.');
      return;
    }
    setState(() => _isSending = true);
    try {
      final reached = await ref.read(notificationApiProvider).broadcast(
            module: _module,
            audience: _audience,
            academyId: _audience == 'ACADEMY' ? _academyId : null,
            title: _titleController.text.trim(),
            body: _bodyController.text.trim(),
          );
      if (mounted) {
        AppNotice.success(context, 'Sent to $reached ${reached == 1 ? 'person' : 'people'}.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Broadcast announcement')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Which bell does this land in?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<NotificationModule>(
            segments: const [
              ButtonSegment(value: NotificationModule.social, label: Text('Social'), icon: Icon(Icons.dynamic_feed_outlined)),
              ButtonSegment(value: NotificationModule.erp, label: Text('ERP'), icon: Icon(Icons.dashboard_outlined)),
            ],
            selected: {_module},
            onSelectionChanged: (s) => setState(() => _module = s.first),
          ),
          const SizedBox(height: 20),
          Text('Who gets it?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'EVERYONE', label: Text('Everyone')),
              ButtonSegment(value: 'ACADEMY', label: Text('One academy')),
            ],
            selected: {_audience},
            onSelectionChanged: (s) => setState(() => _audience = s.first),
          ),
          if (_audience == 'ACADEMY') ...[
            const SizedBox(height: 12),
            _AcademyPicker(
              selectedAcademyId: _academyId,
              onChanged: (id) => setState(() => _academyId = id),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            decoration: const InputDecoration(labelText: 'Message'),
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.send_outlined),
            onPressed: _isSending ? null : _send,
            label: _isSending
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send'),
          ),
        ],
      ),
    );
  }
}

class _AcademyPicker extends ConsumerWidget {
  const _AcademyPicker({required this.selectedAcademyId, required this.onChanged});

  final String? selectedAcademyId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final academiesAsync = ref.watch(allAcademiesProvider);
    return AsyncValueView<List<AcademyBrief>>(
      value: academiesAsync,
      onRetry: () => ref.invalidate(allAcademiesProvider),
      data: (context, academies) {
        if (academies.isEmpty) {
          return const Text('No academies yet.', style: TextStyle(fontSize: 12.5));
        }
        return DropdownButtonFormField<String>(
          initialValue: selectedAcademyId,
          decoration: const InputDecoration(labelText: 'Academy', prefixIcon: Icon(Icons.account_balance_outlined)),
          items: academies
              .map((a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(a.isSuspended ? '${a.name} (suspended)' : a.name),
                  ))
              .toList(),
          onChanged: onChanged,
        );
      },
    );
  }
}
