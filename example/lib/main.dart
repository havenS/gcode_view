import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gcode_view/gcode_view.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'G-code Viewer - G0 Tester',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String gcode = "";
  bool isLoading = true;
  String currentFilePath = "";

  // Vibrant colors for visibility
  final Color cutColor = Colors.blue;
  final Color travelColor = Colors.red.withAlpha(90);
  double pathThickness = 1.0; // Thicker for better visibility
  final controller = GcodeViewerController();

  @override
  void initState() {
    super.initState();
    // Start with default G-code
    setState(() {
      gcode = """
; Set origin position to ensure first movement is visible
G92 X0 Y0 Z0
; First explicit G0 movement
G0 X0 Y0 Z0
; Test movements to visualize G0 trajectories
G0 X100 Y0 Z0
G0 X100 Y100 Z0
G0 X0 Y100 Z0
G0 X0 Y0 Z0
; Move to working position
G0 X114.655 Y41.819 Z15
G0 Z5
G1 Z-15 F500
G1 X120 Y40 F800
G1 X130 Y50
G1 X130 Y70
G1 X120 Y80
G1 X80 Y80
G1 X70 Y70
G1 X70 Y50
G1 X80 Y40
G1 X114.655 Y41.819
G0 Z15
G0 X0 Y0 Z15
""";
      currentFilePath = "Sample G-code";
      isLoading = false;
    });
  }

  Future<void> _pickAndLoadGcodeFile() async {
    setState(() {
      isLoading = true;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['nc', 'gcode', 'g', 'txt'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        String filePath = result.files.single.path!;
        final file = File(filePath);
        final content = await file.readAsString();

        setState(() {
          gcode = content;
          currentFilePath = file.path.split('/').last;
          isLoading = false;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File loaded: $currentFilePath'),
              duration: const Duration(seconds: 2),
            ),
          );
        });
      } else {
        // User cancelled selection
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Loading error: $e');

      setState(() {
        isLoading = false;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('G0 Test - ${currentFilePath.split('/').last}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              controller.resetView();
            },
            tooltip: 'Reset view',
          ),
          IconButton(
            icon: const Icon(Icons.file_open),
            onPressed: () {
              // Allow loading different test files
              _showFileSelectionDialog();
            },
            tooltip: 'Open file',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : GcodeViewer(
                    gcode: gcode,
                    cutColor: cutColor,
                    travelColor: travelColor,
                    pathThickness: pathThickness,
                    showGrid: true,
                    controller: controller,
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      color: travelColor,
                      margin: const EdgeInsets.only(right: 8),
                    ),
                    const Text(
                      'G0 - Rapid movements (RED)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      color: cutColor,
                      margin: const EdgeInsets.only(right: 8),
                    ),
                    const Text(
                      'G1 - Working movements (BLUE)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFileSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose a G-code file'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Select G-code file'),
              onTap: () {
                Navigator.pop(context);
                _pickAndLoadGcodeFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_present),
              title: const Text('Sample G-code (gripper)'),
              onTap: () {
                Navigator.pop(context);
                // Use default G-code that matches your gripper
                setState(() {
                  gcode = """
; Set origin position to ensure first movement is visible
G92 X0 Y0 Z0
; First explicit G0 movement
G0 X0 Y0 Z0
; Test movements to visualize G0 trajectories
G0 X100 Y0 Z0
G0 X100 Y100 Z0
G0 X0 Y100 Z0
G0 X0 Y0 Z0
; Move to working position
G0 X114.655 Y41.819 Z15
G0 Z5
G1 Z-15 F500
G1 X120 Y40 F800
G1 X130 Y50
G1 X130 Y70
G1 X120 Y80
G1 X80 Y80
G1 X70 Y70
G1 X70 Y50
G1 X80 Y40
G1 X114.655 Y41.819
G0 Z15
G0 X0 Y0 Z15
""";
                  currentFilePath = "Sample G-code";
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('G0 visibility test'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  gcode = """
; Specific test to see all G0
G92 X0 Y0 Z0
G0 X0 Y0 Z0
G0 X50 Y0 Z0
G0 X50 Y50 Z0
G0 X0 Y50 Z0
G0 X0 Y0 Z0
; Test with Z
G0 X0 Y0 Z10
G0 X50 Y0 Z10
G0 X50 Y50 Z10
G0 X0 Y50 Z10
G0 X0 Y0 Z10
G0 X0 Y0 Z0
""";
                  currentFilePath = "G0 Test";
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
