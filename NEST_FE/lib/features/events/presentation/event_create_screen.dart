import 'package:nest_fe/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart';

/// PRD 3.12: a Public event auto-publishes a matching Social post in the same backend call -
/// verified live. In-house never leaves the academy's own notification list.
class EventCreateScreen extends ConsumerStatefulWidget {
  const EventCreateScreen({super.key});

  @override
  ConsumerState<EventCreateScreen> createState() => _EventCreateScreenState();
}

class _EventCreateScreenState extends ConsumerState<EventCreateScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _dateController = TextEditingController();
  final _locationController = TextEditingController();
  String _type = 'PROGRAMME';
  String _visibility = 'PUBLIC';
  bool _isSaving = false;

  Future<void> _submit() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(eventsApiProvider).create(
            type: _type,
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            eventDate: _dateController.text.trim(),
            location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
            visibility: _visibility,
          );
      if (mounted) {
        AppNotice.success(context, AppLocalizations.of(context).evtCreated);
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).evtNewEvent)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'PROGRAMME', label: Text(AppLocalizations.of(context).evtProgramme)),
              ButtonSegment(value: 'LOOKING_FOR_ARTIST', label: Text(AppLocalizations.of(context).evtLookingForArtist)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 14),
          TextField(controller: _titleController, decoration: InputDecoration(labelText: AppLocalizations.of(context).fieldTitle)),
          const SizedBox(height: 12),
          TextField(controller: _descriptionController, maxLines: 3, decoration: InputDecoration(labelText: AppLocalizations.of(context).fieldDescription)),
          const SizedBox(height: 12),
          TextField(controller: _dateController, decoration: InputDecoration(labelText: AppLocalizations.of(context).evtDateTimeHint)),
          const SizedBox(height: 12),
          TextField(controller: _locationController, decoration: InputDecoration(labelText: AppLocalizations.of(context).fieldLocation)),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(AppLocalizations.of(context).evtVisibility),
              const SizedBox(width: 12),
              ChoiceChip(
                label: Text(AppLocalizations.of(context).evtInHouse),
                selected: _visibility == 'INHOUSE',
                onSelected: (_) => setState(() => _visibility = 'INHOUSE'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(AppLocalizations.of(context).evtPublic),
                selected: _visibility == 'PUBLIC',
                onSelected: (_) => setState(() => _visibility = 'PUBLIC'),
              ),
            ],
          ),
          if (_visibility == 'PUBLIC')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'This also auto-publishes a Social post from your academy\'s profile.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(AppLocalizations.of(context).evtCreateEvent),
          ),
        ],
      ),
    );
  }
}
