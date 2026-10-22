// Import flutter_dotenv to securely load environment variables (e.g., API URLs)
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
// Import http package for handling API requests to the AI backend
import 'package:http/http.dart' as http;

class DiagnosisScreen extends StatefulWidget {
  const DiagnosisScreen({super.key});

  @override
  State<DiagnosisScreen> createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen> {
  // --- Core State Variables ---
  File? _image; // Holds the currently selected image file
  final ImagePicker _picker =
      ImagePicker(); // Utility to pick images from camera or gallery
  bool _isLoading = false; // Controls the loading spinner during the API call

  // --- ML Results State (Leaf Analysis) ---
  String? _diseaseStatus;
  double? _diseaseConfidence;
  bool? _isHealthy;
  String? _treatment;

  // --- ML Results State (Fruit Analysis) ---
  int? _totalFruits;
  String? _harvestStatus;

  // Scan Type State ('leaf' for disease detection or 'fruit' for harvest counting)
  String _scanType = 'leaf';

  // Securely fetch the AI backend API URL from the .env file
  // This prevents the URL from being hardcoded and exposed in the source code
  String get apiUrl => dotenv.env['AI_API_URL']!;

  // Clears all previously fetched results before starting a new analysis
  void _clearResults() {
    _diseaseStatus = null;
    _diseaseConfidence = null;
    _isHealthy = null;
    _treatment = null;
    _totalFruits = null;
    _harvestStatus = null;
  }

  // Opens the camera or gallery for the user to select an image
  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _clearResults(); // Reset UI when a new image is selected
      });
    }
  }

  // --- Core AI Integration Logic ---
  // Sends the selected image to the HuggingFace backend and processes the results
  Future<void> _analyzeImage() async {
    if (_image == null) return; // Prevent analysis if no image is selected

    setState(() {
      _isLoading = true; // Show loading indicator
    });

    try {
      // Prepare a multipart POST request to send the image file
      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
      request.fields['scan_type'] =
          _scanType; // Tell backend what we are scanning
      request.files.add(
        await http.MultipartFile.fromPath('file', _image!.path),
      );

      // Send the request with a 60-second timeout to handle backend "cold starts"
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw Exception("Server Timeout: Model is waking up."),
      );

      var response = await http.Response.fromStream(streamedResponse);

      // If the API call is successful (HTTP 200)
      if (response.statusCode == 200) {
        var jsonResult = jsonDecode(response.body);

        if (jsonResult.containsKey('error')) {
          _showErrorDialog(jsonResult['error']);
        } else {
          // Update the UI with the processed AI data
          setState(() {
            if (_scanType == 'leaf') {
              // Parse leaf disease data
              _diseaseStatus = jsonResult['status'];
              String confStr =
                  jsonResult['confidence']?.toString().replaceAll('%', '') ??
                  '0';
              _diseaseConfidence = double.tryParse(confStr) ?? 0.0;

              // Parse boolean status and treatment plan if available
              if (jsonResult.containsKey('is_healthy')) {
                _isHealthy = jsonResult['is_healthy'];
              }
              if (jsonResult.containsKey('treatment')) {
                _treatment = jsonResult['treatment'];
              }
            } else if (_scanType == 'fruit') {
              // Parse fruit counting data
              _totalFruits = jsonResult['total_fruits'];
              _harvestStatus = jsonResult['harvest_status'];
            }
          });
        }
      } else {
        _showErrorDialog("Backend Error: ${response.statusCode}");
      }
    } catch (e) {
      // Provide user-friendly error messages based on the exception type
      _showErrorDialog(
        e.toString().contains('Timeout')
            ? "Server is waking up. Please wait and try again."
            : "Failed to connect. Please check your internet.",
      );
    } finally {
      // Hide loading indicator regardless of success or failure
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Displays a generic error popup for API failures or network issues
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
            // --- Modern Segmented Toggle for Scan Type (Leaf vs Fruit) ---
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
            // Displays the selected image or a placeholder icon
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

            // --- Sleek Camera & Gallery Action Buttons ---
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
            // Disabled if no image is selected or if an API call is currently running
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

            // --- Dynamic Results Display Section ---
            if (_diseaseStatus != null || _totalFruits != null)
              _buildModernResultCard(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // --- Modern UI Component for Displaying AI Results ---
  Widget _buildModernResultCard() {
    // 1. Result layout for Fruit Count & Harvest Status
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
          ],
        ),
      );
    } else {
      // 2. Result layout for Leaf Disease & Treatment Plan
      bool isHealthy = _isHealthy ?? false;
      String formattedStatus =
          _diseaseStatus?.replaceAll('_', ' ') ?? 'Unknown';

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
            // Status Icon Indicator
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
            // Formatted Disease Name
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
            // AI Confidence Score
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

            // --- Integrated Treatment Plan Section ---
            // Only displayed if the plant is sick and a treatment is provided by the API
            if (!isHealthy && _treatment != null && _treatment!.isNotEmpty) ...[
              const SizedBox(height: 25),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade100, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.05),
                      blurRadius: 5,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.medical_information_outlined,
                          color: Colors.red.shade700,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "Treatment Plan",
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _treatment!,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // ------------------------------------------
          ],
        ),
      );
    }
  }
}
