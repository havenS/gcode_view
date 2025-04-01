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
        const MaterialApp(
          home: Scaffold(body: GcodeViewer(gcode: '', isRotationMode: false)),
        ),
      );

      // Verify it renders without errors
      expect(find.byType(GcodeViewer), findsOneWidget);
    });

    testWidgets('handles empty gcode string', (WidgetTester tester) async {
      // Build our widget with empty G-code
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: GcodeViewer(gcode: '', isRotationMode: false)),
        ),
      );

      // Verify it renders without errors
      expect(find.byType(GcodeViewer), findsOneWidget);
    });

    testWidgets('GcodeViewer shows empty state when no G-code is provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: GcodeViewer(gcode: '', isRotationMode: false)),
        ),
      );

      // Verify that the G-code viewer is rendered
      expect(find.byType(GcodeViewer), findsOneWidget);

      // Verify that the widget is in empty state by checking for CustomPaint
      // which should still be rendered but with no paths
      final customPaint = find.descendant(
        of: find.byType(GcodeViewer),
        matching: find.byType(CustomPaint),
      );
      expect(customPaint, findsOneWidget);
    });

    testWidgets('GcodeViewer shows G-code content when provided', (
      WidgetTester tester,
    ) async {
      const testGcode = 'G21\nG90\nG0 X0 Y0\nG1 X10 Y10 F100\nM2';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GcodeViewer(gcode: testGcode, isRotationMode: false),
          ),
        ),
      );

      // Verify that the G-code viewer is rendered
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
      expect(result.points.length, 2); // Initial point + G0 move
      expect(result.points.first.x, 0);
      expect(result.points.first.y, 0);
      expect(result.points.first.z, 0);
      expect(result.points.last.x, 10);
      expect(result.points.last.y, 20);
      expect(result.points.last.z, 30);
      expect(result.isTravel, [true, true]); // Both points are travel moves
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

  group('GcodeViewerConfig Tests', () {
    test('default configuration has expected values', () {
      final config = const GcodeViewerConfig();

      // Test default values
      expect(config.useLevelOfDetail, true);
      expect(config.usePathCaching, true);
      expect(config.maxPointsToRender, 10000);
      expect(config.preserveSmallFeatures, true);
      expect(config.smallFeatureThreshold, 5.0);
      expect(config.zoomSensitivity, 0.5);
      expect(config.arcDetailLevel, 1.0);
    });

    test('custom configuration values are applied correctly', () {
      final config = const GcodeViewerConfig(
        useLevelOfDetail: false,
        usePathCaching: false,
        maxPointsToRender: 5000,
        preserveSmallFeatures: false,
        smallFeatureThreshold: 0.5,
        zoomSensitivity: 2.0,
        arcDetailLevel: 0.2,
      );

      // Test custom values
      expect(config.useLevelOfDetail, false);
      expect(config.usePathCaching, false);
      expect(config.maxPointsToRender, 5000);
      expect(config.preserveSmallFeatures, false);
      expect(config.smallFeatureThreshold, 0.5);
      expect(config.zoomSensitivity, 2.0);
      expect(config.arcDetailLevel, 0.2);
    });

    testWidgets('GcodeViewer applies configuration correctly', (
      WidgetTester tester,
    ) async {
      const customConfig = GcodeViewerConfig(
        useLevelOfDetail: false,
        usePathCaching: false,
        maxPointsToRender: 5000,
        preserveSmallFeatures: false,
        smallFeatureThreshold: 0.5,
        zoomSensitivity: 2.0,
        arcDetailLevel: 0.2,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GcodeViewer(
              gcode: 'G1 X10 Y10',
              isRotationMode: false,
              config: customConfig,
            ),
          ),
        ),
      );

      // Verify that the widget is rendered
      expect(find.byType(GcodeViewer), findsOneWidget);
    });
  });
}
