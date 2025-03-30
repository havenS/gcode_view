import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      title: 'G-code Viewer - Tester G0',
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

  // Couleurs bien visibles
  final Color cutColor = Colors.blue;
  final Color travelColor = Colors.red.withAlpha(90);
  double pathThickness = 1.0; // Plus épais pour mieux voir
  final controller = GcodeViewerController();

  @override
  void initState() {
    super.initState();
    // Commencer avec le G-code par défaut
    setState(() {
      gcode = """
; Définir une position d'origine pour s'assurer que le premier mouvement est visible
G92 X0 Y0 Z0
; Premier déplacement G0 explicite
G0 X0 Y0 Z0
; Déplacements tests pour visualiser les trajectoires G0
G0 X100 Y0 Z0
G0 X100 Y100 Z0
G0 X0 Y100 Z0
G0 X0 Y0 Z0
; Déplacement vers la position de travail
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
      currentFilePath = "Exemple G-code";
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
              content: Text('Fichier chargé: $currentFilePath'),
              duration: const Duration(seconds: 2),
            ),
          );
        });
      } else {
        // L'utilisateur a annulé la sélection
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Erreur de chargement: $e');

      setState(() {
        isLoading = false;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
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
        title: Text('Test G0 - ${currentFilePath.split('/').last}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              controller.resetView();
            },
            tooltip: 'Réinitialiser la vue',
          ),
          IconButton(
            icon: const Icon(Icons.file_open),
            onPressed: () {
              // Permettre de charger différents fichiers de test
              _showFileSelectionDialog();
            },
            tooltip: 'Ouvrir un fichier',
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
                const Text(
                  'Problème testé:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Vérifier que le déplacement G0 X114.655 Y41.819 est visible en rouge',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      color: travelColor,
                      margin: const EdgeInsets.only(right: 8),
                    ),
                    const Text(
                      'G0 - Déplacements rapides (ROUGE)',
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
                      'G1 - Déplacements de coupe (BLEU)',
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
        title: const Text('Choisir un fichier G-code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Sélectionner un fichier G-code'),
              onTap: () {
                Navigator.pop(context);
                _pickAndLoadGcodeFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_present),
              title: const Text('G-code exemple (pince)'),
              onTap: () {
                Navigator.pop(context);
                // Utiliser le G-code par défaut qui correspond à votre pince
                setState(() {
                  gcode = """
; Définir une position d'origine pour s'assurer que le premier mouvement est visible
G92 X0 Y0 Z0
; Premier déplacement G0 explicite
G0 X0 Y0 Z0
; Déplacements tests pour visualiser les trajectoires G0
G0 X100 Y0 Z0
G0 X100 Y100 Z0
G0 X0 Y100 Z0
G0 X0 Y0 Z0
; Déplacement vers la position de travail
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
                  currentFilePath = "Exemple G-code";
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Test visibilité G0'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  gcode = """
; Test spécifique pour voir tous les G0
G92 X0 Y0 Z0
G0 X0 Y0 Z0
G0 X50 Y0 Z0
G0 X50 Y50 Z0
G0 X0 Y50 Z0
G0 X0 Y0 Z0
; Test avec Z
G0 X0 Y0 Z10
G0 X50 Y0 Z10
G0 X50 Y50 Z10
G0 X0 Y50 Z10
G0 X0 Y0 Z10
G0 X0 Y0 Z0
""";
                  currentFilePath = "Test G0";
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }
}
