import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- Import the Functional Dashboard Screens ---
import 'farmer_dashboard_screen.dart';
import 'admin_configuration_screen.dart';

// --- Firebase Instances ---
final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

// --- Visual Constants ---
const Color adminLoginColor = Color(0xFF5A7079);

// ---------------------------------------------

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

  // --- Core Role-Based Logic ---

  Future<void> _fetchUserRoleAndNavigate(User user) async {
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        await _auth.signOut();
        if (mounted)
          _showSnackBar(
            'User role data missing. Please contact support.',
            isError: true,
          );
        return;
      }

      final String? storedRole = userDoc.data()?['role'] as String?;

      if (!mounted) return;

      if (storedRole == 'Farmer') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const FarmerDashboardScreen(),
          ),
        );
      } else if (storedRole == 'Admin') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const AdminConfigurationScreen(),
          ),
        );
      } else {
        await _auth.signOut();
        if (mounted)
          _showSnackBar(
            'Invalid user role assigned. Access denied.',
            isError: true,
          );
      }
    } catch (e) {
      await _auth.signOut();
      if (mounted)
        _showSnackBar(
          'Failed to verify user role: ${e.toString()}',
          isError: true,
        );
    }
  }

  Future<void> _handleLogin() async {
    final email = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      if (mounted)
        _showSnackBar('Please enter both email and password.', isError: true);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (userCredential.user != null) {
        await _fetchUserRoleAndNavigate(userCredential.user!);
      }
    } on FirebaseAuthException {
      if (mounted)
        _showSnackBar(
          'Invalid credentials. Please check your email and password.',
          isError: true,
        );
    } catch (e) {
      if (mounted)
        _showSnackBar(
          'An unexpected error occurred during login: ${e.toString()}',
          isError: true,
        );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

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
                  'Password must be at least 6 characters long.',
                  isError: true,
                );
                return;
              }

              setState(() {
                isRegistering = true;
              });

              final email = regEmailController.text.trim();
              final password = regPasswordController.text.trim();
              final role = isFarmerMode ? 'Farmer' : 'Admin';

              try {
                final userCredential = await _auth
                    .createUserWithEmailAndPassword(
                      email: email,
                      password: password,
                    );
                await _firestore
                    .collection('users')
                    .doc(userCredential.user!.uid)
                    .set({'email': email, 'role': role});

                Navigator.of(dialogContext).pop();
                _showSnackBar('Registration successful! Logged in as $role.');
                await _fetchUserRoleAndNavigate(userCredential.user!);
              } on FirebaseAuthException catch (e) {
                String message = e.message ?? 'Registration failed.';
                _showSnackBar(message, isError: true);
                setState(() {
                  isRegistering = false;
                });
              } catch (e) {
                _showSnackBar('An unexpected error occurred.', isError: true);
                setState(() {
                  isRegistering = false;
                });
              }
            }

            return AlertDialog(
              title: Text('Register as ${isFarmerMode ? "Farmer" : "Admin"}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: regEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email (Username)',
                      ),
                      enabled: !isRegistering,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: regPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password (Min 6 characters)',
                      ),
                      enabled: !isRegistering,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: regConfirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm Password',
                      ),
                      enabled: !isRegistering,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isRegistering
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: isRegistering ? null : performRegistration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: isRegistering
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
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
  // --- FIX: Helper Methods (Moved inside the class) ---

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
  // --- END OF FIX ---

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- Main UI Build Method ---
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    // Trigger the image tag here, just before the layout is built

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(height: screenHeight * 0.05),
              // Logo Placeholder
              SizedBox(height: screenHeight * 0.05),
              Image.asset(
                'assets/smartgreen_logo.png', // YOUR LOGO IS HERE
                height: 80,
                width: 80,
              ),
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

              // 2. Login Mode Selection Buttons
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

              // 3. Username Input Field
              TextField(
                controller: _usernameController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration(
                  hint: 'Username',
                  icon: Icons.person_outline,
                ),
              ),
              const SizedBox(height: 20),

              // 4. Password Input Field
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

              // 5. Main Login Button
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

              // 6. Registration Link
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
