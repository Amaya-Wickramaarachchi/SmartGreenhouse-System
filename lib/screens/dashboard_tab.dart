import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:percent_indicator/percent_indicator.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  MqttServerClient? client;

  // --- MOCK DATA FOR DASHBOARD ---
  double? _temp1 = 29.2;
  double? _temp2 = 28.5;
  double? _humidity = 76.5;
  double? _soilMoisture = 60.0;
  double? _lightLux = 15200.0;

  String _healthStatus = 'SYSTEM OPTIMAL';
  Color _healthColor = Colors.green.shade600;
  // -------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _setupMqttConnection();
  }

  Future<void> _setupMqttConnection() async {
    // HiveMQ Cloud Credentials
    client = MqttServerClient.withPort(
      'c0eacb6e24dd4984814b3e19f4daa7a4.s1.eu.hivemq.cloud',
      'flutter_mobile_client_${DateTime.now().millisecondsSinceEpoch}',
      8883,
    );

    client!.secure = true;
    client!.logging(on: false);
    client!.keepAlivePeriod = 20;

    final connMess = MqttConnectMessage()
        .withClientIdentifier('flutter_mobile_client')
        .authenticateAs('greenhouse_admin', 'Admin@123');

    client!.connectionMessage = connMess;

    try {
      await client!.connect();
    } catch (e) {
      print('Exception: $e');
      client!.disconnect();
      setState(() {
        _healthStatus = 'CONNECTION ERROR';
        _healthColor = Colors.red;
      });
      return;
    }

    if (client!.connectionStatus!.state == MqttConnectionState.connected) {
      const topic = 'greenhouse/telemetry';
      client!.subscribe(topic, MqttQos.atMostOnce);

      client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        final recMess = c![0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );
        _parseSensorData(payload);
      });
    }
  }

  void _parseSensorData(String payload) {
    try {
      Map<String, dynamic> data = jsonDecode(payload);

      setState(() {
        // Extracting exact keys from ESP32 payload
        _temp1 = (data['temperature_1'] as num?)?.toDouble();
        _temp2 = (data['temperature_2'] as num?)?.toDouble();
        _humidity = (data['humidity'] as num?)?.toDouble();
        _soilMoisture = (data['soil_moisture'] as num?)?.toDouble();
        _lightLux = (data['light_lux'] as num?)?.toDouble();

        _updateHealthStatus();
      });
    } catch (e) {
      print('Error parsing JSON: $e');
    }
  }

  void _updateHealthStatus() {
    if (_temp1 == null || _soilMoisture == null) {
      _healthStatus = 'WAITING FOR DATA';
      _healthColor = Colors.orange;
    } else if (_temp1! > 32) {
      _healthStatus = 'WARNING: HIGH TEMP';
      _healthColor = Colors.red.shade700;
    } else if (_soilMoisture! < 40) {
      _healthStatus = 'WARNING: LOW MOISTURE';
      _healthColor = Colors.amber.shade700;
    } else {
      _healthStatus = 'HEALTHY';
      _healthColor = Colors.green;
    }
  }

  @override
  void dispose() {
    client?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildHealthStatusBanner(),
          const SizedBox(height: 30),

          const Text(
            'Environmental Conditions',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // 1. Circular Gauges for Temp and Humidity
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCircularGauge(
                title: 'Temperature 1',
                value: _temp1,
                unit: '°C',
                maxLimit: 50.0,
                progressColor: Colors.orange,
                icon: Icons.thermostat,
              ),
              _buildCircularGauge(
                title: 'Humidity',
                value: _humidity,
                unit: '%',
                maxLimit: 100.0,
                progressColor: Colors.blue,
                icon: Icons.water_drop,
              ),
            ],
          ),
          const SizedBox(height: 30),

          // 2. Linear Progress Bar for Soil Moisture
          _buildLinearProgressBar(
            title: 'Soil Moisture',
            value: _soilMoisture,
            progressColor: Colors.brown.shade400,
          ),
          const SizedBox(height: 30),

          // 3. Simple Cards for Light Lux and Temp 2
          Row(
            children: [
              Expanded(
                child: _buildSimpleCard(
                  'Light Intensity',
                  '${_lightLux ?? '--'} Lux',
                  Icons.light_mode,
                  Colors.amber,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildSimpleCard(
                  'Temperature 2',
                  '${_temp2 ?? '--'} °C',
                  Icons.device_thermostat,
                  Colors.orangeAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- UI Builder Methods ---

  Widget _buildHealthStatusBanner() {
    return Container(
      padding: const EdgeInsets.all(15.0),
      decoration: BoxDecoration(
        color: _healthColor,
        borderRadius: BorderRadius.circular(10.0),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(
            _healthStatus.contains('OPTIMAL') || _healthStatus == 'HEALTHY'
                ? Icons.check_circle
                : Icons.warning_amber_rounded,
            color: Colors.white,
            size: 30,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              _healthStatus,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Circular Gauge Widget
  Widget _buildCircularGauge({
    required String title,
    required double? value,
    required String unit,
    required double maxLimit,
    required Color progressColor,
    required IconData icon,
  }) {
    // Calculate percentage (0.0 to 1.0)
    double percent = 0.0;
    if (value != null) {
      percent = value / maxLimit;
      if (percent > 1.0) percent = 1.0;
      if (percent < 0.0) percent = 0.0;
    }

    return Column(
      children: [
        CircularPercentIndicator(
          radius: 60.0,
          lineWidth: 12.0,
          animation: true,
          animateFromLastPercent: true,
          percent: percent,
          center: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: progressColor, size: 24),
              const SizedBox(height: 4),
              Text(
                value != null ? '${value.toStringAsFixed(1)}$unit' : '--',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18.0,
                ),
              ),
            ],
          ),
          circularStrokeCap: CircularStrokeCap.round,
          progressColor: progressColor,
          backgroundColor: Colors.grey.shade200,
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // Linear Progress Bar Widget
  Widget _buildLinearProgressBar({
    required String title,
    required double? value,
    required Color progressColor,
  }) {
    double percent = 0.0;
    if (value != null) {
      percent = value / 100.0;
      if (percent > 1.0) percent = 1.0;
      if (percent < 0.0) percent = 0.0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              value != null ? '${value.toStringAsFixed(1)}%' : '--',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LinearPercentIndicator(
          lineHeight: 20.0,
          animation: true,
          animateFromLastPercent: true,
          percent: percent,
          barRadius: const Radius.circular(10),
          progressColor: progressColor,
          backgroundColor: Colors.grey.shade200,
        ),
      ],
    );
  }

  // Simple Card Widget for Light and Temp2
  Widget _buildSimpleCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
