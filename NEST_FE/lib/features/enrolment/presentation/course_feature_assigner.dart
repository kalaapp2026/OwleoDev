import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';

/// The delegable feature checklist offered when assigning a trainer to courses.
const trainerFeatureKeys = [
  FeatureKeys.attendance,
  FeatureKeys.batchScheduling,
  FeatureKeys.reschedule,
  FeatureKeys.feesEntry,
  FeatureKeys.syllabusEdit,
  FeatureKeys.eventManagement,
  FeatureKeys.studentRegistration,
  FeatureKeys.batchCreation,
];

/// Reusable per-course feature picker shared by trainer create and trainer edit: pick courses,
/// then either one shared feature set ("same for all courses") or a separate set per course.
/// Emits the current {courseId -> features} map through [onChanged] on every change.
class CourseFeatureAssigner extends ConsumerStatefulWidget {
  const CourseFeatureAssigner({super.key, required this.initial, required this.onChanged});

  /// Existing assignment to seed from (empty for a brand-new trainer).
  final Map<String, Set<String>> initial;
  final ValueChanged<Map<String, Set<String>>> onChanged;

  @override
  ConsumerState<CourseFeatureAssigner> createState() => _CourseFeatureAssignerState();
}

class _CourseFeatureAssignerState extends ConsumerState<CourseFeatureAssigner> {
  final _selectedCourseIds = <String>{};
  bool _sameForAll = true;
  final _sharedFeatures = <String>{};
  final _perCourseFeatures = <String, Set<String>>{};

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _selectedCourseIds.addAll(initial.keys);
    initial.forEach((courseId, features) => _perCourseFeatures[courseId] = {...features});

    // Collapse to "same for all" when every course shares an identical set (incl. the empty case);
    // otherwise start in per-course mode so no distinction is lost.
    final sets = initial.values.toList();
    final allEqual = sets.isEmpty || sets.every((s) => _setEquals(s, sets.first));
    _sameForAll = allEqual;
    if (allEqual && sets.isNotEmpty) _sharedFeatures.addAll(sets.first);

    // Seed the parent with the initial map once, after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emit();
    });
  }

  bool _setEquals(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  Map<String, Set<String>> _build() => {
        for (final id in _selectedCourseIds) id: _sameForAll ? {..._sharedFeatures} : {...?_perCourseFeatures[id]},
      };

  void _emit() => widget.onChanged(_build());

  Widget _featureWrap(Set<String> selected, void Function(String feature, bool on) onToggle) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: trainerFeatureKeys.map((f) {
        return FilterChip(
          label: Text(f.replaceAll('_', ' ')),
          selected: selected.contains(f),
          onSelected: (v) => setState(() {
            onToggle(f, v);
            _emit();
          }),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(activeCoursesProvider);
    return AsyncValueView<List<Course>>(
      value: coursesAsync,
      onRetry: () => ref.invalidate(activeCoursesProvider),
      data: (context, courses) {
        String nameFor(String id) {
          for (final c in courses) {
            if (c.id == id) return c.name;
          }
          return 'Course';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Courses to assign', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (courses.isEmpty)
              const Text('No active courses in this academy yet.', style: TextStyle(fontSize: 12.5))
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: courses.map((c) {
                  return FilterChip(
                    label: Text(c.name),
                    selected: _selectedCourseIds.contains(c.id),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selectedCourseIds.add(c.id);
                      } else {
                        _selectedCourseIds.remove(c.id);
                        _perCourseFeatures.remove(c.id);
                      }
                      _emit();
                    }),
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
            Text('Features to grant', style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Same features for all courses'),
              subtitle: Text(_sameForAll
                  ? 'One feature set applied to every selected course.'
                  : 'Set features separately for each course.'),
              value: _sameForAll,
              onChanged: (v) => setState(() {
                _sameForAll = v;
                _emit();
              }),
            ),
            const SizedBox(height: 8),
            if (_sameForAll)
              _featureWrap(_sharedFeatures, (f, on) => on ? _sharedFeatures.add(f) : _sharedFeatures.remove(f))
            else if (_selectedCourseIds.isEmpty)
              Text('Pick a course above first.', style: Theme.of(context).textTheme.bodySmall)
            else
              ..._selectedCourseIds.map((courseId) {
                final selected = _perCourseFeatures[courseId] ?? const <String>{};
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nameFor(courseId),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      _featureWrap(selected, (f, on) {
                        final set = _perCourseFeatures.putIfAbsent(courseId, () => <String>{});
                        on ? set.add(f) : set.remove(f);
                      }),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
