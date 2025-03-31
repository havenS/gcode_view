import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_view/gcode_view.dart';
import 'package:flutter/material.dart';
import 'package:gcode_view/src/gcode_parser.dart';
import 'package:gcode_view/src/models/parsed_gcode.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

void main() {
  group('GcodeViewer Widget Tests', () {
    testWidgets('renders without crashing', (WidgetTester tester) async {
      // Build our widget
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GcodeViewer(gcode: ''))),
      );

      // Verify it renders without errors
      expect(find.byType(GcodeViewer), findsOneWidget);
    });

    testWidgets('handles empty gcode string', (WidgetTester tester) async {
      // Build our widget with empty G-code
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GcodeViewer(gcode: ''))),
      );

      // Verify it renders without errors
      expect(find.byType(GcodeViewer), findsOneWidget);
    });
  });

  group('GcodeParser Tests', () {
    test('parseGcode handles empty string', () {
      final result = parseGcode('');
      expect(result.points, isEmpty);
      expect(result.isTravel, isEmpty);
      expect(result.zValues, isEmpty);
      expect(result.pathSegments, isEmpty);
    });

    test('parseGcode handles simple linear move', () {
      final result = parseGcode('G1 X10 Y20 Z30');
      expect(result.points.length, 1);
      expect(result.points.first.x, 10);
      expect(result.points.first.y, 20);
      expect(result.points.first.z, 30);
      expect(result.isTravel, [false]); // G1 is a cutting move
    });

    test('parseGcode handles travel move', () {
      final result = parseGcode('G0 X10 Y20 Z30');
      expect(result.points.length, 1);
      expect(result.isTravel, [true]); // G0 is a travel move
    });

    test('getNormalizedZLevels works correctly', () {
      final parsedData = ParsedGcode(
        [vector.Vector3(0, 0, 0), vector.Vector3(0, 0, 10)],
        [false, false],
        [0, 10],
      );

      final zLevels = parsedData.getNormalizedZLevels();
      expect(zLevels.length, 2);
      expect(zLevels[0], 0.0);
      expect(zLevels[10], 1.0);
    });
  });

  group('GcodeViewerController Tests', () {
    test('controller can be instantiated', () {
      final controller = GcodeViewerController();
      expect(controller, isNotNull);
    });
  });
}
