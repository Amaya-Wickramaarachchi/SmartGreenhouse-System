import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

const String mlEndpoint =
    'https://tomato-farm-app-dasun.azurewebsites.net/analyze';

class PredictionResult {
  final String diseaseName;
  final double confidenceScore;
  final bool isHealthy;
  final int totalFruits;
  final int ripeFruits;
  final int unripeFruits;
  final String recommendation;

  PredictionResult({
    required this.diseaseName,
    required this.confidenceScore,
    required this.isHealthy,
    required this.totalFruits,
    required this.ripeFruits,
    required this.unripeFruits,
    required this.recommendation,
  });

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    final health = json['plant_health'] ?? {};
    final harvest = json['harvest_info'] ?? {};

    String confidenceStr = (health['confidence'] as String? ?? '0%')
        .replaceAll('%', '')
        .trim();
    double confidence = (double.tryParse(confidenceStr) ?? 0.0);

    final ripe = harvest['ripe_fruits'] ?? 0;
    final unripe = harvest['unripe_fruits'] ?? 0;

    String recommendationText = (health['is_healthy'] == false)
        ? 'Disease: ${health['status']}, Action: Consult a specialist.'
        : (harvest['ready_to_harvest'] == true)
        ? 'Ready for harvest. Ripe fruits: $ripe'
        : 'Plant is healthy. Total fruits: ${harvest['total_fruits'] ?? 0}';

    return PredictionResult(
      diseaseName: health['status'] ?? 'N/A',
      confidenceScore: confidence,
      isHealthy: health['is_healthy'] ?? true,
      totalFruits: harvest['total_fruits'] ?? 0,
      ripeFruits: ripe,
      unripeFruits: unripe,
      recommendation: recommendationText,
    );
  }
}

class DiagnosisScreen extends StatefulWidget {
  const DiagnosisScreen({super.key});

  @override
  State<DiagnosisScreen> createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen> {
  XFile? _imageFile;
  PredictionResult? _lastResult;
  bool _isAnalyzing = false;
  final ImagePicker _picker = ImagePicker();

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _imageFile = pickedFile;
        _lastResult = null;
      });
    }
  }

  Future<void> _analyzePlant() async {
    if (_imageFile == null) {
      _showSnackBar('Please select an image first.', isError: true);
      return;
    }

    setState(() {
      _isAnalyzing = true;
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse(mlEndpoint));
      final bytes = await _imageFile!.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: _imageFile!.name,
          contentType: MediaType('image', _imageFile!.name.split('.').last),
        ),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var jsonResponse = json.decode(response.body);
        setState(() {
          _lastResult = PredictionResult.fromJson(jsonResponse);
        });
      } else {
        _showSnackBar(
          'ML API Failed (Code ${response.statusCode}).',
          isError: true,
        );
      }
    } catch (e) {
      _showSnackBar('Network error: $e', isError: true);
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartGreen AI'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Image display
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade200,
                image: _imageFile != null
                    ? DecorationImage(
                        image: FileImage(File(_imageFile!.path)),
                        fit: BoxFit.cover,
                      )
                    : const DecorationImage(
                        image: AssetImage('assets/placeholder.png'),
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(height: 15),
            // Camera & Gallery buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  label: const Text(
                    'Camera',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo, color: Colors.white),
                  label: const Text(
                    'Gallery',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Analyze Plant button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isAnalyzing ? null : _analyzePlant,
                child: _isAnalyzing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'ANALYZE PLANT',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
            ),
            const SizedBox(height: 30),
            // Analysis Results Card
            if (_lastResult != null)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.medical_services, color: Colors.red),
                          SizedBox(width: 8),
                          Text(
                            'Plant Health',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Text(
                        'Status: ${_lastResult!.diseaseName}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Confidence: ${_lastResult!.confidenceScore.toStringAsFixed(1)}%',
                      ),
                      const SizedBox(height: 5),
                      Text('Total Fruits: ${_lastResult!.totalFruits}'),
                      Text('Ripe Fruits: ${_lastResult!.ripeFruits}'),
                      const SizedBox(height: 5),
                      Text('Recommendation: ${_lastResult!.recommendation}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
