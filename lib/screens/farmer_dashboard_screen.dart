import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --- Importing the functional LoginScreen and other tabs ---
import 'login_screen.dart';
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
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (Route<dynamic> route) => false,
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to logout: ${e.toString()}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),

      body: IndexedStack(index: _selectedIndex, children: _widgetOptions),

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
