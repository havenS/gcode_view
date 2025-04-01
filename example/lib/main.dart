import 'dart:io';
import 'package:flutter/foundation.dart';
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
      title: 'G-code Viewer',
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
  bool showGrid = true;
  bool _isRotationMode = false;

  // Vibrant colors for visibility
  final Color cutColor = Colors.blue;
  final Color travelColor = Colors.red.withAlpha(90);
  double pathThickness = 1.0; // Thicker for better visibility
  final controller = GcodeViewerController();

  // Performance configuration
  final viewerConfig = GcodeViewerConfig.highDetail();

  @override
  void initState() {
    super.initState();
    // Start with empty state until a file is loaded
    setState(() {
      gcode = "";
      currentFilePath = "No file loaded";
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
      if (kDebugMode) {
        print('Loading error: $e');
      }

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
        title: Text('GCode Viewer - $currentFilePath'),
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
            icon: const Icon(Icons.grid_on),
            onPressed: () {
              setState(() {
                showGrid = !showGrid;
              });
            },
            tooltip: 'Toggle grid',
          ),
          IconButton(
            icon: const Icon(Icons.file_open),
            onPressed: _pickAndLoadGcodeFile,
            tooltip: 'Open file',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : gcode.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.upload_file,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            const Text(
                                'No file loaded. Tap the file icon to load a G-code file.'),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.file_open),
                              label: const Text('Load G-code File'),
                              onPressed: _pickAndLoadGcodeFile,
                            ),
                          ],
                        ),
                      )
                    : GcodeViewer(
                        gcode: gcode,
                        cutColor: cutColor,
                        travelColor: travelColor,
                        pathThickness: pathThickness,
                        showGrid: showGrid,
                        controller: controller,
                        config: viewerConfig,
                        isRotationMode: _isRotationMode,
                      ),
          ),
          // Info bar with gesture instructions
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            color: Colors.grey.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _isRotationMode
                  ? [
                      const Icon(Icons.swipe_left, size: 16),
                      const SizedBox(width: 4),
                      const Text('Drag left/right to rotate',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 16),
                      const Icon(Icons.swipe_up, size: 16),
                      const SizedBox(width: 4),
                      const Text('Drag up/down to tilt',
                          style: TextStyle(fontSize: 12)),
                    ]
                  : [
                      const Icon(Icons.pan_tool, size: 16),
                      const SizedBox(width: 4),
                      const Text('Drag to pan', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 16),
                      const Icon(Icons.pinch, size: 16),
                      const SizedBox(width: 4),
                      const Text('Pinch to zoom',
                          style: TextStyle(fontSize: 12)),
                    ],
            ),
          ),
          // Combined mode selector and color legend
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Color legend
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
                    const SizedBox(width: 16),
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
                // Mode selector
                Row(
                  children: [
                    const Text('Move Mode'),
                    Switch(
                      value: _isRotationMode,
                      onChanged: (value) {
                        setState(() {
                          _isRotationMode = value;
                        });
                      },
                    ),
                    const Text('Rotate Mode'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
