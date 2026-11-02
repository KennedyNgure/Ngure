import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'email_verification_page.dart';
import 'homepage.dart';
import 'login_page.dart';
import 'terms_page.dart';
import 'privacy_policy_page.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _green => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _background =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _card => _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _text => _isDark ? Colors.grey.shade200 : Colors.grey.shade800;

  Color get _muted => _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  String _tr(String en, String sw) {
    return AppSettings.of(context).languageCode == 'sw' ? sw : en;
  }

  // ============================================================
  // NAVIGATION
  // ============================================================

  /// The AppBar back button goes straight to the public Homepage
  /// instead of popping the navigation stack.
  void _goToHomePage() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _muted),
      prefixIcon: Icon(icon, color: _green),
      filled: true,
      fillColor: _card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: _isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _green, width: 2),
      ),
    );
  }

  String? _nameValidator(String? value) {
    final valueText = value?.trim() ?? '';

    if (valueText.length < 2) {
      return _tr(
        'Enter your full name or business name.',
        'Weka jina lako kamili au jina la biashara.',
      );
    }

    return null;
  }

  String? _emailValidator(String? value) {
    final email = value?.trim().toLowerCase() ?? '';

    if (email.isEmpty) {
      return _tr('Enter your email.', 'Weka barua pepe yako.');
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return _tr(
        'Enter a valid email address.',
        'Weka barua pepe halali.',
      );
    }

    return null;
  }

  String? _phoneValidator(String? value) {
    final phone = value?.trim() ?? '';

    if (!RegExp(r'^(07|01)[0-9]{8}$').hasMatch(phone)) {
      return _tr(
        'Enter a valid Kenyan phone number, e.g. 0712345678.',
        'Weka namba halali ya Kenya, mfano 0712345678.',
      );
    }

    return null;
  }

  bool _strongPassword(String value) {
    return value.length >= 8 &&
        RegExp(r'[a-z]').hasMatch(value) &&
        RegExp(r'[A-Z]').hasMatch(value) &&
        RegExp(r'[0-9]').hasMatch(value) &&
        RegExp(r'[!@#$%^&*(),.?":{}|<>_\-]').hasMatch(value);
  }

  String? _passwordValidator(String? value) {
    final password = value ?? '';

    if (!_strongPassword(password)) {
      return _tr(
        'Use 8+ characters with uppercase, lowercase, number and special character.',
        'Tumia herufi 8+ zenye kubwa, ndogo, namba na alama maalum.',
      );
    }

    return null;
  }

  String? _confirmValidator(String? value) {
    if (value != passwordController.text) {
      return _tr('Passwords do not match.', 'Manenosiri hayalingani.');
    }

    return null;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Please accept the Terms and Privacy Policy.',
              'Tafadhali kubali Masharti na Sera ya Faragha.',
            ),
          ),
        ),
      );

      return;
    }

    setState(() {
      _loading = true;
    });

    final String email = emailController.text.trim().toLowerCase();

    final String password = passwordController.text;

    try {
      final UserCredential credential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = credential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'missing-user',
          message: 'Account could not be created.',
        );
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': nameController.text.trim(),
        'email': email,
        'phone': phoneController.text.trim(),

        // PropertyKonnect provider role.
        'role': 'owner',

        // Registration starts with email verification.
        'registrationStage': 'email_verification',

        'emailVerified': false,
        'idUploaded': false,
        'idVerified': false,
        'fingerprintEnabled': false,
        'isActive': true,

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // NOTE: The verification link is sent by EmailVerificationPage
      // (user.sendEmailVerification) as soon as it opens, so it is NOT
      // sent here. That page then polls Firebase Auth; once the owner
      // clicks the link and the email is verified, it updates Firestore
      // (registrationStage: 'id_upload') and opens IdUploadPage.

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EmailVerificationPage(
            name: nameController.text.trim(),
            email: email,
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message = _tr(
            'An account already exists with this email.',
            'Akaunti tayari ipo kwa barua pepe hii.',
          );
          break;

        case 'invalid-email':
          message = _tr(
            'The email address is invalid.',
            'Barua pepe si sahihi.',
          );
          break;

        case 'weak-password':
          message = _tr(
            'The password is too weak.',
            'Nenosiri ni dhaifu sana.',
          );
          break;

        default:
          message = e.message ??
              _tr('Registration failed.', 'Usajili umeshindikana.');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'Registration failed. Please try again.',
                'Usajili umeshindikana. Tafadhali jaribu tena.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // LOGIN
  // ============================================================

  void _openLogin() {
    if (_loading) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
    );
  }

  Widget _passwordRules() {
    final String value = passwordController.text;

    final List<Map<String, dynamic>> rules = [
      {
        'text': _tr('8 or more characters', 'Herufi 8 au zaidi'),
        'ok': value.length >= 8,
      },
      {
        'text': _tr('Lowercase letter', 'Herufi ndogo'),
        'ok': RegExp(r'[a-z]').hasMatch(value),
      },
      {
        'text': _tr('Uppercase letter', 'Herufi kubwa'),
        'ok': RegExp(r'[A-Z]').hasMatch(value),
      },
      {
        'text': _tr('Number', 'Namba'),
        'ok': RegExp(r'[0-9]').hasMatch(value),
      },
      {
        'text': _tr('Special character', 'Alama maalum'),
        'ok': RegExp(r'[!@#$%^&*(),.?":{}|<>_\-]').hasMatch(value),
      },
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF202A23) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: rules.map((rule) {
          final bool ok = rule['ok'] as bool;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  ok ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 17,
                  color: ok ? Colors.green : _muted,
                ),
                const SizedBox(width: 8),
                Text(
                  rule['text'] as String,
                  style: TextStyle(color: ok ? Colors.green : _muted),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: Text(
          _tr('Create Provider Account', 'Unda Akaunti ya Mtoa Mali'),
        ),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: _tr('Back to Homepage', 'Rudi Ukurasa wa Mwanzo'),
          onPressed: _goToHomePage,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: Card(
                color: _card,
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      children: [
                        // HEADER
                        Icon(
                          Icons.person_add_alt_1,
                          size: 62,
                          color: _green,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _tr(
                            'Create your PropertyKonnect account',
                            'Unda akaunti yako ya PropertyKonnect',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _text,
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // NAME
                        TextFormField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _decoration(
                            _tr(
                              'Full name / Business name',
                              'Jina kamili / Jina la biashara',
                            ),
                            Icons.person_outline,
                          ),
                          validator: _nameValidator,
                        ),
                        const SizedBox(height: 14),

                        // EMAIL
                        TextFormField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _decoration(
                            _tr('Email address', 'Barua pepe'),
                            Icons.email_outlined,
                          ),
                          validator: _emailValidator,
                        ),
                        const SizedBox(height: 14),

                        // PHONE
                        TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          decoration: _decoration(
                            _tr('Phone number', 'Namba ya simu'),
                            Icons.phone_outlined,
                          ).copyWith(counterText: ''),
                          validator: _phoneValidator,
                        ),
                        const SizedBox(height: 14),

                        // PASSWORD
                        TextFormField(
                          controller: passwordController,
                          obscureText: _obscurePassword,
                          onChanged: (_) {
                            setState(() {});
                          },
                          decoration: _decoration(
                            _tr('Password', 'Nenosiri'),
                            Icons.lock_outline,
                          ).copyWith(
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                          validator: _passwordValidator,
                        ),
                        const SizedBox(height: 10),
                        _passwordRules(),
                        const SizedBox(height: 14),

                        // CONFIRM PASSWORD
                        TextFormField(
                          controller: confirmPasswordController,
                          obscureText: _obscureConfirm,
                          decoration: _decoration(
                            _tr('Confirm password', 'Thibitisha nenosiri'),
                            Icons.lock_reset_outlined,
                          ).copyWith(
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscureConfirm = !_obscureConfirm;
                                });
                              },
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                          validator: _confirmValidator,
                        ),
                        const SizedBox(height: 14),

                        // TERMS
                        CheckboxListTile(
                          value: _acceptedTerms,
                          onChanged: (value) {
                            setState(() {
                              _acceptedTerms = value ?? false;
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Wrap(
                            children: [
                              Text(
                                _tr('I agree to the ', 'Ninakubali '),
                                style: TextStyle(color: _text),
                              ),
                              InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const TermsPage(),
                                    ),
                                  );
                                },
                                child: Text(
                                  _tr('Terms', 'Masharti'),
                                  style: TextStyle(
                                    color: _green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                _tr(' and ', ' na '),
                                style: TextStyle(color: _text),
                              ),
                              InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                      const PrivacyPolicyPage(),
                                    ),
                                  );
                                },
                                child: Text(
                                  _tr('Privacy Policy', 'Sera ya Faragha'),
                                  style: TextStyle(
                                    color: _green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // CREATE ACCOUNT
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _register,
                            icon: _loading
                                ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Icon(Icons.arrow_forward),
                            label: Text(
                              _loading
                                  ? _tr(
                                'Creating account...',
                                'Inaandaa akaunti...',
                              )
                                  : _tr('Continue', 'Endelea'),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: _green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ALREADY HAVE ACCOUNT
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _tr(
                                'Already have an account?',
                                'Tayari una akaunti?',
                              ),
                              style: TextStyle(color: _muted),
                            ),
                            TextButton(
                              onPressed: _loading ? null : _openLogin,
                              style: TextButton.styleFrom(
                                foregroundColor: _green,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                              ),
                              child: Text(
                                _tr('Login', 'Ingia'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // REGISTRATION FLOW
                        Text(
                          _tr(
                            'Next: email verification → ID verification → fingerprint setup → login',
                            'Ifuatayo: uthibitishaji wa barua pepe → ID → fingerprint → kuingia',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}