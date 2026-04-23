import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  // MQTT Client
  MqttServerClient? client;
  bool _isConnected = false;

  // Actuator States
  bool _isPumpOn = false;
  bool _isFanOn = false;
  bool _isMisterOn = false;
  bool _isLedOn = false;

  @override
  void initState() {
    super.initState();
    _setupMqttConnection();
  }

  // Connect to HiveMQ Cloud [cite: 451, 452]
  Future<void> _setupMqttConnection() async {
    client = MqttServerClient.withPort(
      'c0eacb6e24dd4984814b3e19f4daa7a4.s1.eu.hivemq.cloud',
      'flutter_control_client_${DateTime.now().millisecondsSinceEpoch}',
      8883,
    );

    client!.secure = true;
    client!.logging(on: false);
    client!.keepAlivePeriod = 20;

    final connMess = MqttConnectMessage()
        .withClientIdentifier('flutter_control_client')
        .authenticateAs(
          'greenhouse_admin',
          'Admin@123',
        ); // ESP32 credentials [cite: 482, 483]

    client!.connectionMessage = connMess;

    try {
      await client!.connect();
    } catch (e) {
      print('Connection failed: $e');
      client!.disconnect();
      return;
    }

    if (client!.connectionStatus!.state == MqttConnectionState.connected) {
      setState(() {
        _isConnected = true;
      });
      print('Connected to HiveMQ Cloud for Manual Control!');
    }
  }

  // Publish a command to the Edge Controller
  void _publishCommand(String actuator, bool state) {
    if (_isConnected == false || client == null) return;

    // Create the JSON command
    final commandMap = {
      "actuator": actuator,
      "command": state ? "ON" : "OFF",
      "override": true, // Tells the Edge Controller to ignore autonomous logic
    };

    final payload = jsonEncode(commandMap);
    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    // Publish to a specific control topic
    const topic = 'greenhouse/control';
    client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);

    print('Published command: $payload to $topic');
  }

  // Handle Switch Toggles
  void _togglePump(bool value) {
    setState(() => _isPumpOn = value);
    _publishCommand('Pump', value);
  }

  void _toggleFan(bool value) {
    setState(() => _isFanOn = value);
    _publishCommand('Fan', value);
  }

  void _toggleMister(bool value) {
    setState(() => _isMisterOn = value);
    _publishCommand('Mister', value);
  }

  void _toggleLed(bool value) {
    setState(() => _isLedOn = value);
    _publishCommand('LED', value);
  }

  @override
  void dispose() {
    client?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Override Control'),
        backgroundColor: Colors.green.shade700,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Icon(
              _isConnected ? Icons.cloud_done : Icons.cloud_off,
              color: _isConnected ? Colors.white : Colors.redAccent,
            ),
          ),
        ],
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
              'Use these switches to override the Edge Computing autonomous logic.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 30),

            // Control Cards
            _buildControlCard(
              'Water Pump',
              'Activates irrigation',
              Icons.water_drop,
              _isPumpOn,
              _togglePump,
            ),
            _buildControlCard(
              'Ventilation Fan',
              'Reduces ambient temperature',
              Icons.air,
              _isFanOn,
              _toggleFan,
            ),
            _buildControlCard(
              'Mister',
              'Increases humidity levels',
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

  // Reusable UI Component for the Switches
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
          onChanged: onChanged,
        ),
      ),
    );
  }
}
