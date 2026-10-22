import 'package:flutter/foundation.dart';
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
  bool _isLoading = true;

  // --- Text Controllers for Configuration Inputs ---
  final TextEditingController _plantCountController = TextEditingController();
  final TextEditingController _soilTempController = TextEditingController();
  final TextEditingController _airTempController = TextEditingController();
  final TextEditingController _humidityController = TextEditingController();
  final TextEditingController _soilMoistureController = TextEditingController();
  final TextEditingController _lightIntensityController =
      TextEditingController();
  final TextEditingController _fertilityFreqController =
      TextEditingController();
  final TextEditingController _cameraIntervalController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  // Formats numbers nicely: 30.0 -> "30", 27.5 -> "27.5"
  String _fmt(dynamic v, String fallback) {
    if (v == null) return fallback;
    if (v is num) {
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    return v.toString();
  }

  Future<void> _loadCurrentSettings() async {
    try {
      final doc = await _firestore
          .collection('configuration')
          .doc('settings')
          .get();

      final data = doc.data();
      if (data != null && mounted) {
        setState(() {
          _plantCountController.text = _fmt(data['numberOfPlants'], '50');
          _airTempController.text = _fmt(data['targetTemp'], '30');
          _soilTempController.text = _fmt(data['targetSoilTemp'], '25');
          _humidityController.text = _fmt(data['targetHumid'], '75');
          _soilMoistureController.text = _fmt(data['targetMoist'], '60');
          _lightIntensityController.text = _fmt(data['targetLight'], '10000');
          _fertilityFreqController.text = _fmt(data['fertilityFreqDays'], '7');
          _cameraIntervalController.text = _fmt(
            data['cameraIntervalHours'],
            '4',
          );
        });
      } else if (mounted) {
        // No document yet -> show defaults
        setState(() {
          _plantCountController.text = '50';
          _airTempController.text = '30';
          _soilTempController.text = '25';
          _humidityController.text = '75';
          _soilMoistureController.text = '60';
          _lightIntensityController.text = '10000';
          _fertilityFreqController.text = '7';
          _cameraIntervalController.text = '4';
        });
      }
    } catch (e) {
      debugPrint('Load config error: $e');
      _showSnackBar('Failed to load current settings.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _plantCountController.dispose();
    _soilTempController.dispose();
    _airTempController.dispose();
    _humidityController.dispose();
    _soilMoistureController.dispose();
    _lightIntensityController.dispose();
    _fertilityFreqController.dispose();
    _cameraIntervalController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // Parses a number field. Returns null (and shows an error) if invalid.
  double? _parseDouble(
    TextEditingController c,
    String label, {
    required double min,
    required double max,
  }) {
    final v = double.tryParse(c.text.trim());
    if (v == null) {
      _showSnackBar('$label must be a valid number.', isError: true);
      return null;
    }
    if (v < min || v > max) {
      _showSnackBar('$label must be between $min and $max.', isError: true);
      return null;
    }
    return v;
  }

  int? _parseInt(
    TextEditingController c,
    String label, {
    required int min,
    required int max,
  }) {
    final v = int.tryParse(c.text.trim());
    if (v == null) {
      _showSnackBar('$label must be a whole number.', isError: true);
      return null;
    }
    if (v < min || v > max) {
      _showSnackBar('$label must be between $min and $max.', isError: true);
      return null;
    }
    return v;
  }

  // --- Function to Save Configuration to Firestore ---
  Future<void> _saveConfiguration() async {
    // Validate EVERYTHING first (so we never write null/invalid values)
    final soilTemp = _parseDouble(
      _soilTempController,
      'Target Soil Temperature',
      min: -10,
      max: 60,
    );
    if (soilTemp == null) return;

    final airTemp = _parseDouble(
      _airTempController,
      'Target Air Temperature',
      min: -10,
      max: 60,
    );
    if (airTemp == null) return;

    final humid = _parseDouble(
      _humidityController,
      'Target Humidity',
      min: 0,
      max: 100,
    );
    if (humid == null) return;

    final moist = _parseDouble(
      _soilMoistureController,
      'Target Soil Moisture',
      min: 0,
      max: 100,
    );
    if (moist == null) return;

    final light = _parseDouble(
      _lightIntensityController,
      'Target Light Intensity',
      min: 0,
      max: 200000,
    );
    if (light == null) return;

    final fertDays = _parseInt(
      _fertilityFreqController,
      'Fertility Frequency',
      min: 1,
      max: 365,
    );
    if (fertDays == null) return;

    final camHours = _parseInt(
      _cameraIntervalController,
      'Camera Photo Interval',
      min: 1,
      max: 168,
    );
    if (camHours == null) return;

    final plants = _parseInt(
      _plantCountController,
      'Number of Plants',
      min: 1,
      max: 100000,
    );
    if (plants == null) return;

    setState(() {
      _isSaving = true;
    });

    final Map<String, dynamic> configData = {
      'timestamp': FieldValue.serverTimestamp(),
      'targetSoilTemp': soilTemp,
      'targetTemp': airTemp,
      'targetHumid': humid,
      'targetMoist': moist,
      'targetLight': light,
      'fertilityFreqDays': fertDays,
      'cameraIntervalHours': camHours,
      'numberOfPlants': plants,
    };

    try {
      await _firestore
          .collection('configuration')
          .doc('settings')
          .set(configData, SetOptions(merge: true));
      _showSnackBar(
        'Configuration saved successfully and synced to Edge Device!',
        isError: false,
      );
    } catch (e) {
      debugPrint('Save config error: $e');
      _showSnackBar(
        'Error saving configuration. Check Admin privileges and connection.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (Route<dynamic> route) => false,
    );
  }

  // ---------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------

  // A single rounded input with icon + unit
  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String unit,
    required IconData icon,
    required Color color,
    bool allowDecimal = true,
  }) {
    return TextField(
      controller: controller,
      enabled: !_isSaving,
      keyboardType: TextInputType.numberWithOptions(
        decimal: allowDecimal,
        signed: true,
      ),
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade600),
        floatingLabelStyle: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(icon, color: color, size: 22),
        suffixText: unit,
        suffixStyle: TextStyle(
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: 2),
        ),
      ),
    );
  }

  // Two fields side by side
  Widget _buildFieldPair(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  // Card that groups related settings
  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade700, Colors.green.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.tune, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edge Configuration',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Saved values sync live to the Edge Node and the farmer dashboard.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveConfiguration,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(
                _isSaving ? 'SAVING...' : 'SAVE & SYNC CONFIGURATION',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.green.shade300,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green.shade700,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderBanner(),

                    // --- 1. Asset Setup ---
                    _buildSectionCard(
                      title: 'Asset Setup',
                      subtitle: 'What is growing in this greenhouse',
                      icon: Icons.eco,
                      color: Colors.green.shade600,
                      children: [
                        _buildField(
                          label: 'Number of Plants',
                          controller: _plantCountController,
                          unit: 'plants',
                          icon: Icons.local_florist,
                          color: Colors.green.shade600,
                          allowDecimal: false,
                        ),
                      ],
                    ),

                    // --- 2. Temperature Targets ---
                    _buildSectionCard(
                      title: 'Temperature Targets',
                      subtitle: 'Alerts fire when live readings go above these',
                      icon: Icons.thermostat,
                      color: Colors.deepOrange,
                      children: [
                        _buildFieldPair(
                          _buildField(
                            label: 'Soil Temp',
                            controller: _soilTempController,
                            unit: '°C',
                            icon: Icons.thermostat,
                            color: Colors.orange.shade700,
                          ),
                          _buildField(
                            label: 'Air Temp',
                            controller: _airTempController,
                            unit: '°C',
                            icon: Icons.device_thermostat,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ],
                    ),

                    // --- 3. Environment Targets ---
                    _buildSectionCard(
                      title: 'Environment Targets',
                      subtitle: 'Ideal humidity, moisture and light levels',
                      icon: Icons.water_drop,
                      color: Colors.blue,
                      children: [
                        _buildFieldPair(
                          _buildField(
                            label: 'Humidity',
                            controller: _humidityController,
                            unit: '%',
                            icon: Icons.water_drop,
                            color: Colors.blue,
                          ),
                          _buildField(
                            label: 'Soil Moisture',
                            controller: _soilMoistureController,
                            unit: '%',
                            icon: Icons.grass,
                            color: Colors.brown,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildField(
                          label: 'Light Intensity',
                          controller: _lightIntensityController,
                          unit: 'Lux',
                          icon: Icons.wb_sunny,
                          color: Colors.amber.shade700,
                        ),
                      ],
                    ),

                    // --- 4. Automation Schedule ---
                    _buildSectionCard(
                      title: 'Automation Schedule',
                      subtitle: 'How often the Edge Node acts',
                      icon: Icons.schedule,
                      color: Colors.purple,
                      children: [
                        _buildFieldPair(
                          _buildField(
                            label: 'Fertilize every',
                            controller: _fertilityFreqController,
                            unit: 'days',
                            icon: Icons.science,
                            color: Colors.purple,
                            allowDecimal: false,
                          ),
                          _buildField(
                            label: 'Photo every',
                            controller: _cameraIntervalController,
                            unit: 'hours',
                            icon: Icons.camera_alt,
                            color: Colors.teal,
                            allowDecimal: false,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _isLoading ? null : _buildSaveBar(),
    );
  }
}
