import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  MqttServerClient? client;

  // --- clock state ---
  String _currentTime = '';
  Timer? _clockTimer;

  // --- live sensor data ---
  double? _temp1;
  double? _temp2;
  double? _humidity;
  double? _soilMoisture;
  double? _lightLux;

  // --- AI Harvest Data (New) ---
  int _totalFruits = 0;
  String _harvestStatus = "Waiting for data...";
  String _lastHarvestUpdate = "Not scanned yet";

  // --- firestore target settings ---
  double? _targetTemp;
  double? _targetHumidity;
  double? _targetMoisture;
  double? _targetLight;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- system health state ---
  String _healthStatus = 'CONNECTING...';
  Color _healthColor = Colors.orange;

  @override
  void initState() {
    super.initState();
    _startClock();
    _setupMqttConnection();
    _listenToConfiguration();
  }

  // --- clock logic ---
  void _startClock() {
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTime();
    });
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _currentTime =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}  "
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    });
  }

  // --- fetch targets from firestore ---
  void _listenToConfiguration() {
    _firestore.collection('configuration').doc('settings').snapshots().listen((
      doc,
    ) {
      if (doc.exists) {
        final data = doc.data();
        setState(() {
          _targetTemp = (data?['targetTemp'] as num?)?.toDouble();
          _targetHumidity = (data?['targetHumid'] as num?)?.toDouble();
          _targetMoisture = (data?['targetMoist'] as num?)?.toDouble();
          _targetLight = (data?['targetLight'] as num?)?.toDouble();
        });
      }
    });
  }

  // --- connect to hivemq broker ---
  Future<void> _setupMqttConnection() async {
    client = MqttServerClient.withPort(
      'c0eacb6e24dd4984814b3e19f4daa7a4.s1.eu.hivemq.cloud',
      'flutter_mobile_${DateTime.now().millisecondsSinceEpoch}',
      8883,
    );

    client!.secure = true;
    client!.logging(on: false);
    client!.keepAlivePeriod = 20;

    client!.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_mobile')
        .authenticateAs('greenhouse_admin', 'Admin@123');

    try {
      await client!.connect();
    } catch (e) {
      client!.disconnect();
      setState(() {
        _healthStatus = 'CONNECTION ERROR';
        _healthColor = Colors.red;
      });
      return;
    }

    if (client!.connectionStatus!.state == MqttConnectionState.connected) {
      setState(() {
        _healthStatus = 'WAITING FOR DATA';
        _healthColor = Colors.orange;
      });

      // Subscribe to BOTH topics
      client!.subscribe('greenhouse/telemetry', MqttQos.atMostOnce);
      client!.subscribe('greenhouse/fruit_result', MqttQos.atLeastOnce);

      client!.updates!.listen((messages) {
        final topic =
            messages[0].topic; // Identify which topic this message came from
        final rec = messages[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
          rec.payload.message,
        );

        // Route the payload to the correct parser
        if (topic == 'greenhouse/telemetry') {
          _parseSensorData(payload);
        } else if (topic == 'greenhouse/fruit_result') {
          _parseHarvestData(payload);
        }
      });
    }
  }

  // --- update UI with new sensor data ---
  void _parseSensorData(String payload) {
    try {
      final data = jsonDecode(payload);

      setState(() {
        _temp1 = (data['temperature_1'] as num?)?.toDouble();
        _temp2 = (data['temperature_2'] as num?)?.toDouble();
        _humidity = (data['humidity'] as num?)?.toDouble();
        _soilMoisture = (data['soil_moisture'] as num?)?.toDouble();
        _lightLux = (data['light_lux'] as num?)?.toDouble();

        _updateHealth();
      });
    } catch (_) {}
  }

  // --- update UI with new AI harvest data ---
  void _parseHarvestData(String payload) {
    try {
      final data = jsonDecode(payload);

      if (data['analysis_type'] == 'fruit') {
        setState(() {
          _totalFruits = data['total_fruits'] ?? 0;
          _harvestStatus = data['harvest_status'] ?? "Unknown";
          _lastHarvestUpdate = data['timestamp'] ?? "Unknown time";
        });
      }
    } catch (_) {}
  }

  // --- simple edge logic evaluation for UI ---
  void _updateHealth() {
    if (_temp1 == null || _soilMoisture == null) {
      _healthStatus = 'WAITING FOR DATA';
      _healthColor = Colors.orange;
    } else if (_temp1! > 32) {
      _healthStatus = 'HIGH TEMP ALERT';
      _healthColor = Colors.red;
    } else if (_soilMoisture! < 40) {
      _healthStatus = 'LOW MOISTURE ALERT';
      _healthColor = Colors.amber.shade800;
    } else {
      _healthStatus = 'SYSTEM OPTIMAL';
      _healthColor = Colors.green;
    }
  }

  @override
  void dispose() {
    client?.disconnect();
    _clockTimer?.cancel();
    super.dispose();
  }

  // ================= UI BUILD =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50, // clean off-white background
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 25),

            // targets section header
            const Text(
              "CONFIGURED TARGETS",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _buildTargetRow(), // much prettier targets UI

            const SizedBox(height: 30),

            // live telemetry header
            const Text(
              "LIVE TELEMETRY",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _buildSensorGrid(), // upgraded cards

            const SizedBox(height: 30),

            // AI Harvest section header
            const Text(
              "AI HARVEST ANALYSIS",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _buildHarvestCard(), // New AI Card integration

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // --- top status bar ---
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: _healthColor, // dynamically changes color based on health
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _healthColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "SYSTEM STATUS",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _healthStatus,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _currentTime.split('  ')[1], // show only time in the pill
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- modern horizontally scrolling targets ---
  Widget _buildTargetRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _targetPill(
            Icons.thermostat,
            "Temp",
            _targetTemp,
            "°C",
            Colors.orange,
          ),
          _targetPill(
            Icons.water_drop,
            "Humidity",
            _targetHumidity,
            "%",
            Colors.blue,
          ),
          _targetPill(
            Icons.grass,
            "Moisture",
            _targetMoisture,
            "%",
            Colors.brown,
          ),
          _targetPill(
            Icons.light_mode,
            "Light",
            _targetLight,
            "Lux",
            Colors.amber,
          ),
        ],
      ),
    );
  }

  // --- ui template for a single target pill ---
  Widget _targetPill(
    IconData icon,
    String title,
    double? value,
    String unit,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30), // round pill shape
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            "$title: ",
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value != null ? "$value$unit" : "--",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // --- grid for live data ---
  Widget _buildSensorGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics:
          const NeverScrollableScrollPhysics(), // scrolling handled by main view
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.1, // make cards slightly taller
      children: [
        _sensorCard(
          "Temperature 1",
          _temp1,
          "°C",
          Icons.thermostat,
          Colors.orange,
        ),
        _sensorCard(
          "Temperature 2",
          _temp2,
          "°C",
          Icons.device_thermostat,
          Colors.deepOrange,
        ),
        _sensorCard("Humidity", _humidity, "%", Icons.water_drop, Colors.blue),
        _sensorCard(
          "Soil Moisture",
          _soilMoisture,
          "%",
          Icons.grass,
          Colors.brown,
        ),
        _sensorCard(
          "Light Level",
          _lightLux,
          "Lux",
          Icons.wb_sunny,
          Colors.amber,
        ),
      ],
    );
  }

  // --- ui template for live sensor cards ---
  Widget _sensorCard(
    String title,
    double? value,
    String unit,
    IconData icon,
    Color iconColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value != null ? value.toStringAsFixed(1) : "--",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- New AI Harvest Card Widget ---
  Widget _buildHarvestCard() {
    Color statusColor = _harvestStatus.toLowerCase().contains("ready")
        ? Colors.orange.shade800
        : Colors.green.shade600;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade100, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.green[700],
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Edge Vision Result",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[900],
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "YOLOv8",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Ready Fruits Detected:",
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
                Text(
                  "$_totalFruits",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Harvest Status:",
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _harvestStatus,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            const Divider(),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.sync, size: 14, color: Colors.grey),
                const SizedBox(width: 5),
                Text(
                  "Last scan: $_lastHarvestUpdate",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
