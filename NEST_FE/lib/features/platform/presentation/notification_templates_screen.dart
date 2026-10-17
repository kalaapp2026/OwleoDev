import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/platform/data/notification_templates_api.dart';
import 'package:nest_fe/features/platform/presentation/console_layout.dart';

/// Super Admin control over what the platform says, to whom, and on which channel, when something
/// happens. Events are fixed by the server; this screen owns the wording and the channels.
class NotificationTemplatesScreen extends StatelessWidget {
  const NotificationTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notification templates'),
          bottom: const TabBar(tabs: [Tab(text: 'Templates'), Tab(text: 'Delivery log')]),
        ),
        body: const TabBarView(children: [_TemplatesTab(), _DeliveryLogTab()]),
      ),
    );
  }
}

class _TemplatesTab extends ConsumerWidget {
  const _TemplatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationCatalogProvider);
    return AsyncValueView<NotificationCatalog>(
      value: async,
      onRetry: () => ref.invalidate(notificationCatalogProvider),
      data: (context, catalog) {
        final erp = catalog.events.where((e) => e.module == 'ERP').toList();
        final social = catalog.events.where((e) => e.module == 'SOCIAL').toList();
        return ConsolePage(
          maxWidth: 900,
          children: [
            _ChannelStatusCard(status: catalog.channels),
            const SizedBox(height: 24),
            if (erp.isNotEmpty) ...[
              const ConsoleSectionTitle('ERP events'),
              ...erp.map((e) => _EventTile(event: e, channels: catalog.channels)),
              const SizedBox(height: 16),
            ],
            if (social.isNotEmpty) ...[
              const ConsoleSectionTitle('Social events'),
              ...social.map((e) => _EventTile(event: e, channels: catalog.channels)),
            ],
          ],
        );
      },
    );
  }
}

class _ChannelStatusCard extends StatelessWidget {
  const _ChannelStatusCard({required this.status});

  final ChannelStatus status;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Channels', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, children: [
              _ChannelPill(icon: Icons.notifications_outlined, label: 'In-app', ready: status.inApp),
              _ChannelPill(icon: Icons.phone_android, label: 'Push', ready: status.push),
              _ChannelPill(icon: Icons.chat_outlined, label: 'WhatsApp', ready: status.whatsapp),
            ]),
            if (!status.push || !status.whatsapp) ...[
              const SizedBox(height: 10),
              Text(
                'Push and WhatsApp send once their credentials are set on the server '
                '(NEST_FCM_CREDENTIALS, NEST_WHATSAPP_TOKEN, NEST_WHATSAPP_PHONE_NUMBER_ID). '
                'Until then you can still configure templates; deliveries are logged as skipped.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChannelPill extends StatelessWidget {
  const _ChannelPill({required this.icon, required this.label, required this.ready});

  final IconData icon;
  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = ready ? scheme.primary : scheme.onSurface.withValues(alpha: 0.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text('$label · ${ready ? 'ready' : 'not set up'}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.channels});

  final NotificationEventConfig event;
  final ChannelStatus channels;

  @override
  Widget build(BuildContext context) {
    final t = event.template;
    final scheme = Theme.of(context).colorScheme;
    final live = t != null && t.enabled;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => NotificationTemplateEditor(event: event)),
        ),
        title: Text(event.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.description),
            const SizedBox(height: 8),
            if (t == null)
              Text('Not configured — nothing is sent',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55), fontSize: 12))
            else
              Wrap(spacing: 6, runSpacing: 4, children: [
                _Badge(live ? 'On' : 'Paused', live ? scheme.primary : scheme.onSurface.withValues(alpha: 0.5)),
                if (t.inAppEnabled) const _Badge('In-app', null),
                if (t.pushEnabled) const _Badge('Push', null),
                if (t.whatsappEnabled) const _Badge('WhatsApp', null),
              ]),
          ]),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

/// Edit one event's template: wording with tappable placeholders, channel switches, live preview.
class NotificationTemplateEditor extends ConsumerStatefulWidget {
  const NotificationTemplateEditor({super.key, required this.event});

  final NotificationEventConfig event;

  @override
  ConsumerState<NotificationTemplateEditor> createState() => _NotificationTemplateEditorState();
}

