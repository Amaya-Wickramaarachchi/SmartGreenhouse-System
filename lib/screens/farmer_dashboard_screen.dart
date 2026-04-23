import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --- Import the functional LoginScreen and other tabs ---
// Make sure this path is correct
import 'dashboard_tab.dart';
import 'control_screen.dart' as control;
import 'diagnosis_screen.dart' as diagnosis;

// -------------------------------------------------------------
// --- Custom Header Widget (SmartGreen) ---
// -------------------------------------------------------------
class SmartGreenHeader extends StatelessWidget {
  final double fontSize;
  final FontWeight fontWeight;

  const SmartGreenHeader({
    super.key,
    this.fontSize = 20.0,
    this.fontWeight = FontWeight.bold,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontFamily: DefaultTextStyle.of(context).style.fontFamily,
        ),
        children: <TextSpan>[
          const TextSpan(
            text: 'Smart',
            style: TextStyle(color: Colors.black87),
          ),
          TextSpan(
            text: 'Green',
            style: TextStyle(color: Colors.green.shade600),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------

class FarmerDashboardScreen extends StatefulWidget {
  const FarmerDashboardScreen({super.key});

  @override
  State<FarmerDashboardScreen> createState() => _FarmerDashboardScreenState();
}

class _FarmerDashboardScreenState extends State<FarmerDashboardScreen> {
  int _selectedIndex = 0;

  // List of screens corresponding to the bottom navigation tabs
  late final List<Widget> _widgetOptions = <Widget>[
    const DashboardTab(),
    const control.ControlScreen(),
    const diagnosis.DiagnosisScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SmartGreenHeader(fontSize: 20.0),
        automaticallyImplyLeading: false, // hide back button after login
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await FirebaseAuth.instance.signOut();
                // No need for Navigator.push; StreamBuilder in main.dart handles redirection
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to logout: ${e.toString()}'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
          ),
        ],
      ),

      // Display the currently selected screen
      body: _widgetOptions.elementAt(_selectedIndex),

      // Bottom navigation bar for tab switching
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_remote),
            label: 'Control',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.monitor_heart),
            label: 'Diagnosis',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.green,
        onTap: _onItemTapped,
      ),
    );
  }
}
