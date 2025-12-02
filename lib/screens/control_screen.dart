import 'package:flutter/material.dart';

// Placeholder for Actuator control color (matching Admin button for contrast)
const Color actuatorControlColor = Color(0xFF5A7079);

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  // State variables for the operational mode and actuator levels (0.0 to 100.0)
  bool _isAutoMode = true; // Default mode is Auto
  double _ventilationFanValue = 0.0;
  double _lightsValue = 0.0;
  double _irrigationPumpValue = 0.0;
  double _coolingFansValue = 0.0;

  // Function to show the critical Warning Alert
  void _showSafetyWarningAlert() {
    showDialog(
      context: context,
      barrierDismissible: false, // User must interact with buttons
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '⚠️ Warning: Manual Override',
            style: TextStyle(color: Colors.red),
          ),
          content: const Text(
            'Are you sure you want to switch from Automated Mode? '
            'Manual Mode disables critical automated climate and irrigation control. '
            'This action requires confirmation.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () {
                Navigator.of(
                  context,
                ).pop(); // Dismiss the dialog, keeping _isAutoMode = true
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'CONFIRM MANUAL MODE',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                setState(() {
                  _isAutoMode = false; // Set to Manual Mode
                });
                // TODO: Log action to ActuatorLog and RequestSetMode(Manual) to Edge Device
                print('Mode set to Manual. Sending command to Edge Device...');
                Navigator.of(context).pop(); // Dismiss the dialog
              },
            ),
          ],
        );
      },
    );
  }

  // Function to handle the mode toggle click
  void _handleModeToggle(bool newValue) {
    if (_isAutoMode == true && newValue == false) {
      // User is attempting to switch from Auto to Manual: trigger warning
      _showSafetyWarningAlert();
    } else {
      // User is switching from Manual (false) back to Auto (true)
      setState(() {
        _isAutoMode = true; // Set back to Auto Mode
        // Reset manual values for a clean switch (optional)
        _ventilationFanValue = _lightsValue = _irrigationPumpValue =
            _coolingFansValue = 0.0;
      });
      // TODO: Log action to ActuatorLog and RequestSetMode(Auto) to Edge Device
      print('Mode set to Auto. Sending command to Edge Device...');
    }
  }

  // Helper widget to build the individual actuator control sliders
  Widget _buildActuatorControl(
    String label,
    double currentValue,
    ValueSetter<double> onChanged,
  ) {
    // Determine the ON/OFF status for immediate feedback
    String status = currentValue > 0 ? "ON" : "OFF";
    Color statusColor = currentValue > 0 ? Colors.green : Colors.grey;
    bool isEnabled = !_isAutoMode; // Control is only enabled in Manual Mode

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isEnabled ? Colors.black87 : Colors.grey.shade500,
                ),
              ),
              Text(
                'Status: $status',
                style: TextStyle(
                  color: isEnabled ? statusColor : Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: currentValue,
            min: 0,
            max: 100, // Representing Intensity or Power Percentage
            divisions: 10,
            label: currentValue.round().toString(),
            // Only allow changes if NOT in Auto Mode
            onChanged: isEnabled ? onChanged : null,
            activeColor: isEnabled
                ? actuatorControlColor
                : Colors.grey.shade400,
            inactiveColor: Colors.grey.shade300,
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
              'Farmer Interface - Control Tab',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // 1. Mode Selector Toggle
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: _isAutoMode ? Colors.green : actuatorControlColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isAutoMode
                        ? 'Automation Mode (ON)'
                        : 'Manual Mode (OVERRIDE)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Switch(
                    value: _isAutoMode,
                    onChanged:
                        _handleModeToggle, // Triggers warning if switching off
                    activeThumbColor: Colors.white,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // 2. Manual Controls Section Label
            Text(
              'Manual Controls',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _isAutoMode ? Colors.grey : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),

            // 3. Actuator Sliders (Enabled only when _isAutoMode is false)

            // Ventilation Fans Control
            _buildActuatorControl('Ventilation Fans', _ventilationFanValue, (
              newValue,
            ) {
              setState(() {
                _ventilationFanValue = newValue;
              });
              // TODO: Send ControlActuator(ActuatorID, State) to the Edge Device
            }),

            // Lights Control
            _buildActuatorControl('Lights', _lightsValue, (newValue) {
              setState(() {
                _lightsValue = newValue;
              });
            }),

            // Irrigation Pump Control
            _buildActuatorControl('Irrigation Pump', _irrigationPumpValue, (
              newValue,
            ) {
              setState(() {
                _irrigationPumpValue = newValue;
              });
            }),

            // Cooling Fans Control
            _buildActuatorControl('Cooling Fans', _coolingFansValue, (
              newValue,
            ) {
              setState(() {
                _coolingFansValue = newValue;
              });
            }),
          ],
        ),
      ),
    );
  }
}
