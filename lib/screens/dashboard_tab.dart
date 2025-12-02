import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Placeholder data structure (used only if Firestore data is unavailable)
Map<String, dynamic> _defaultSensorData = {
  'temperature': 'N/A',
  'humidity': 'N/A',
  'soilMoisture': 'N/A',
  'lightIntensity': 'N/A',
};

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late Stream<DocumentSnapshot> _sensorStream;

  String _healthStatus = 'CHECKING...';
  Color _healthColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    // Stream data from the specific Firestore document updated by the Edge Device
    _sensorStream = _firestore
        .collection('sensor_data')
        .doc('latest_data')
        .snapshots();
  }

  // Helper function to update the health status based on streamed data
  // This logic compares incoming data against Admin-set thresholds[cite: 301].
  void _updateHealthStatus(Map<String, dynamic> data) {
    double? temp = double.tryParse(data['temperature'].toString() ?? '0');
    double? moisture = double.tryParse(data['soilMoisture'].toString() ?? '0');

    if (temp == null || moisture == null || temp == 0 || moisture == 0) {
      _healthStatus = 'NO DATA';
      _healthColor = Colors.grey;
    } else if (temp > 32) {
      _healthStatus = 'WARNING: HIGH TEMP';
      _healthColor = Colors.red.shade700;
    } else if (moisture < 20) {
      _healthStatus = 'WARNING: LOW MOISTURE';
      _healthColor = Colors.amber.shade700;
    } else {
      _healthStatus = 'HEALTHY';
      _healthColor = Colors.green;
    }
  }

  // ----------------------------------------------------
  // --- BUILD METHOD START ---
  // ----------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 700;

    return StreamBuilder<DocumentSnapshot>(
      stream: _sensorStream,
      builder: (context, snapshot) {
        // Use data from the snapshot or default data if loading/error
        Map<String, dynamic> data = _defaultSensorData;
        if (snapshot.hasData && snapshot.data!.exists) {
          data = snapshot.data!.data() as Map<String, dynamic>;
          _updateHealthStatus(data);
        } else if (snapshot.hasError) {
          _healthStatus = 'ERROR';
          _healthColor = Colors.red;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 1. Health Status Banner (Prominent, color-coded) [cite: 300]
              _buildHealthStatusBanner(),
              const SizedBox(height: 20),

              // 2. Real-time Condition Cards [cite: 298]
              _buildConditionCards(context, isWeb, data),
              const SizedBox(height: 30),

              // 3. Historical Data Section
              const Text(
                'Historical Data (Day by Day)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // Placeholder for Interactive Line Graph [cite: 302]
              Container(
                height: isWeb ? 400 : 250,
                width: double.infinity,
                color: Colors.grey.shade100,
                child: Center(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const CircularProgressIndicator()
                      : Text(
                          'Interactive Time-Series Graph Widget (Uses ActuatorLog/SensorData collections)',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  // ----------------------------------------------------
  // --- BUILD METHOD END ---
  // ----------------------------------------------------

  // --- Helper Widgets ---

  Widget _buildHealthStatusBanner() {
    return Container(
      padding: const EdgeInsets.all(15.0),
      decoration: BoxDecoration(
        color: _healthColor,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _healthStatus == 'HEALTHY'
                ? Icons.check_circle_outline
                : Icons.warning_amber,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(width: 10),
          Text(
            'Current Condition: $_healthStatus',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionCards(
    BuildContext context,
    bool isWeb,
    Map<String, dynamic> data,
  ) {
    final sensorMetrics = [
      {
        'label': 'LIGHT',
        'value': '${data['lightIntensity'] ?? 'N/A'} LUX',
        'icon': Icons.lightbulb_outline,
      },
      {
        'label': 'TEMP',
        'value': '${data['temperature'] ?? 'N/A'} °C',
        'icon': Icons.thermostat_outlined,
      },
      {
        'label': 'HUMIDITY',
        'value': '${data['humidity'] ?? 'N/A'} %',
        'icon': Icons.opacity,
      },
      {
        'label': 'SOIL MOISTURE',
        'value': '${data['soilMoisture'] ?? 'N/A'} %',
        'icon': Icons.water_drop_outlined,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sensorMetrics.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWeb ? 4 : 2,
        crossAxisSpacing: 15,
        mainAxisSpacing: 15,
        childAspectRatio: isWeb ? 1.0 : 1.2,
      ),
      itemBuilder: (context, index) {
        final metric = sensorMetrics[index];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                metric['icon'] as IconData?,
                color: Colors.green,
                size: isWeb ? 40 : 30,
              ),
              const SizedBox(height: 5),
              Text(
                metric['value'] as String,
                style: TextStyle(
                  fontSize: isWeb ? 22 : 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                metric['label'] as String,
                style: TextStyle(
                  fontSize: isWeb ? 14 : 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
