// Import flutter_dotenv to securely load environment variables (e.g., passwords)
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FontFeature;
// Import MQTT client packages for real-time IoT communication
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  // MQTT client instance
  MqttServerClient? client;

  // Device display names (used by remote-command handler)
  static const Map<String, String> _names = {
    'pump': 'Water Pump',
    'fan': 'Ventilation Fan',
    'mister': 'Mister',
    'shade': 'Shade Net',
    'led': 'Grow Lights',
  };

  // --- System Mode State ---
  // Tracks whether the greenhouse is operating autonomously or manually
  String _systemMode = "AUTO";

  // --- Hardware Actuator States ---
  // Boolean variables to track the ON/OFF status of each physical device
  bool _isPumpOn = false;
  bool _isFanOn = false;
  bool _isMisterOn = false;
  bool _isLedOn = false;
  bool _isShadeOn = false;

  // Map to store active timers for each manually overridden device
  // Key: Actuator ID (e.g., 'fan'), Value: The Timer instance
  final Map<String, Timer> _activeTimers = {};

  // --- Countdown display state ---
  // When each device's timer will finish, and how long it was set for
  final Map<String, DateTime> _endTimes = {};
  final Map<String, int> _totalSeconds = {};

  // 1-second ticker that refreshes the countdown on screen.
  // It only runs while at least one timer is active.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Initialize the MQTT connection as soon as the screen loads
    _setupMqttConnection();
  }

  // --- MQTT Connection Setup ---
  Future<void> _setupMqttConnection() async {
    // One client ID used everywhere
    final clientId = 'flutter_ctrl_${DateTime.now().millisecondsSinceEpoch}';

    // Initialize the client with the HiveMQ cloud broker URL and a unique client ID
    client = MqttServerClient.withPort(
      'c0eacb6e24dd4984814b3e19f4daa7a4.s1.eu.hivemq.cloud',
      clientId,
      8883, // Secure MQTT port
    );

    // Connection configurations
    client!.secure = true; // Enable SSL/TLS
    client!.logging(on: false); // Disable excessive logging for production
    client!.keepAlivePeriod = 60; // Keep connection alive by pinging every 60s

    // Authenticate securely using environment variables loaded from the .env file
    client!.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(
          dotenv.env['MQTT_USERNAME']!, // Securely fetched username
          dotenv.env['MQTT_PASSWORD']!, // Securely fetched password
        );

    try {
      await client!.connect();

      if (client!.connectionStatus?.state == MqttConnectionState.connected) {
        debugPrint("Control Screen MQTT Connected Successfully!");

        // Subscribe so this phone also hears what other phones do
        client!.subscribe('greenhouse/mode', MqttQos.atLeastOnce);
        client!.subscribe('greenhouse/manual_cmd', MqttQos.atLeastOnce);

        client!.updates?.listen((messages) {
          for (final message in messages) {
            final publishMessage = message.payload as MqttPublishMessage;
            final payload = MqttPublishPayload.bytesToStringAsString(
              publishMessage.payload.message,
            );
            try {
              final data = jsonDecode(payload);
              if (!mounted || data is! Map) continue;

              if (message.topic == 'greenhouse/mode') {
                _onRemoteMode(data);
              } else if (message.topic == 'greenhouse/manual_cmd') {
                _onRemoteCmd(data);
              }
            } catch (e) {
              debugPrint('MQTT update error: $e');
            }
          }
        });
      } else {
        debugPrint("Control Screen MQTT connection was not successful.");
      }
    } catch (e) {
      debugPrint("Control Screen MQTT Connection Failed: $e");
      client?.disconnect();
    }
  }

  // ---------------------------------------------------------------
  // Remote sync handlers (messages coming from other phones)
  // ---------------------------------------------------------------

  // Sets one device's local ON/OFF flag by its id
  void _setLocal(String id, bool v) {
    switch (id) {
      case 'pump':
        _isPumpOn = v;
        break;
      case 'fan':
        _isFanOn = v;
        break;
      case 'mister':
        _isMisterOn = v;
        break;
      case 'shade':
        _isShadeOn = v;
        break;
      case 'led':
        _isLedOn = v;
        break;
    }
  }

  // Another phone changed the system mode
  void _onRemoteMode(Map data) {
    final mode = data['mode']?.toString().toUpperCase();
    if (mode != 'AUTO' && mode != 'MANUAL') return;

    setState(() {
      _systemMode = mode!;
      if (mode == 'AUTO') {
        // AUTO from any phone resets timers and switches everywhere
        for (var t in _activeTimers.values) {
          t.cancel();
        }
        _activeTimers.clear();
        _endTimes.clear();
        _totalSeconds.clear();
        _ticker?.cancel();
        _ticker = null;
        _isPumpOn = false;
        _isFanOn = false;
        _isMisterOn = false;
        _isShadeOn = false;
        _isLedOn = false;
      }
    });
  }

  // Another phone turned a device ON/OFF
  void _onRemoteCmd(Map data) {
    for (final id in _names.keys) {
      if (!data.containsKey(id)) continue;
      final on = data[id].toString().toUpperCase() == 'ON';

      if (on) {
        setState(() => _setLocal(id, true));
        final secs = int.tryParse(data['duration']?.toString() ?? '');
        // Skip if this phone already has the timer (this is our own message echoed back)
        if (secs != null && secs > 0 && !_activeTimers.containsKey(id)) {
          _handleActuatorTimer(
            id,
            _names[id]!,
            0,
            () => setState(() => _setLocal(id, false)),
            seconds: secs,
          );
        }
      } else {
        // Device turned OFF elsewhere: stop our timer and countdown too
        _activeTimers[id]?.cancel();
        _activeTimers.remove(id);
        _clearCountdown(id);
        setState(() => _setLocal(id, false));
      }
    }
  }

  // --- MQTT Publish Methods ---

  // Publishes the overarching system mode (AUTO or MANUAL) to the edge device
  void _publishMode(String mode) {
    if (client?.connectionStatus?.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      // Format payload as JSON: {"mode": "AUTO"}
      builder.addString(jsonEncode({"mode": mode}));
      client!.publishMessage(
        'greenhouse/mode',
        MqttQos.atLeastOnce, // Ensure delivery
        builder.payload!,
      );
    }
  }

  // Publishes direct hardware commands (ON/OFF) to specific actuators.
  // For ON, the duration (seconds) is included so other phones can start the same countdown.
  void _publishManualCmd(String device, String state, {int? durationSeconds}) {
    if (client?.connectionStatus?.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      // Format payload as JSON: {"fan": "ON", "duration": 300}
      builder.addString(
        jsonEncode({
          device: state,
          if (durationSeconds != null) 'duration': durationSeconds,
        }),
      );
      client!.publishMessage(
        'greenhouse/manual_cmd',
        MqttQos.atLeastOnce,
        builder.payload!,
      );
    }
  }

  @override
  void dispose() {
    // Cancel all running timers to prevent memory leaks when the screen is closed
    for (var timer in _activeTimers.values) {
      timer.cancel();
    }
    _ticker?.cancel();
    // Disconnect MQTT client cleanly
    client?.disconnect();
    super.dispose();
  }

  // Displays a non-intrusive floating message to provide feedback to the user
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
        // Use a distinct blue color for automatic timer expirations
        backgroundColor: isAutoOff
            ? Colors.blue.shade800
            : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Countdown helpers
  // ---------------------------------------------------------------

  // Starts the 1-second UI ticker (only if it is not already running)
  void _startTicker() {
    if (_ticker?.isActive ?? false) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_endTimes.isEmpty) {
        _ticker?.cancel();
        _ticker = null;
        return;
      }
      setState(() {}); // just repaint the countdowns
    });
  }

  // Seconds left for a device (0 if no timer)
  int _remainingSeconds(String id) {
    final end = _endTimes[id];
    if (end == null) return 0;
    final ms = end.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  // 125 -> "02:05"
  String _formatCountdown(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // Forget the countdown of one device
  void _clearCountdown(String id) {
    _endTimes.remove(id);
    _totalSeconds.remove(id);
    if (_endTimes.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  // --- Core Safety Feature: Dual-Layer Timer Management ---
  // Handles the logic when a manual override timer expires.
  // `duration` is in minutes; `seconds` (optional) overrides it for remote timers.
  void _handleActuatorTimer(
    String actuatorId,
    String name,
    int duration,
    Function turnOffAction, {
    int? seconds,
  }) {
    // Cancel any existing timer for this specific device before starting a new one
    _activeTimers[actuatorId]?.cancel();

    final secs = seconds ?? duration * 60;

    // Remember when this timer ends so the card can show a live countdown
    _endTimes[actuatorId] = DateTime.now().add(Duration(seconds: secs));
    _totalSeconds[actuatorId] = secs;
    _startTicker();

    // Start a new timer based on the selected duration
    _activeTimers[actuatorId] = Timer(Duration(seconds: secs), () {
      if (mounted) {
        turnOffAction(); // Step 1: Update local App UI state to OFF
        _publishManualCmd(
          actuatorId,
          "OFF",
        ); // Step 2: Send OFF command to Edge device

        // Remove the expired timer from the active list
        _activeTimers.remove(actuatorId);
        _clearCountdown(actuatorId);

        // Step 3: Crucial Safety Logic
        // If there are no other active manual overrides running, completely revert the system to AUTO mode
        if (_activeTimers.isEmpty) {
          setState(() {
            _systemMode = "AUTO"; // Update App UI to AUTO
          });
          _publishMode("AUTO"); // Inform Edge device to resume autonomous logic

          _showActionSnackBar(
            '⏰ $name OFF. System completely reverted to AUTO mode.',
            isAutoOff: true,
          );
        } else {
          // If other devices are still running manually, just turn off this specific device
          _showActionSnackBar(
            '⏰ Timer finished: $name automatically turned OFF.',
            isAutoOff: true,
          );
        }
      }
    });
  }

  // Handles the logic when a user manually turns off a device BEFORE the timer expires
  void _turnOffManually(String actuatorId, String name) {
    _activeTimers[actuatorId]?.cancel(); // Stop the timer
    _activeTimers.remove(actuatorId); // Remove from active list
    _clearCountdown(actuatorId); // Hide its countdown
    _publishManualCmd(actuatorId, "OFF"); // Send OFF command to Edge

    // If this was the last active manual device, revert to AUTO
    if (_activeTimers.isEmpty) {
      setState(() {
        _systemMode = "AUTO";
      });
      _publishMode("AUTO");
      _showActionSnackBar(
        '$name turned OFF manually. System reverted to AUTO mode.',
        isAutoOff: true, // Show the blue theme to indicate system transition
      );
    } else {
      // If other devices are still on, just say this one turned off
      _showActionSnackBar('$name turned OFF manually.');
    }
  }

  // User tapped the AUTO button: stop every manual timer and reset all switches
  void _switchToAuto() {
    for (var timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    _endTimes.clear();
    _totalSeconds.clear();
    _ticker?.cancel();
    _ticker = null;

    setState(() {
      _systemMode = "AUTO";
      _isPumpOn = false;
      _isFanOn = false;
      _isMisterOn = false;
      _isLedOn = false;
      _isShadeOn = false;
    });
    _publishMode("AUTO");
  }

  // Displays a popup allowing the user to set a timer when turning a device ON manually
  void _showConfirmationDialog(
    String actuatorName,
    bool newValue,
    Function(bool, int?) onConfirm,
  ) {
    int selectedTime = 1; // Default timer duration is 1 minute

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
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
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to turn ${newValue ? "ON" : "OFF"} the $actuatorName?\n\nThis will override the autonomous logic.',
                    style: const TextStyle(fontSize: 15),
                  ),
                  // Only show the slider if the user is turning the device ON
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
                    // Slider to dynamically select time between 1 and 60 minutes
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
                          selectedTime = val.toInt();
                        });
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
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
                    // Trigger the confirmed action callback with the selected time
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

  // --- Specific Actuator Toggle Handlers ---
  // Each function wraps the confirmation dialog and timer management logic for a specific device

  void _togglePump(bool value) {
    _showConfirmationDialog('Water Pump', value, (confirmed, duration) {
      setState(() => _isPumpOn = confirmed);
      if (confirmed) {
        _publishManualCmd("pump", "ON", durationSeconds: duration! * 60);
        _showActionSnackBar('Water Pump ON for $duration minutes.');
        _handleActuatorTimer(
          'pump',
          'Water Pump',
          duration,
          () => setState(() => _isPumpOn = false),
        );
      } else {
        _turnOffManually('pump', 'Water Pump');
      }
    });
  }

  void _toggleFan(bool value) {
    _showConfirmationDialog('Ventilation Fan', value, (confirmed, duration) {
      setState(() => _isFanOn = confirmed);
      if (confirmed) {
        _publishManualCmd("fan", "ON", durationSeconds: duration! * 60);
        _showActionSnackBar('Ventilation Fan ON for $duration minutes.');
        _handleActuatorTimer(
          'fan',
          'Ventilation Fan',
          duration,
          () => setState(() => _isFanOn = false),
        );
      } else {
        _turnOffManually('fan', 'Ventilation Fan');
      }
    });
  }

  void _toggleMister(bool value) {
    _showConfirmationDialog('Mister', value, (confirmed, duration) {
      setState(() => _isMisterOn = confirmed);
      if (confirmed) {
        _publishManualCmd("mister", "ON", durationSeconds: duration! * 60);
        _showActionSnackBar('Mister ON for $duration minutes.');
        _handleActuatorTimer(
          'mister',
          'Mister',
          duration,
          () => setState(() => _isMisterOn = false),
        );
      } else {
        _turnOffManually('mister', 'Mister');
      }
    });
  }

  void _toggleShade(bool value) {
    _showConfirmationDialog('Shade Net', value, (confirmed, duration) {
      setState(() => _isShadeOn = confirmed);
      if (confirmed) {
        _publishManualCmd("shade", "ON", durationSeconds: duration! * 60);
        _showActionSnackBar('Shade Net ON for $duration minutes.');
        _handleActuatorTimer(
          'shade',
          'Shade Net',
          duration,
          () => setState(() => _isShadeOn = false),
        );
      } else {
        _turnOffManually('shade', 'Shade Net');
      }
    });
  }

  void _toggleLed(bool value) {
    _showConfirmationDialog('Grow Lights', value, (confirmed, duration) {
      setState(() => _isLedOn = confirmed);
      if (confirmed) {
        _publishManualCmd("led", "ON", durationSeconds: duration! * 60);
        _showActionSnackBar('Grow Lights ON for $duration minutes.');
        _handleActuatorTimer(
          'led',
          'Grow Lights',
          duration,
          () => setState(() => _isLedOn = false),
        );
      } else {
        _turnOffManually('led', 'Grow Lights');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Utility flag to quickly check if the system is currently in AUTO mode
    bool isAuto = _systemMode == "AUTO";

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Equipment Control',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Segmented Control for System Mode (AUTO vs MANUAL) ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "SYSTEM MODE",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // AUTO Mode Button
                      Expanded(
                        child: GestureDetector(
                          onTap: _switchToAuto,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: isAuto
                                  ? Colors.green.shade600
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                "AUTO",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isAuto
                                      ? Colors.white
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // MANUAL Mode Button
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _systemMode = "MANUAL");
                            _publishMode("MANUAL");
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !isAuto
                                  ? Colors.orange.shade600
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                "MANUAL",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: !isAuto
                                      ? Colors.white
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- Manual Override Controls Section ---
            const Text(
              "MANUAL OVERRIDES",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            // Contextual help text guiding the user based on the current mode
            Text(
              isAuto
                  ? 'Switch to MANUAL mode to enable controls.'
                  : 'Set timers for each device. They will automatically turn off when the timer ends.',
              style: TextStyle(
                color: isAuto ? Colors.red.shade400 : Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),

            // Dynamic Hardware Control Cards
            // If the system is in AUTO mode, the 'onChanged' callback is null, visibly disabling the switches
            _buildControlCard(
              'pump',
              'Water Pump',
              'Activates irrigation',
              Icons.water_drop,
              Colors.blue,
              _isPumpOn,
              isAuto ? null : _togglePump,
            ),
            _buildControlCard(
              'fan',
              'Ventilation Fan',
              'Reduces ambient temp',
              Icons.air,
              Colors.orange,
              _isFanOn,
              isAuto ? null : _toggleFan,
            ),
            _buildControlCard(
              'mister',
              'Mister',
              'Increases humidity',
              Icons.cloudy_snowing,
              Colors.cyan,
              _isMisterOn,
              isAuto ? null : _toggleMister,
            ),
            _buildControlCard(
              'shade',
              'Shade Net',
              'Reduces light intensity',
              Icons.wb_shade,
              Colors.brown,
              _isShadeOn,
              isAuto ? null : _toggleShade,
            ),
            _buildControlCard(
              'led',
              'Grow Lights',
              'Increases light intensity',
              Icons.lightbulb,
              Colors.amber,
              _isLedOn,
              isAuto ? null : _toggleLed,
            ),
          ],
        ),
      ),
    );
  }

  // Small pill that shows the live countdown, e.g. [ ⏱ 04:32 ]
  Widget _buildCountdownChip(int remaining, Color color) {
    // Last 10 seconds -> turn red so the user notices it is about to switch off
    final bool endingSoon = remaining <= 10;
    final Color chipColor = endingSoon ? Colors.red.shade600 : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: chipColor.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: chipColor),
          const SizedBox(width: 4),
          Text(
            _formatCountdown(remaining),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: chipColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  // --- Reusable UI Component for Device Control ---
  // Renders a stylized SwitchListTile for a given actuator,
  // with a live countdown chip + progress bar while its timer is running.
  Widget _buildControlCard(
    String actuatorId,
    String title,
    String subtitle,
    IconData icon,
    Color iconColor,
    bool currentValue,
    Function(bool)? onChanged, // A null function disables the entire card
  ) {
    bool isDisabled = onChanged == null;

    final int remaining = _remainingSeconds(actuatorId);
    final int total = _totalSeconds[actuatorId] ?? 0;
    final bool hasTimer = currentValue && _endTimes.containsKey(actuatorId);
    final double progress = (hasTimer && total > 0)
        ? (remaining / total).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // Add a colored border if the device is currently turned ON
        side: BorderSide(
          color: isDisabled
              ? Colors.transparent
              : (currentValue
                    ? iconColor.withOpacity(0.5)
                    : Colors.grey.shade200),
        ),
      ),
      // Gray out the background slightly when disabled (in AUTO mode)
      color: isDisabled ? Colors.grey.shade100 : Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: SwitchListTile(
              activeColor: iconColor,
              secondary: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  // Dynamically color the icon background based on state and availability
                  color: isDisabled
                      ? Colors.grey.shade200
                      : (currentValue
                            ? iconColor.withOpacity(0.15)
                            : Colors.grey.shade100),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isDisabled
                      ? Colors.grey.shade400
                      : (currentValue ? iconColor : Colors.grey.shade600),
                ),
              ),
              // Title + live countdown chip right next to the device name
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDisabled
                            ? Colors.grey.shade500
                            : Colors.black87,
                      ),
                    ),
                  ),
                  if (hasTimer) ...[
                    const SizedBox(width: 8),
                    _buildCountdownChip(remaining, iconColor),
                  ],
                ],
              ),
              subtitle: Text(
                hasTimer ? 'Running - auto OFF when timer ends' : subtitle,
                style: TextStyle(
                  color: isDisabled
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                ),
              ),
              value: currentValue,
              onChanged: onChanged,
            ),
          ),

          // Thin progress bar along the bottom edge: shrinks as time runs out
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: hasTimer
                ? LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: iconColor.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      remaining <= 10 ? Colors.red.shade600 : iconColor,
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }
}
