import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

void main() async {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Note Translation',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Music Note Translation'),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  Future<void> _openJianpu() async {
  try {
    final uri = Uri.parse("http://localhost:5500/assets/jianpu/index.html");

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint("⚠️ Could not open Jianpu viewer");
    }
  } catch (e) {
    debugPrint("⚠️ Error opening Jianpu: $e");
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(title),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PngToMusicXmlPage(),
                  ),
                );
              },
              child: const Text("Image to MusicXML"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _openJianpu,  // 🚀 Directly open Jianpu
              child: const Text("MusicXML to Jianpu"),
            ),
          ],
        ),
      ),
    );
  }
}

//
// ========== PNG → MusicXML PAGE ==========
//
class PngToMusicXmlPage extends StatefulWidget {
  const PngToMusicXmlPage({super.key});

  @override
  State<PngToMusicXmlPage> createState() => _PngToMusicXmlPageState();
}

class ConvertingPage extends StatelessWidget {
  final String message;

  const ConvertingPage({super.key, this.message = "Converting to MusicXML..."});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(message, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 10),
            const Text(
              "It will take some time to convert, be patient ><",
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _PngToMusicXmlPageState extends State<PngToMusicXmlPage> {
  String? selectedFilePath;
  String? selectedFileName;
  String? debugMessage;

  Future<void> _pickPngFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp'],
      withData: true,
    );

    if (result == null) return;

    final file = result.files.first;
    final name = file.name;

    
    String? filePath = file.path;

    // On some platforms/path providers, `path` can be null (for example when
    // the picker returns bytes only). If so, write bytes to a temporary file
    // and use that path so downstream code can access a file on disk.
    if (filePath == null && file.bytes != null) {
      try {
        final tempFile = File(p.join(Directory.systemTemp.path, name));
        await tempFile.writeAsBytes(file.bytes!);
        filePath = tempFile.path;
      } catch (e) {
        debugPrint('⚠️ Failed to write picked file to temp: $e');
        _showError('Failed to prepare picked file.');
        return;
      }
    }


    final pickMsg = 'Picked file: name=$name, path=$filePath, bytes=${file.bytes?.length}';
    debugPrint(pickMsg);

    setState(() {
      selectedFileName = name;
      selectedFilePath = filePath;
      debugMessage = pickMsg;
    });

    // Notify user visually so they know selection succeeded.
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected: $name')),
      );
    } catch (_) {
      // ignore if scaffold not available
    }
  }

  Future<void> _runHomr(String imagePath) async {
    final ext = p.extension(imagePath).toLowerCase();

    String finalPath = imagePath;

    // ✅ If not PNG → convert first
    if (ext != '.png') {
      try {
        final inputFile = File(imagePath);

        if (!await inputFile.exists()) {
          _showError("Input file not found.");
          return;
        }

        final bytes = await inputFile.readAsBytes();
        final decoded = img.decodeImage(bytes);

        if (decoded == null) {
          _showError("Unsupported or corrupted image.");
          return;
        }

        final pngPath = imagePath.replaceAll(RegExp(r'\.\w+$'), '.png');
        final pngFile = File(pngPath);

        await pngFile.writeAsBytes(img.encodePng(decoded));

        finalPath = pngPath; // ✅ use converted PNG
      } catch (e) {
        debugPrint('⚠️ PNG conversion failed: $e');
        _showError("Failed to convert image to PNG: $e");
        return;
      }
    }

    // Show loading UI
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConvertingPage()),
    );

    final currentDir = Directory.current.path;
    final homrPath = p.join(currentDir, 'assets', 'homr-main', 'homr-main');

    ProcessResult? result;

    try {
      result = await Process.run(
        'poetry',
        ['run', 'homr', finalPath],
        workingDirectory: homrPath,
      );
    } catch (e) {
      Navigator.pop(context);
      debugPrint('⚠️ Failed to run homr: $e');
      _showError('Failed to start conversion process: $e');
      return;
    }

    Navigator.pop(context);

    if (result.exitCode == 0) {
      final match = RegExp(r'(\S+\.musicxml)').firstMatch(
        "${result.stdout}\n${result.stderr}",
      );

      if (match != null) {
        final outputPath = match.group(1)!;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ConversionSuccessPage(outputPath: outputPath),
          ),
        );
      } else {
        _showError("Conversion finished, but output file not detected.");
      }
    } else {
      _showError(
        "Conversion failed with exit code ${result.exitCode}:\n${result.stderr}",
      );
    }
  }

  void _showError(String msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Conversion Failed"),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }
  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Image → MusicXML")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _pickPngFile,
              child: const Text("Select Image File"),
            ),
                const SizedBox(height: 12),
                if (debugMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      debugMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 8),
                if (selectedFileName != null)
              Column(
                children: [
                  Text("Selected: $selectedFileName"),
                  ElevatedButton(
                    onPressed: () {
                      if (selectedFilePath != null) {
                        _runHomr(selectedFilePath!);
                      }
                    },
                    child: const Text("Convert"),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class ConversionSuccessPage extends StatelessWidget {
  final String outputPath;

  const ConversionSuccessPage({super.key, required this.outputPath});

  Future<void> _openFile(String path) async {
    final uri = Uri.file(path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      debugPrint("⚠️ Could not open file: $path");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 80),
              const SizedBox(height: 20),
              const Text(
                "Conversion Successful!",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              InkWell(
                onTap: () => _openFile(outputPath),
                child: Text(
                  "Saved at:\n$outputPath",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("⬅ Back"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}