import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class DiagnosisScreen extends StatefulWidget {
  const DiagnosisScreen({super.key});

  @override
  State<DiagnosisScreen> createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen> {
  File? _image;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  // ML Results State
  String? _diseaseStatus;
  double? _diseaseConfidence;
  int? _totalFruits;
  String? _harvestStatus;

  // Scan Type State ('leaf' or 'fruit')
  String _scanType = 'leaf';

  final String apiUrl = "https://dasunz-tomato-disease-api.hf.space/analyze";

  void _clearResults() {
    _diseaseStatus = null;
    _diseaseConfidence = null;
    _totalFruits = null;
    _harvestStatus = null;
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _clearResults();
      });
    }
  }

  Future<void> _analyzeImage() async {
    if (_image == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
      request.fields['scan_type'] = _scanType;
      request.files.add(
        await http.MultipartFile.fromPath('file', _image!.path),
      );

      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw Exception("Server Timeout: Model is waking up."),
      );

      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var jsonResult = jsonDecode(response.body);

        if (jsonResult.containsKey('error')) {
          _showErrorDialog(jsonResult['error']);
        } else {
          setState(() {
            if (_scanType == 'leaf') {
              _diseaseStatus = jsonResult['status'];
              String confStr =
                  jsonResult['confidence']?.toString().replaceAll('%', '') ??
                  '0';
              _diseaseConfidence = double.tryParse(confStr) ?? 0.0;
            } else if (_scanType == 'fruit') {
              _totalFruits = jsonResult['total_fruits'];
              _harvestStatus = jsonResult['harvest_status'];
            }
          });
        }
      } else {
        _showErrorDialog("Backend Error: ${response.statusCode}");
      }
    } catch (e) {
      _showErrorDialog(
        e.toString().contains('Timeout')
            ? "Server is waking up. Please wait and try again."
            : "Failed to connect. Please check your internet.",
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          "Notice",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              "OK",
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Smart Brain AI',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Modern Segmented Toggle (Apple iOS Style) ---
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _scanType = 'leaf';
                        _clearResults();
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _scanType == 'leaf'
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: _scanType == 'leaf'
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Text(
                            '🌿 Leaf Disease',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _scanType == 'leaf'
                                  ? Colors.green.shade800
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _scanType = 'fruit';
                        _clearResults();
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _scanType == 'fruit'
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: _scanType == 'fruit'
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Text(
                            '🍅 Fruit Health',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _scanType == 'fruit'
                                  ? Colors.orange.shade800
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // --- Modern Image Upload Container ---
            Container(
              height: 280,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: _scanType == 'leaf'
                        ? Colors.green.withOpacity(0.08)
                        : Colors.orange.withOpacity(0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(
                  color: _scanType == 'leaf'
                      ? Colors.green.shade100
                      : Colors.orange.shade100,
                  width: 2,
                ),
              ),
              child: _image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.file(
                        _image!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _scanType == 'leaf'
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _scanType == 'leaf'
                                ? Icons.energy_savings_leaf
                                : Icons.eco,
                            size: 50,
                            color: _scanType == 'leaf'
                                ? Colors.green.shade400
                                : Colors.orange.shade400,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          'Upload a ${_scanType == 'leaf' ? 'Leaf' : 'Fruit'} Photo',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 25),

            // --- Sleek Camera & Gallery Buttons ---
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.green.shade700,
                    ),
                    label: Text(
                      'Camera',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: Colors.green.shade200, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: Icon(
                      Icons.photo_library_outlined,
                      color: Colors.green.shade700,
                    ),
                    label: Text(
                      'Gallery',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: Colors.green.shade200, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 35),

            // --- Modern Gradient Analyze Button ---
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _scanType == 'leaf'
                        ? Colors.green.withOpacity(0.3)
                        : Colors.orange.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
                gradient: LinearGradient(
                  colors: _scanType == 'leaf'
                      ? [Colors.green.shade500, Colors.green.shade800]
                      : [Colors.orange.shade400, Colors.deepOrange.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: ElevatedButton(
                onPressed: _image != null && !_isLoading ? _analyzeImage : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                    : const Text(
                        'Start AI Analysis',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 30),

            // --- Results Section ---
            if (_diseaseStatus != null || _totalFruits != null)
              _buildModernResultCard(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // --- Modern UI Component for Results ---
  Widget _buildModernResultCard() {
    if (_scanType == 'fruit') {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.orange.shade200, width: 2),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                Icons.check_circle_rounded,
                color: Colors.orange.shade600,
                size: 35,
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              "Tomatoes Detected",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              "$_totalFruits",
              style: TextStyle(
                fontSize: 48,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w900,
              ),
            ),

            if (_harvestStatus != null) ...[
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _harvestStatus!,
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],

            // ----------------------------------------------------
          ],
        ),
      );
    } else {
      String formattedStatus =
          _diseaseStatus?.replaceAll('_', ' ').replaceAll('___', ' ') ??
          'Unknown';
      bool isHealthy = formattedStatus.toLowerCase().contains('healthy');

      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isHealthy ? Colors.green.shade50 : Colors.red.shade50,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isHealthy ? Colors.green.shade200 : Colors.red.shade200,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isHealthy ? Colors.green : Colors.red).withOpacity(
                      0.1,
                    ),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                isHealthy
                    ? Icons.health_and_safety_rounded
                    : Icons.warning_rounded,
                color: isHealthy ? Colors.green.shade600 : Colors.red.shade600,
                size: 35,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              isHealthy ? "Plant is Healthy" : "Disease Detected",
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              formattedStatus,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                color: isHealthy ? Colors.green.shade800 : Colors.red.shade800,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "Accuracy: ${_diseaseConfidence?.toStringAsFixed(1)}%",
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}