class _NotificationTemplateEditorState extends ConsumerState<NotificationTemplateEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _waName;
  final _titleFocus = FocusNode();
  final _bodyFocus = FocusNode();

  late bool _inApp;
  late bool _push;
  late bool _whatsapp;
  late bool _enabled;
  bool _busy = false;

  // Sample values so the preview reads like a real message. Anything not listed shows its name.
  static const _sample = {
    'recipientName': 'Asha',
    'batchName': 'Bharatanatyam Beginners',
    'oldDate': '12 Oct',
    'newDate': '14 Oct',
    'newTime': '5:30 PM',
    'date': '12 Oct',
    'time': '5:30 PM',
    'reason': 'Trainer unavailable.',
    'amount': 'Rs 2,500',
    'courseName': 'Bharatanatyam',
    'period': 'October 2026',
    'mode': 'Cash',
  };

  @override
  void initState() {
    super.initState();
    final t = widget.event.template;
    _title = TextEditingController(text: t?.title ?? widget.event.defaultTitle);
    _body = TextEditingController(text: t?.body ?? widget.event.defaultBody);
    _waName = TextEditingController(text: t?.whatsappTemplateName ?? '');
    _inApp = t?.inAppEnabled ?? true;
    _push = t?.pushEnabled ?? false;
    _whatsapp = t?.whatsappEnabled ?? false;
    _enabled = t?.enabled ?? true;
    for (final c in [_title, _body]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _waName.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  String _render(String template) => template.replaceAllMapped(
        RegExp(r'\{\{\s*(\w+)\s*\}\}'),
        (m) => _sample[m.group(1)] ?? m.group(1)!,
      );

  /// Inserts at the caret of whichever field was last focused (body by default).
  void _insertPlaceholder(String name) {
    final useTitle = _titleFocus.hasFocus;
    final controller = useTitle ? _title : _body;
    final token = '{{$name}}';
    final sel = controller.selection;
    final text = controller.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    (useTitle ? _titleFocus : _bodyFocus).requestFocus();
  }

  Future<void> _run(Future<void> Function() action, String successMessage, {bool pop = false}) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(notificationCatalogProvider);
      if (!mounted) return;
      AppNotice.success(context, successMessage);
      if (pop) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(
        () => ref.read(notificationTemplatesApiProvider).save(
              widget.event.eventKey,
              title: _title.text.trim(),
              body: _body.text.trim(),
              inAppEnabled: _inApp,
              pushEnabled: _push,
              whatsappEnabled: _whatsapp,
              whatsappTemplateName: _waName.text.trim().isEmpty ? null : _waName.text.trim(),
              enabled: _enabled,
            ),
        'Template saved.',
        pop: true,
      );

  Future<void> _sendTest() async {
    // The test sends the SAVED template, so make that explicit rather than testing stale text.
    if (!widget.event.isConfigured) {
      AppNotice.error(context, 'Save the template first, then send a test.');
      return;
    }
    await _run(() => ref.read(notificationTemplatesApiProvider).sendTest(widget.event.eventKey),
        'Test sent to you. Check the Delivery log for each channel.');
    ref.invalidate(deliveryLogProvider);
  }

  Future<void> _remove() async {
    final ok = await AppNotice.confirm(
      context,
      title: 'Remove template?',
      message: 'This event goes silent until a template is configured again.',
      confirmLabel: 'Remove',
    );
    if (!ok) return;
    await _run(() => ref.read(notificationTemplatesApiProvider).remove(widget.event.eventKey),
        'Template removed.', pop: true);
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final channels = ref.watch(notificationCatalogProvider).valueOrNull?.channels;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(event.label)),
      body: ConsolePage(
        maxWidth: 760,
        children: [
          Text(event.description, style: theme.textTheme.bodySmall),
          const SizedBox(height: 20),
          const ConsoleSectionTitle('Message'),
          TextField(
            controller: _title,
            focusNode: _titleFocus,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            focusNode: _bodyFocus,
            maxLength: 1000,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder()),
          ),
          Text('Tap a placeholder to insert it where your cursor is:', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final p in event.placeholders)
                ActionChip(label: Text('{{$p}}'), onPressed: _busy ? null : () => _insertPlaceholder(p)),
            ],
          ),
          const SizedBox(height: 20),
          const ConsoleSectionTitle('Preview'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_render(_title.text), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_render(_body.text)),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          const ConsoleSectionTitle('Send on'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              SwitchListTile(
                title: const Text('In-app'),
                subtitle: const Text('Shows in the recipient\'s notifications bell'),
                value: _inApp,
                onChanged: _busy ? null : (v) => setState(() => _inApp = v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Push notification'),
                subtitle: Text(channels?.push == false
                    ? 'Server has no Firebase credentials yet - will be skipped'
                    : 'To the recipient\'s signed-in phones'),
                value: _push,
                onChanged: _busy ? null : (v) => setState(() => _push = v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('WhatsApp'),
                subtitle: Text(channels?.whatsapp == false
                    ? 'Server has no WhatsApp credentials yet - will be skipped'
                    : 'Needs a template approved in Meta Business Manager'),
                value: _whatsapp,
                onChanged: _busy ? null : (v) => setState(() => _whatsapp = v),
              ),
              if (_whatsapp)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(
                      controller: _waName,
                      decoration: const InputDecoration(
                        labelText: 'WhatsApp template name',
                        hintText: 'e.g. class_cancelled',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Meta variables {{1}}, {{2}}… are filled with the placeholders in the order '
                      'they first appear in the message above.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Template active'),
              subtitle: const Text('Pause to stop sending without losing the wording'),
              value: _enabled,
              onChanged: _busy ? null : (v) => setState(() => _enabled = v),
            ),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save template'),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: _busy ? null : _sendTest, child: const Text('Send test to me')),
          ]),
          if (event.isConfigured) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : _remove,
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                child: const Text('Remove template'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeliveryLogTab extends ConsumerWidget {
  const _DeliveryLogTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deliveryLogProvider);
    return AsyncValueView<List<DeliveryLogEntry>>(
      value: async,
      onRetry: () => ref.invalidate(deliveryLogProvider),
      data: (context, rows) => RefreshIndicator(
        onRefresh: () async => ref.refresh(deliveryLogProvider.future),
        child: rows.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('Nothing sent yet.')),
              ])
            : ConsolePage(
                maxWidth: 900,
                children: [for (final r in rows) _DeliveryRow(entry: r)],
              ),
      ),
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.entry});

  final DeliveryLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color tone;
    switch (entry.status) {
      case 'SENT':
        tone = scheme.primary;
      case 'FAILED':
        tone = scheme.error;
      default:
        tone = scheme.onSurface.withValues(alpha: 0.55);
    }
    final t = entry.createdAt;
    final when = '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text('${entry.eventKey} → ${entry.recipientName}'),
        subtitle: Text([entry.channel, if (entry.detail != null) entry.detail!, when].join(' · ')),
        trailing: _Badge(entry.status, tone),
      ),
    );
  }
}
