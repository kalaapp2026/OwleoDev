import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/theme/app_theme.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/file_previews.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/permission_badge.dart';

StudyMaterial _doc({String permission = 'DOWNLOADABLE'}) => StudyMaterial.fromJson({
      'id': 'm1',
      'batchId': 'b1',
      'title': 'Chord Chart',
      'url': '/files/chord.pdf',
      'fileName': 'chord-chart.pdf',
      'fileType': 'NOTES',
      'sizeBytes': 1024,
      'permission': permission,
      'uploadedAt': '2026-08-25T10:30:00Z',
    });

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: SizedBox(width: 390, height: 700, child: child)),
    );

void main() {
  group('DocumentPreview markup', () {
    testWidgets('a pen stroke is kept, undone and cleared', (tester) async {
      final controller = MarkupController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(DocumentPreview(
        material: _doc(),
        controller: controller,
        fullscreen: false,
      )));

      expect(controller.hasMarks, isFalse);

      await tester.tap(find.text('Pen'));
      await tester.pump();
      expect(controller.tool, MarkupTool.pen);

      final page = find.text('chord-chart.pdf');
      await tester.drag(page, const Offset(60, 40));
      await tester.pump();
      expect(controller.hasMarks, isTrue);

      controller.undo();
      expect(controller.hasMarks, isFalse);

      await tester.drag(page, const Offset(40, 20));
      await tester.pump();
      expect(controller.hasMarks, isTrue);
      controller.clear();
      expect(controller.hasMarks, isFalse);
    });

    testWidgets('no tool means a drag draws nothing', (tester) async {
      final controller = MarkupController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(DocumentPreview(
        material: _doc(),
        controller: controller,
        fullscreen: false,
      )));

      await tester.drag(find.text('chord-chart.pdf'), const Offset(60, 40));
      await tester.pump();
      expect(controller.hasMarks, isFalse);
    });

    testWidgets('switching tool resets the colour to that tool\'s first swatch', (tester) async {
      final controller = MarkupController();
      addTearDown(controller.dispose);

      controller.toggleTool(MarkupTool.pen);
      controller.setColor(2);
      controller.toggleTool(MarkupTool.highlighter);
      expect(controller.colorIndex, 0);

      // Tapping the active tool again puts it down.
      controller.toggleTool(MarkupTool.highlighter);
      expect(controller.tool, isNull);
    });

    testWidgets('hiding the toolbar leaves a way to bring it back', (tester) async {
      final controller = MarkupController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(DocumentPreview(
        material: _doc(),
        controller: controller,
        fullscreen: false,
      )));

      expect(find.text('Pen'), findsOneWidget);
      controller.setToolbarVisible(false);
      await tester.pump();
      expect(find.text('Pen'), findsNothing);
      expect(find.text('Show tools'), findsOneWidget);
    });

    testWidgets('fullscreen moves the tools to a rail and can collapse it', (tester) async {
      final controller = MarkupController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(DocumentPreview(
        material: _doc(),
        controller: controller,
        fullscreen: true,
      )));

      // Icon-only rail: no "Pen" caption.
      expect(find.text('Pen'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.close_fullscreen), findsOneWidget);

      controller.setToolbarVisible(false);
      await tester.pump();
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.keyboard_double_arrow_left), findsOneWidget);
    });

    testWidgets('a view-only document says it stays in the app', (tester) async {
      final controller = MarkupController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(DocumentPreview(
        material: _doc(permission: 'VIEW_ONLY'),
        controller: controller,
        fullscreen: false,
      )));

      expect(find.textContaining('view-only'), findsOneWidget);
    });
  });

  testWidgets('PermissionBadge names the permission', (tester) async {
    await tester.pumpWidget(_host(
      const Column(children: [
        PermissionBadge(permission: StudyMaterialPermission.downloadable),
        PermissionBadge(permission: StudyMaterialPermission.viewOnly),
      ]),
    ));
    expect(find.text('Downloadable'), findsOneWidget);
    expect(find.text('View only'), findsOneWidget);
  });
}
