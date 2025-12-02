import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';

class AdminConfigurationScreen extends StatefulWidget {
  const AdminConfigurationScreen({super.key});

  @override
  State<AdminConfigurationScreen> createState() =>
      _AdminConfigurationScreenState();
}

class _AdminConfigurationScreenState extends State<AdminConfigurationScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSaving = false;

  // --- Text Controllers for Configuration Inputs ---
  final TextEditingController _plantCountController = TextEditingController(
    text: '50',
  ); // Example default
  final TextEditingController _tempController = TextEditingController(
    text: '30',
  );
  final TextEditingController _humidityController = TextEditingController(
    text: '75',
  );
  final TextEditingController _soilMoistureController = TextEditingController(
    text: '60',
  );
  final TextEditingController _lightIntensityController = TextEditingController(
    text: '10000',
  );
  final TextEditingController _fertilityFreqController = TextEditingController(
    text: '7',
  );
  final TextEditingController _waterAmountController = TextEditingController(
    text: '200',
  );
  final TextEditingController _cameraIntervalController = TextEditingController(
    text: '4',
  );

  @override
  void dispose() {
    _plantCountController.dispose();
    _tempController.dispose();
    _humidityController.dispose();
    _soilMoistureController.dispose();
    _lightIntensityController.dispose();
    _fertilityFreqController.dispose();
    _waterAmountController.dispose();
    _cameraIntervalController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // --- Function to Save Configuration to Firestore ---
  Future<void> _saveConfiguration() async {
    setState(() {
      _isSaving = true;
    });

    // Validate inputs
    if (_tempController.text.isEmpty || _waterAmountController.text.isEmpty) {
      _showSnackBar('Please fill in all mandatory fields.', isError: true);
      setState(() {
        _isSaving = false;
      });
      return;
    }

    // Prepare data object to save to the 'Configuration' collection
    final Map<String, dynamic> configData = {
      // Configuration details
      'timestamp': FieldValue.serverTimestamp(),
      'targetTemp': double.tryParse(_tempController.text),
      'targetHumid': double.tryParse(_humidityController.text),
      'targetMoist': double.tryParse(_soilMoistureController.text),
      'targetLight': double.tryParse(_lightIntensityController.text),

      // Automation Schedules
      'fertilityFreqDays': int.tryParse(_fertilityFreqController.text),
      'irrigationAmountMl': double.tryParse(_waterAmountController.text),
      'cameraIntervalHours': int.tryParse(_cameraIntervalController.text),

      // Asset Management
      'numberOfPlants': int.tryParse(_plantCountController.text),
    };

    try {
      // Direct write to the 'Configuration' collection (requires Admin privilege via Security Rules)
      await _firestore
          .collection('configuration')
          .doc('settings')
          .set(
            configData,
            SetOptions(
              merge: true,
            ), // Merge to update fields without deleting others
          );
      _showSnackBar(
        'Configuration saved successfully and synced to Edge Device!',
        isError: false,
      );

      // TODO: Implement logic to update Plant IDs in the database based on _plantCountController
    } catch (e) {
      _showSnackBar(
        'Error saving configuration. Check Admin privileges and connection.',
        isError: true,
      );
      print(e);
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  // Helper widget for a single configuration input row
  Widget _buildConfigRow({
    required String label,
    required TextEditingController controller,
    required String unit,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: const TextStyle(fontSize: 16)),
          ),
          Expanded(
            flex: 2,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                suffixText: unit,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Admin Configuration',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 30),

            // --- 1. Asset Setup ---
            _buildSectionTitle('Asset Setup'),
            _buildConfigRow(
              label: 'Number of Plants:',
              controller: _plantCountController,
              unit: 'plants',
            ),
            const SizedBox(height: 20),

            // --- 2. Target Conditions ---
            _buildSectionTitle('Target Conditions'),
            _buildConfigRow(
              label: 'Target Temperature:',
              controller: _tempController,
              unit: '°C',
            ),
            _buildConfigRow(
              label: 'Target Humidity:',
              controller: _humidityController,
              unit: '%',
            ),
            _buildConfigRow(
              label: 'Target Soil Moisture:',
              controller: _soilMoistureController,
              unit: '%',
            ),
            _buildConfigRow(
              label: 'Target Light Intensity:',
              controller: _lightIntensityController,
              unit: 'Lux',
            ),
            const SizedBox(height: 20),

            // --- 3. Automation Schedules ---
            _buildSectionTitle('Automation Schedules'),
            _buildConfigRow(
              label: 'Fertility Frequency:',
              controller: _fertilityFreqController,
              unit: 'days',
            ),
            _buildConfigRow(
              label: 'Irrigation Water Amount:',
              controller: _waterAmountController,
              unit: 'ml/plant',
            ),
            _buildConfigRow(
              label: 'Camera Photo Interval:',
              controller: _cameraIntervalController,
              unit: 'hours',
            ),
            const SizedBox(height: 40),

            // --- SAVE CONFIGURATION Button ---
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveConfiguration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Text(
                        'SAVE CONFIGURATION',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // Logout button for completeness (Optional)
            Center(
              child: TextButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  // FIX: Navigate to LoginScreen and clear stack after signing out
                  // NOTE: You must ensure LoginScreen is imported in this file.
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (Route<dynamic> route) => false,
                  );
                },
                child: const Text('Logout'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }
}
