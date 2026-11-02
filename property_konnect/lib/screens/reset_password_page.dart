import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../firebase_auth.dart';
import 'login_page.dart';

class ResetPasswordPage extends StatefulWidget {
  final String oobCode;

  const ResetPasswordPage({
    super.key,
    required this.oobCode,
  });

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _checkingCode = true;
  bool _codeValid = false;
  bool _saving = false;
  bool _hidePassword = true;
  bool _hideConfirm = true;

  String? _email;
  String? _error;

  @override
  void initState() {
    super.initState();
    _validateResetCode();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _validateResetCode() async {
    try {
      final email = await FirebaseAuthService.instance
          .verifyPasswordResetCode(widget.oobCode);

      if (!mounted) return;

      setState(() {
        _email = email;
        _codeValid = true;
        _checkingCode = false;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        _checkingCode = false;
        _codeValid = false;
        _error = _messageForCodeError(e.code);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _checkingCode = false;
        _codeValid = false;
        _error = 'Could not validate this link. Check your connection '
            'and open the latest password-reset email.';
      });
    }
  }

  String _messageForCodeError(String code) {
    switch (code) {
      case 'expired-action-code':
        return 'This reset link has expired. Request a new one.';
      case 'invalid-action-code':
        return 'This reset link is invalid or has already been used. '
            'Request a new one.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'user-not-found':
        return 'The account for this reset link could not be found.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection and retry.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      default:
        return 'This reset link could not be validated. Request a new one.';
    }
  }

  // ============================================================
  // PASSWORD STRENGTH (same rules as RegistrationPage)
  // ============================================================

  bool _strongPassword(String value) {
    return value.length >= 8 &&
        RegExp(r'[a-z]').hasMatch(value) &&
        RegExp(r'[A-Z]').hasMatch(value) &&
        RegExp(r'[0-9]').hasMatch(value) &&
        RegExp(r'[!@#$%^&*(),.?":{}|<>_-]').hasMatch(value);
  }

  String? _passwordValidator(String? value) {
    final password = value ?? '';

    if (password.isEmpty) {
      return 'Enter a new password.';
    }

    if (!_strongPassword(password)) {
      return 'Use 8+ characters with uppercase, lowercase, '
          'number and special character.';
    }

    return null;
  }

  String? _confirmValidator(String? value) {
    if ((value ?? '').isEmpty) {
      return 'Confirm your new password.';
    }

    if (value != _passwordController.text) {
      return 'The passwords do not match.';
    }

    return null;
  }

  Widget _passwordRules(ThemeData theme) {
    final value = _passwordController.text;

    final rules = [
      {
        'text': '8 or more characters',
        'ok': value.length >= 8,
      },
      {
        'text': 'Lowercase letter',
        'ok': RegExp(r'[a-z]').hasMatch(value),
      },
      {
        'text': 'Uppercase letter',
        'ok': RegExp(r'[A-Z]').hasMatch(value),
      },
      {
        'text': 'Number',
        'ok': RegExp(r'[0-9]').hasMatch(value),
      },
      {
        'text': 'Special character',
        'ok': RegExp(r'[!@#$%^&*(),.?":{}|<>_-]').hasMatch(value),
      },
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF202A23)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: rules.map((rule) {
          final ok = rule['ok'] as bool;
          final muted = theme.brightness == Brightness.dark
              ? Colors.grey.shade400
              : Colors.grey.shade600;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  ok ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 17,
                  color: ok ? Colors.green : muted,
                ),
                const SizedBox(width: 8),
                Text(
                  rule['text'] as String,
                  style: TextStyle(color: ok ? Colors.green : muted),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _saveNewPassword() async {
    if (!_codeValid || !_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await FirebaseAuthService.instance.confirmPasswordReset(
        code: widget.oobCode,
        newPassword: _passwordController.text,
      );

      if (!mounted) return;

      _passwordController.clear();
      _confirmController.clear();

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_outline,
            color: Colors.green,
            size: 48,
          ),
          title: const Text('Password updated'),
          content: const Text(
            'Your password has been changed successfully. '
                'You can now sign in using your new password.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Go to login'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      // Clear the reset page and open the login screen.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
        ),
            (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'expired-action-code':
          message = 'This reset link has expired. Request a new one.';
          break;
        case 'invalid-action-code':
          message = 'This reset link is invalid or has already been used.';
          break;
        case 'weak-password':
          message = 'Choose a stronger password. Use 8+ characters with '
              'uppercase, lowercase, number and special character.';
          break;
        case 'network-request-failed':
          message = 'Network error. Check your connection and retry.';
          break;
        case 'too-many-requests':
          message = 'Too many attempts. Please wait and try again.';
          break;
        default:
          message = 'Could not update your password. Please try again.';
      }

      setState(() => _error = message);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Create New Password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _buildContent(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_checkingCode) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text('Verifying your reset link...'),
        ],
      );
    }

    if (!_codeValid) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.link_off,
            size: 68,
            color: Colors.orange,
          ),
          const SizedBox(height: 20),
          Text(
            'Reset link unavailable',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Request a new password-reset email.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(
                builder: (_) => const LoginPage(),
              ),
                  (route) => false,
            ),
            child: const Text('Return to login'),
          ),
        ],
      );
    }

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.lock_reset,
            size: 72,
            color: Color(0xFF16845B),
          ),
          const SizedBox(height: 20),
          Text(
            'Choose a new password',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Enter a new password for your account.',
            textAlign: TextAlign.center,
          ),
          if (_email != null) ...[
            const SizedBox(height: 8),
            Text(
              _email!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 28),

          // NEW PASSWORD
          TextFormField(
            controller: _passwordController,
            obscureText: _hidePassword,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'New password',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => _hidePassword = !_hidePassword);
                },
                icon: Icon(
                  _hidePassword ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
            validator: _passwordValidator,
          ),
          const SizedBox(height: 10),

          // LIVE PASSWORD RULES CHECKLIST
          _passwordRules(theme),
          const SizedBox(height: 16),

          // CONFIRM PASSWORD
          TextFormField(
            controller: _confirmController,
            obscureText: _hideConfirm,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Confirm new password',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_reset),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => _hideConfirm = !_hideConfirm);
                },
                icon: Icon(
                  _hideConfirm ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
            validator: _confirmValidator,
            onFieldSubmitted: (_) => _saveNewPassword(),
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _saveNewPassword,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: _saving
                  ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Text('Update password'),
            ),
          ),
        ],
      ),
    );
  }
}