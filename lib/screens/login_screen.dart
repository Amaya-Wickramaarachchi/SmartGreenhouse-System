import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- Screen Imports ---
import 'farmer_dashboard_screen.dart';
import 'admin_configuration_screen.dart';

// Global flag to prevent auto-login after registration
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
  // True = Farmer login mode, False = Admin login mode
  bool isFarmerMode = true;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  // ─────────────────────────────────────────────
  // Show a SnackBar message at the bottom of the screen
  // ─────────────────────────────────────────────
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Displays a "No Permission" alert with red styling and blocks access.
  // ─────────────────────────────────────────────
  Future<void> _showNoPermissionDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Row(
            children: [
              Icon(Icons.block, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Text(
                'No Permission',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            'You do not have permission to access the Admin panel.\n\nOnly Admin accounts can log in here.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(),
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

  // ─────────────────────────────────────────────
  // [DIALOG 2] — Shown when an ADMIN tries to log in via FARMER mode.
  // Returns true  → proceed to Farmer Dashboard
  // Returns false → cancel, sign out, stay on login screen
  // ─────────────────────────────────────────────
  Future<bool> _showAdminAsFarmerConfirmation() async {
    bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text(
                'Confirm Login',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to login to the Farmer Dashboard?\n\nYou are currently logged in as an Admin.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            // NO — cancel and sign out
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
              child: const Text(
                'No, Cancel',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            // YES — go to Farmer Dashboard
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Yes, Continue',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  // ─────────────────────────────────────────────
  // Fetch user role from Firestore WHILE user is still signed in,
  // then navigate or show dialog based on role + selected login mode.
  //
  // Login Mode | Stored Role | Result
  // -----------+-------------+--------------------------------------------
  // Admin UI   | Admin       | ✅ Go to AdminConfigurationScreen
  // Admin UI   | Farmer      | ❌ Show "No Permission" dialog → sign out
  // Farmer UI  | Farmer      | ✅ Go to FarmerDashboardScreen
  // Farmer UI  | Admin       | ⚠️  Show confirmation dialog → Yes/No
  // ─────────────────────────────────────────────
  Future<void> _fetchUserRoleAndNavigate(User user) async {
    try {
      // Read Firestore BEFORE any signOut — user is authenticated at this point
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        await _auth.signOut();
        if (mounted) _showSnackBar('User role missing.', isError: true);
        return;
      }

      final String? storedRole = userDoc.data()?['role'] as String?;

      if (!mounted) return;

      // ── CASE 1: ADMIN login mode selected ──
      if (!isFarmerMode) {
        if (storedRole == 'Farmer') {
          // Farmer trying Admin login → sign out THEN show No Permission dialog
          await _auth.signOut();
          if (mounted) await _showNoPermissionDialog();
        } else if (storedRole == 'Admin') {
          // Admin → Admin login → ALLOW
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminConfigurationScreen()),
          );
        } else {
          await _auth.signOut();
          if (mounted) {
            _showSnackBar('Invalid role. Access denied.', isError: true);
          }
        }
      }
      // ── CASE 2: FARMER login mode selected ──
      else {
        if (storedRole == 'Farmer') {
          // Farmer → Farmer login → ALLOW
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const FarmerDashboardScreen()),
          );
        } else if (storedRole == 'Admin') {
          // Admin trying Farmer login → show confirmation dialog
          bool confirm = await _showAdminAsFarmerConfirmation();

          if (confirm) {
            // Admin said YES → go to Farmer Dashboard
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const FarmerDashboardScreen(),
                ),
              );
            }
          } else {
            // Admin said NO → sign out, stay on login screen
            await _auth.signOut();
          }
        } else {
          await _auth.signOut();
          if (mounted) {
            _showSnackBar('Invalid role. Access denied.', isError: true);
          }
        }
      }
    } catch (e) {
      await _auth.signOut();
      if (mounted) _showSnackBar('Failed to verify role.', isError: true);
    }
  }

  // ─────────────────────────────────────────────
  // Handle LOGIN button press.
  // Validates input → Firebase sign-in → role check → navigate.
  // ─────────────────────────────────────────────
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
      // Step 1: Firebase sign-in
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        // Step 2: Immediately fetch role while user is still authenticated
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

  // ─────────────────────────────────────────────
  // Show the Registration dialog.
  // Role is auto-assigned from current login mode.
  // Signs out after registration to prevent auto-login.
  // ─────────────────────────────────────────────
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

              setState(() => isRegistering = true);
              isRegisteringProcess = true;

              final email = regEmailController.text.trim();
              final password = regPasswordController.text.trim();
              final role = isFarmerMode ? 'Farmer' : 'Admin';

              try {
                // Step 1: Create Firebase Auth account
                final userCredential = await _auth
                    .createUserWithEmailAndPassword(
                      email: email,
                      password: password,
                    );

                // Step 2: Store role in Firestore while authenticated
                await _firestore
                    .collection('users')
                    .doc(userCredential.user!.uid)
                    .set({'email': email, 'role': role});

                // Step 3: Sign out to prevent auto-login
                await _auth.signOut();
                isRegisteringProcess = false;

                // Step 4: Close the registration dialog
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }

                // Step 5: Show success alert
                if (mounted) {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
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
                setState(() => isRegistering = false);
              } catch (e) {
                isRegisteringProcess = false;
                _showSnackBar('Unexpected error occurred.', isError: true);
                setState(() => isRegistering = false);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: isRegistering
                  ? null
                  : Text('Register as ${isFarmerMode ? "Farmer" : "Admin"}'),
              content: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: isRegistering
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

  // Builds the Farmer/Admin toggle mode button
  Widget _buildModeButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final Color foregroundColor = isActive ? Colors.white : activeColor;
    final Color backgroundColor = isActive ? activeColor : Colors.white;

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

  // Reusable text field decoration
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

              // App logo
              Image.asset('assets/smartgreen_logo.png', height: 80, width: 80),
              const SizedBox(height: 10),

              // App name
              const Text(
                'SmartGreen',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),

              SizedBox(height: screenHeight * 0.05),

              // Login mode toggle: Farmer | Admin
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

              // Email input
              TextField(
                controller: _usernameController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration(
                  hint: 'Username',
                  icon: Icons.person_outline,
                ),
              ),
              const SizedBox(height: 20),

              // Password input
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

              // Login button
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

              // Registration link
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
