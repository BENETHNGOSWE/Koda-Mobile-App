import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/constants/app_constants.dart';
import '../../../core/config/theme/theme_provider.dart';
import '../../providers/auth_provider.dart';
import 'components/auth_text_field.dart';
import 'components/auth_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();

  final _phoneFocusNode = FocusNode();
  final _pinFocusNode = FocusNode();

  bool _rememberMe = false;
  bool _showPin = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    _phoneFocusNode.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  // Phone validation (same as web)
  bool _isValidPhone(String phone) {
    final cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    return RegExp(r'^(\+?255|0)\d{9}$').hasMatch(cleanPhone);
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    ref.read(authProvider.notifier).clearError();

    final success = await ref
        .read(authProvider.notifier)
        .login(
          phone: _phoneController.text.trim(),
          password: _pinController.text.trim(), // ← Changed from 'pin' to 'password'
          rememberMe: _rememberMe,
        );

    if (success && mounted) {
      context.go('/dashboard');
    }
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Phone number is required';
    }
    if (!_isValidPhone(value)) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  String? _validatePin(String? value) {
    if (value == null || value.isEmpty) {
      return 'PIN is required';
    }
    if (value.length < 4) {
      return 'PIN must be 4 digits';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: SizedBox(
            height: size.height - MediaQuery.of(context).padding.top - 48,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),

                  // Logo
                  Center(
                    child: Image.asset(
                      ref.watch(isDarkModeProvider)
                          ? 'assets/images/white_logo.png'
                          : 'assets/images/black_logo.png',
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Header
                  Text(
                    'Welcome back',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your phone number and PIN to continue',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Error Message
                  if (authState.errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              authState.errorMessage!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Phone Number Field
                  AuthTextField(
                    controller: _phoneController,
                    focusNode: _phoneFocusNode,
                    label: 'Phone Number',
                    hint: '0712 345 678',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: _validatePhone,
                    enabled: !authState.isLoading,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) {
                      FocusScope.of(context).requestFocus(_pinFocusNode);
                    },
                  ),

                  const SizedBox(height: 16),

                  // PIN Field
                  AuthTextField(
                    controller: _pinController,
                    focusNode: _pinFocusNode,
                    label: 'PIN',
                    hint: '••••',
                    prefixIcon: Icons.lock_outline,
                    isPassword: true,
                    validator: _validatePin,
                    enabled: !authState.isLoading,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.number,
                    onFieldSubmitted: (_) => _handleLogin(),
                  ),

                  const SizedBox(height: 8),

                  // Remember Me & Forgot PIN
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: authState.isLoading
                                ? null
                                : (value) {
                                    setState(() {
                                      _rememberMe = value ?? false;
                                    });
                                  },
                          ),
                          Text(
                            'Remember me',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: authState.isLoading
                            ? null
                            : () {
                                // TODO: Navigate to PIN reset screen
                                context.push('/forgot-pin');
                              },
                        child: Text(
                          'Forgot PIN?',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Login Button
                  AuthButton(
                    text: 'Sign In',
                    onPressed: _handleLogin,
                    isLoading: authState.isLoading,
                  ),

                  const Spacer(),

                  // Sign Up Link
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          AppStrings.dontHaveAccount,
                          style: theme.textTheme.bodyMedium,
                        ),
                        TextButton(
                          onPressed: authState.isLoading
                              ? null
                              : () => context.go('/signup'),
                          child: Text(
                            AppStrings.signUp,
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
