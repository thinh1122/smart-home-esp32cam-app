import 'package:flutter/material.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../main_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  bool _obscure     = true;
  bool _loading     = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final err = await AuthService.instance.login(
      _emailCtrl.text.trim(),
      _passCtrl.text,
    );

    if (!mounted) return;
    if (err != null) {
      setState(() { _loading = false; _error = err; });
    } else {
      setState(() { _loading = false; });
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                // Logo / icon
                Center(
                  child: Container(
                    width: 80, height: 80,
                    decoration: AppDecor.accentGlow(radius: 24),
                    child: const Icon(Icons.home_rounded, color: Colors.white, size: 42),
                  ),
                ),
                const SizedBox(height: 28),
                Center(
                  child: Text('Smart Home',
                    style: Theme.of(context).textTheme.headlineMedium),
                ),
                Center(
                  child: Text('Đăng nhập để tiếp tục',
                    style: Theme.of(context).textTheme.bodyMedium),
                ),
                const SizedBox(height: 40),

                // Email
                _label('Email'),
                const SizedBox(height: 8),
                _inputField(
                  controller: _emailCtrl,
                  hint: 'your@email.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Nhập email';
                    if (!v.contains('@')) return 'Email không hợp lệ';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Password
                _label('Mật khẩu'),
                const SizedBox(height: 8),
                _inputField(
                  controller: _passCtrl,
                  hint: '••••••••',
                  icon: Icons.lock_outline,
                  obscure: _obscure,
                  suffix: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: ac.textSecondary, size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Nhập mật khẩu';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Error message
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: ac.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ac.error.withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      Icon(Icons.error_outline, color: ac.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!,
                          style: TextStyle(color: ac.error, fontSize: 13))),
                    ]),
                  ),
                ],

                const SizedBox(height: 32),

                // Login button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ac.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white))
                        : const Text('Đăng nhập',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 24),

                // Go to register
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Chưa có tài khoản? ',
                      style: Theme.of(context).textTheme.bodyMedium),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    child: Text('Đăng ký',
                        style: TextStyle(
                            color: ac.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    final ac = AC.of(context);
    return Text(text,
        style: TextStyle(
            color: ac.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5));
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final ac = AC.of(context);
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(color: ac.textPrimary, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: ac.textDim, fontSize: 14),
        prefixIcon: Icon(icon, color: ac.textSecondary, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: ac.card,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: ac.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: ac.accent, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: ac.error)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: ac.error, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
