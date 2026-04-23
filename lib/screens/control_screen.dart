import 'package:flutter/material.dart';
import 'dart:async'; // needed for the countdown timer

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  // hardware states
  bool _isPumpOn = false;
  bool _isFanOn = false;
  bool _isMisterOn = false;
  bool _isLedOn = false;

  // map to keep track of running timers
  final Map<String, Timer> _activeTimers = {};

  @override
  void dispose() {
    // kill all timers when leaving this screen (prevents memory leaks!)
    for (var timer in _activeTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  // quick helper to show popup messages
  void _showActionSnackBar(String message, {bool isAutoOff = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isAutoOff ? Icons.alarm_on : Icons.info_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isAutoOff
            ? Colors.blue.shade800
            : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // core logic for auto-turning off the devices
  void _handleActuatorTimer(
    String actuatorId,
    String name,
    int duration,
    Function turnOffAction,
  ) {
    // cancel any existing timer for this specific device
    _activeTimers[actuatorId]?.cancel();

    // start a new timer
    _activeTimers[actuatorId] = Timer(Duration(minutes: duration), () {
      if (mounted) {
        turnOffAction(); // flip the switch back to off
        _showActionSnackBar(
          '⏰ Timer finished: $name automatically turned OFF.',
          isAutoOff: true,
        );
      }
    });
  }

  // custom dialog box to ask for confirmation and time
  void _showConfirmationDialog(
    String actuatorName,
    bool newValue,
    Function(bool, int?) onConfirm,
  ) {
    int selectedTime = 1; // default starting value is 1 min

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        // usING StatefulBuilder so the slider updates live inside the dialog
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    newValue ? Icons.timer : Icons.power_off,
                    color: newValue
                        ? Colors.blue.shade600
                        : Colors.red.shade600,
                  ),
                  const SizedBox(width: 10),
                  const Text('Manual Override', style: TextStyle(fontSize: 20)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min, // wrap content to save space
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to turn ${newValue ? "ON" : "OFF"} the $actuatorName?\n\nThis will override the autonomous logic.',
                    style: const TextStyle(fontSize: 15),
                  ),

                  // only show the time slider if the user is turning it ON
                  if (newValue) ...[
                    const SizedBox(height: 25),
                    const Divider(),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Set Duration:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '$selectedTime mins',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: selectedTime.toDouble(),
                      min: 1,
                      max: 60,
                      divisions: 59,
                      activeColor: Colors.green.shade600,
                      inactiveColor: Colors.green.shade100,
                      label: '$selectedTime mins',
                      onChanged: (val) {
                        setStateDialog(() {
                          selectedTime = val.toInt(); // update slider UI
                        });
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(), // just close
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: newValue
                        ? Colors.green.shade700
                        : Colors.red.shade600,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    // send the user's choice back to the main screen
                    onConfirm(newValue, newValue ? selectedTime : null);
                  },
                  child: Text(
                    newValue ? 'Start Timer' : 'Turn OFF',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- button click handlers for each device ---

  void _togglePump(bool value) {
    _showConfirmationDialog('Water Pump', value, (confirmed, duration) {
      setState(() => _isPumpOn = confirmed);
      if (confirmed) {
        _showActionSnackBar('Water Pump ON for $duration minutes.');
        // start countdown
        _handleActuatorTimer('pump', 'Water Pump', duration!, () {
          setState(() => _isPumpOn = false);
        });
      } else {
        _activeTimers['pump']
            ?.cancel(); // stop timer if user manually turns it off
        _showActionSnackBar('Water Pump turned OFF manually.');
      }
    });
  }

  void _toggleFan(bool value) {
    _showConfirmationDialog('Ventilation Fan', value, (confirmed, duration) {
      setState(() => _isFanOn = confirmed);
      if (confirmed) {
        _showActionSnackBar('Ventilation Fan ON for $duration minutes.');
        _handleActuatorTimer('fan', 'Ventilation Fan', duration!, () {
          setState(() => _isFanOn = false);
        });
      } else {
        _activeTimers['fan']?.cancel();
        _showActionSnackBar('Ventilation Fan turned OFF manually.');
      }
    });
  }

  void _toggleMister(bool value) {
    _showConfirmationDialog('Mister', value, (confirmed, duration) {
      setState(() => _isMisterOn = confirmed);
      if (confirmed) {
        _showActionSnackBar('Mister ON for $duration minutes.');
        _handleActuatorTimer('mister', 'Mister', duration!, () {
          setState(() => _isMisterOn = false);
        });
      } else {
        _activeTimers['mister']?.cancel();
        _showActionSnackBar('Mister turned OFF manually.');
      }
    });
  }

  void _toggleLed(bool value) {
    _showConfirmationDialog('Shade / LED', value, (confirmed, duration) {
      setState(() => _isLedOn = confirmed);
      if (confirmed) {
        _showActionSnackBar('Shade / LED ON for $duration minutes.');
        _handleActuatorTimer('led', 'Shade / LED', duration!, () {
          setState(() => _isLedOn = false);
        });
      } else {
        _activeTimers['led']?.cancel();
        _showActionSnackBar('Shade / LED turned OFF manually.');
      }
    });
  }

  // --- UI building starts here ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Manual Override Control',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green.shade700,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Actuator Controls',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Use these switches to override the Edge Computing autonomous logic. Timers can be set for up to 60 minutes.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 30),

            // load our custom cards
            _buildControlCard(
              'Water Pump',
              'Activates irrigation',
              Icons.water_drop,
              _isPumpOn,
              _togglePump,
            ),
            _buildControlCard(
              'Ventilation Fan',
              'Reduces ambient temp',
              Icons.air,
              _isFanOn,
              _toggleFan,
            ),
            _buildControlCard(
              'Mister',
              'Increases humidity',
              Icons.cloudy_snowing,
              _isMisterOn,
              _toggleMister,
            ),
            _buildControlCard(
              'Shade / LED',
              'Controls light intensity',
              Icons.lightbulb,
              _isLedOn,
              _toggleLed,
            ),
          ],
        ),
      ),
    );
  }

  // UI template for the switches
  Widget _buildControlCard(
    String title,
    String subtitle,
    IconData icon,
    bool currentValue,
    Function(bool) onChanged,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 15.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: SwitchListTile(
          activeThumbColor: Colors.green.shade600,
          secondary: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: currentValue
                  ? Colors.green.shade100
                  : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: currentValue
                  ? Colors.green.shade700
                  : Colors.grey.shade600,
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          subtitle: Text(subtitle),
          value: currentValue,
          onChanged: onChanged, // triggers the popup dialog
        ),
      ),
    );
  }
}
