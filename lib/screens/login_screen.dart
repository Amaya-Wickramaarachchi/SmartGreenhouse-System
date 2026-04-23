import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- Screen Imports ---
import 'farmer_dashboard_screen.dart';
import 'admin_configuration_screen.dart';

// Global flag to prevent auto-login blink
bool isRegisteringProcess = false;

// --- Firebase Instances ---
final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

// --- Constants ---
const Color adminLoginColor = Color(0xFF5A7079);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isFarmerMode = true;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // --- Role Verification ---
  Future<void> _fetchUserRoleAndNavigate(User user) async {
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        await _auth.signOut();
        if (mounted) _showSnackBar('User role missing.', isError: true);
        return;
      }

      final String? storedRole = userDoc.data()?['role'] as String?;

      if (!mounted) return;

      if (storedRole == 'Farmer') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const FarmerDashboardScreen()),
        );
      } else if (storedRole == 'Admin') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminConfigurationScreen()),
        );
      } else {
        await _auth.signOut();
        if (mounted)
          _showSnackBar('Invalid role. Access denied.', isError: true);
      }
    } catch (e) {
      await _auth.signOut();
      if (mounted) _showSnackBar('Failed to verify role.', isError: true);
    }
  }

  // --- Login Handler ---
  Future<void> _handleLogin() async {
    final email = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      if (mounted) _showSnackBar('Enter email and password.', isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (userCredential.user != null) {
        await _fetchUserRoleAndNavigate(userCredential.user!);
      }
    } on FirebaseAuthException {
      if (mounted) _showSnackBar('Invalid credentials.', isError: true);
    } catch (e) {
      if (mounted) _showSnackBar('Unexpected error occurred.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Registration Handler ---
  // --- Registration Handler ---
  void _showRegistrationDialog() {
    final TextEditingController regEmailController = TextEditingController();
    final TextEditingController regPasswordController = TextEditingController();
    final TextEditingController regConfirmPasswordController =
        TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            bool isRegistering = false;

            Future<void> performRegistration() async {
              if (regPasswordController.text !=
                  regConfirmPasswordController.text) {
                _showSnackBar('Passwords do not match.', isError: true);
                return;
              }
              if (regPasswordController.text.length < 6) {
                _showSnackBar(
                  'Password must be at least 6 characters.',
                  isError: true,
                );
                return;
              }

              // Show custom loading animation
              setState(() => isRegistering = true);
              isRegisteringProcess = true;

              final email = regEmailController.text.trim();
              final password = regPasswordController.text.trim();
              final role = isFarmerMode ? 'Farmer' : 'Admin';

              try {
                // Create user
                final userCredential = await _auth
                    .createUserWithEmailAndPassword(
                      email: email,
                      password: password,
                    );

                // Save role to Firestore
                await _firestore
                    .collection('users')
                    .doc(userCredential.user!.uid)
                    .set({'email': email, 'role': role});

                // Prevent auto-login
                await _auth.signOut();
                isRegisteringProcess = false;

                // Close registration dialog
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }

                // Show success alert
                if (mounted) {
                  showDialog(
                    context: context,
                    barrierDismissible: false, // Force OK click
                    builder: (BuildContext alertContext) {
                      return AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        title: const Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 28,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Success',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        content: const Text(
                          'Registration successful!\nPlease login again with your new account.',
                          style: TextStyle(fontSize: 16),
                        ),
                        actions: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => Navigator.of(alertContext).pop(),
                              child: const Text(
                                'OK',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                }
              } on FirebaseAuthException catch (e) {
                isRegisteringProcess = false;
                _showSnackBar(
                  e.message ?? 'Registration failed.',
                  isError: true,
                );
                setState(
                  () => isRegistering = false,
                ); // Show form again on error
              } catch (e) {
                isRegisteringProcess = false;
                _showSnackBar('Unexpected error occurred.', isError: true);
                setState(
                  () => isRegistering = false,
                ); // Show form again on error
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              // Hide title while loading
              title: isRegistering
                  ? null
                  : Text('Register as ${isFarmerMode ? "Farmer" : "Admin"}'),
              // AnimatedSwitcher gives a smooth fade effect
              content: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: isRegistering
                    // --- Loading UI with Leaf Icon ---
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.green),
                            SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.eco, color: Colors.green),
                                SizedBox(width: 8),
                                Text(
                                  'Creating account...',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    // --- Registration Form UI ---
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: regEmailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: regPasswordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Password (Min 6 chars)',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: regConfirmPasswordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Confirm Password',
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              // Hide action buttons while loading
              actions: isRegistering
                  ? []
                  : [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('CANCEL'),
                      ),
                      ElevatedButton(
                        onPressed: performRegistration,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: const Text(
                          'REGISTER NOW',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
            );
          },
        );
      },
    );
  }

  // --- UI Helpers ---
  Widget _buildModeButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    Color foregroundColor = isActive ? Colors.white : activeColor;
    Color backgroundColor = isActive ? activeColor : Colors.white;

    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isActive ? activeColor : Colors.grey.shade300,
            ),
          ),
          elevation: 0,
        ),
        icon: Icon(icon, color: foregroundColor),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    IconData? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.grey),
      suffixIcon: suffixIcon != null
          ? Icon(suffixIcon, color: Colors.grey)
          : null,
      contentPadding: const EdgeInsets.symmetric(
        vertical: 16.0,
        horizontal: 10.0,
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(height: screenHeight * 0.1),
              Image.asset('assets/smartgreen_logo.png', height: 80, width: 80),
              const SizedBox(height: 10),
              const Text(
                'SmartGreen',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: screenHeight * 0.05),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildModeButton(
                    label: 'LOGIN AS FARMER',
                    icon: Icons.eco,
                    isActive: isFarmerMode,
                    activeColor: Colors.green,
                    onTap: () => setState(() => isFarmerMode = true),
                  ),
                  const SizedBox(width: 15),
                  _buildModeButton(
                    label: 'LOGIN AS ADMIN',
                    icon: Icons.settings,
                    isActive: !isFarmerMode,
                    activeColor: adminLoginColor,
                    onTap: () => setState(() => isFarmerMode = false),
                  ),
                ],
              ),

              SizedBox(height: screenHeight * 0.05),

              TextField(
                controller: _usernameController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration(
                  hint: 'Username',
                  icon: Icons.person_outline,
                ),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: _inputDecoration(
                  hint: 'Password',
                  icon: Icons.lock_outline,
                  suffixIcon: Icons.visibility_off_outlined,
                ),
              ),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : const Text(
                          'LOGIN',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? "),
                  GestureDetector(
                    onTap: _isLoading ? null : _showRegistrationDialog,
                    child: const Text(
                      'Register here',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
