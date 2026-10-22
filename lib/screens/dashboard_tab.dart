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

  // --- Clock State ---
  String _currentTime = '';
  Timer? _clockTimer;

  // --- Live Sensor Data ---
  double? _temp1;
  double? _temp2;
  double? _humidity;
  double? _soilMoisture;
  double? _lightLux;

  // --- AI Harvest Data ---
  int _totalFruits = 0;
  String _harvestStatus = "Waiting for data...";
  String _lastHarvestUpdate = "Not scanned yet";

  // --- Firestore Targets ---
  double? _targetSoilTemp; // Firestore: targetSoilTemp
  double? _targetAirTemp; // Firestore: targetTemp (air)
  double? _targetHumidity;
  double? _targetMoisture;
  double? _targetLight;

  // --- Firestore Automation Schedule ---
  int? _numberOfPlants;
  int? _fertilityFreqDays;
  int? _cameraIntervalHours;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _configSub;

  // --- Alert tolerances (alert fires when live value drifts past target +/- tolerance) ---
  static const double _tempTolerance = 2.0; // °C above target
  static const double _humidityTolerance = 15.0; // % either side
  static const double _moistureTolerance = 10.0; // % below target

  // --- System Mode ---
  String _systemMode = "AUTO"; // Default Mode

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _healthStatus = 'CONNECTING...';
  Color _healthColor = Colors.orange;

  @override
  void initState() {
    super.initState();
    _startClock();
    _setupMqttConnection();
    _listenToConfiguration();
  }

  void _startClock() {
    _updateTime();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTime(),
    );
  }

  void _updateTime() {
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _currentTime =
            "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}  "
            "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      });
    }
  }

  void _listenToConfiguration() {
    _configSub = _firestore
        .collection('configuration')
        .doc('settings')
        .snapshots()
        .listen((doc) {
          if (doc.exists && mounted) {
            final data = doc.data();
            setState(() {
              _targetSoilTemp = (data?['targetSoilTemp'] as num?)?.toDouble();
              _targetAirTemp = (data?['targetTemp'] as num?)?.toDouble();
              _targetHumidity = (data?['targetHumid'] as num?)?.toDouble();
              _targetMoisture = (data?['targetMoist'] as num?)?.toDouble();
              _targetLight = (data?['targetLight'] as num?)?.toDouble();

              _numberOfPlants = (data?['numberOfPlants'] as num?)?.toInt();
              _fertilityFreqDays = (data?['fertilityFreqDays'] as num?)
                  ?.toInt();
              _cameraIntervalHours = (data?['cameraIntervalHours'] as num?)
                  ?.toInt();

              // Targets changed -> re-evaluate health immediately
              _updateHealth();
            });
          }
        }, onError: (e) => debugPrint('Config listener error: $e'));
  }

  Future<void> _setupMqttConnection() async {
    // Client ID එකට _dash කෑල්ලක් දැම්මා, Control screen එකත් එක්ක පැටලෙන්නේ නැති වෙන්න
    client = MqttServerClient.withPort(
      'c0eacb6e24dd4984814b3e19f4daa7a4.s1.eu.hivemq.cloud',
      'flutter_dash_${DateTime.now().millisecondsSinceEpoch}',
      8883,
    );

    client!.secure = true;
    client!.logging(on: false);
    client!.keepAlivePeriod = 60;
    client!.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(
          'flutter_dash_${DateTime.now().millisecondsSinceEpoch}',
        )
        .authenticateAs('greenhouse_admin', 'Admin@123');

    try {
      await client!.connect();
    } catch (e) {
      if (mounted)
        setState(() {
          _healthStatus = 'CONNECTION ERROR';
          _healthColor = Colors.red;
        });
      return;
    }

    if (client!.connectionStatus!.state == MqttConnectionState.connected) {
      if (mounted)
        setState(() {
          _healthStatus = 'WAITING FOR DATA';
          _healthColor = Colors.orange;
        });

      client!.subscribe('greenhouse/telemetry', MqttQos.atMostOnce);
      client!.subscribe('greenhouse/fruit_result', MqttQos.atLeastOnce);
      client!.subscribe(
        'greenhouse/mode',
        MqttQos.atMostOnce,
      ); // Mode එක අහගෙන ඉන්නවා

      client!.updates!.listen((messages) {
        final topic = messages[0].topic;
        final payload = MqttPublishPayload.bytesToStringAsString(
          (messages[0].payload as MqttPublishMessage).payload.message,
        );

        if (topic == 'greenhouse/telemetry') {
          _parseSensorData(payload);
        } else if (topic == 'greenhouse/fruit_result') {
          _parseHarvestData(payload);
        } else if (topic == 'greenhouse/mode') {
          _parseMode(payload);
        }
      });
    }
  }

  void _parseMode(String payload) {
    try {
      final data = jsonDecode(payload);
      if (mounted && data.containsKey('mode')) {
        setState(() => _systemMode = data['mode'].toString().toUpperCase());
      }
    } catch (e) {
      print("Mode Parse Error: $e");
    }
  }

  void _parseSensorData(String payload) {
    try {
      final data = jsonDecode(payload);
      if (mounted) {
        setState(() {
          _temp1 = (data['temperature_1'] as num?)?.toDouble();
          _temp2 = (data['temperature_2'] as num?)?.toDouble();
          _humidity = (data['humidity'] as num?)?.toDouble();
          _soilMoisture = (data['soil_moisture'] as num?)?.toDouble();
          _lightLux = (data['light_lux'] as num?)?.toDouble();
          _updateHealth();
        });
      }
    } catch (e) {
      print("Telemetry JSON Error: $e");
    }
  }

  void _parseHarvestData(String payload) {
    try {
      final data = jsonDecode(payload);
      if (data['analysis_type'] == 'fruit' && mounted) {
        setState(() {
          _totalFruits = data['total_fruits'] ?? 0;
          _harvestStatus = data['harvest_status'] ?? "Unknown";
          _lastHarvestUpdate = data['timestamp'] ?? "Unknown time";
        });
      }
    } catch (e) {
      print("Harvest JSON Error: $e");
    }
  }

  bool _tooHigh(double? value, double? target, double tol) =>
      value != null && target != null && value > target + tol;

  bool _tooLow(double? value, double? target, double tol) =>
      value != null && target != null && value < target - tol;

  bool _outOfBand(double? value, double? target, double tol) =>
      _tooHigh(value, target, tol) || _tooLow(value, target, tol);

  void _updateHealth() {
    if (_temp1 == null ||
        _temp2 == null ||
        _humidity == null ||
        _soilMoisture == null) {
      _healthStatus = 'WAITING FOR DATA';
      _healthColor = Colors.orange;
      return;
    }

    final alerts = <String>[];
    bool critical = false;

    if (_tooHigh(_temp2, _targetAirTemp, _tempTolerance)) {
      alerts.add('HIGH AIR TEMP');
      critical = true;
    }
    if (_tooHigh(_temp1, _targetSoilTemp, _tempTolerance)) {
      alerts.add('HIGH SOIL TEMP');
      critical = true;
    }
    if (_tooLow(_soilMoisture, _targetMoisture, _moistureTolerance)) {
      alerts.add('LOW MOISTURE');
    }
    if (_outOfBand(_humidity, _targetHumidity, _humidityTolerance)) {
      alerts.add('HUMIDITY OFF TARGET');
    }

    if (alerts.isEmpty) {
      _healthStatus = 'SYSTEM OPTIMAL';
      _healthColor = Colors.green;
    } else {
      _healthStatus = alerts.length == 1
          ? '${alerts.first} ALERT'
          : '${alerts.first} +${alerts.length - 1} MORE';
      _healthColor = critical ? Colors.red : Colors.amber.shade800;
    }
  }

  @override
  void dispose() {
    client?.disconnect();
    _configSub?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 25),

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
            _buildTargetRow(),
            const SizedBox(height: 30),

            const Text(
              "AUTOMATION SCHEDULE",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _buildScheduleRow(),
            const SizedBox(height: 30),

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
            _buildSensorGrid(),
            const SizedBox(height: 30),

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
            _buildHarvestCard(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: _healthColor,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _systemMode == "AUTO"
                      ? Colors.green.shade800
                      : Colors.orange.shade800,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "MODE: $_systemMode",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _currentTime.split('  ').length > 1
                    ? _currentTime.split('  ')[1]
                    : '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtNum(double? v) {
    if (v == null) return "--";
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  Widget _buildTargetRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _targetPill(
            Icons.thermostat,
            "Soil Temp",
            _targetSoilTemp,
            "°C",
            Colors.orange,
          ),
          _targetPill(
            Icons.device_thermostat,
            "Air Temp",
            _targetAirTemp,
            "°C",
            Colors.deepOrange,
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

  Widget _buildScheduleRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _targetPill(
            Icons.eco,
            "Plants",
            _numberOfPlants?.toDouble(),
            "",
            Colors.green,
          ),
          _targetPill(
            Icons.science,
            "Fertilize every",
            _fertilityFreqDays?.toDouble(),
            " days",
            Colors.purple,
          ),
          _targetPill(
            Icons.camera_alt,
            "Photo every",
            _cameraIntervalHours?.toDouble(),
            " h",
            Colors.teal,
          ),
        ],
      ),
    );
  }

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
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.grey.shade200),
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
            value != null ? "${_fmtNum(value)}$unit" : "--",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.0,
      children: [
        _sensorCard(
          "Soil Temp",
          _temp1,
          "°C",
          Icons.thermostat,
          Colors.orange,
          target: _targetSoilTemp,
          alert: _tooHigh(_temp1, _targetSoilTemp, _tempTolerance),
        ),
        _sensorCard(
          "Air Temp",
          _temp2,
          "°C",
          Icons.device_thermostat,
          Colors.deepOrange,
          target: _targetAirTemp,
          alert: _tooHigh(_temp2, _targetAirTemp, _tempTolerance),
        ),
        _sensorCard(
          "Humidity",
          _humidity,
          "%",
          Icons.water_drop,
          Colors.blue,
          target: _targetHumidity,
          alert: _outOfBand(_humidity, _targetHumidity, _humidityTolerance),
        ),
        _sensorCard(
          "Soil Moisture",
          _soilMoisture,
          "%",
          Icons.grass,
          Colors.brown,
          target: _targetMoisture,
          alert: _tooLow(_soilMoisture, _targetMoisture, _moistureTolerance),
        ),
        _sensorCard(
          "Light Level",
          _lightLux,
          "Lux",
          Icons.wb_sunny,
          Colors.amber,
          target: _targetLight,
        ),
      ],
    );
  }

  Widget _sensorCard(
    String title,
    double? value,
    String unit,
    IconData icon,
    Color iconColor, {
    double? target,
    bool alert = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: alert ? Border.all(color: Colors.red.shade300, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
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
          const SizedBox(height: 10),
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                  color: alert ? Colors.red.shade700 : Colors.black87,
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
          const SizedBox(height: 4),
          Text(
            "Target: ${_fmtNum(target)}${target != null ? unit : ''}",
            style: TextStyle(
              fontSize: 12,
              color: alert ? Colors.red.shade400 : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHarvestCard() {
    Color statusColor = _harvestStatus.toLowerCase().contains("ready")
        ? Colors.orange.shade800
        : Colors.green.shade600;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade100, width: 2),
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
          ],
        ),
      ),
    );
  }
}
