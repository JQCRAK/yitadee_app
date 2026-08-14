import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/app_theme.dart';
import '../../widgets/auth_widgets.dart';
import '../../services/user_service.dart';
import '../main_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController  = TextEditingController();
  bool _isLoading = false;
  bool _obscure   = true;
  String? _error;

  late AnimationController _animController;
  late Animation<double>  _fadeAnim;
  late Animation<Offset>  _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(
        parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end:   Offset.zero,
    ).animate(CurvedAnimation(
        parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  bool _isValidEmail(String email) {
    final regex =
        RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');
    return regex.hasMatch(email.trim());
  }

  bool _isValidUsername(String username) {
    if (username.contains(' ')) return false;
    final regex = RegExp(r'^[a-zA-Z0-9]{3,20}$');
    return regex.hasMatch(username.trim());
  }

  String _passwordStrengthMessage(String password) {
    if (password.isEmpty)    return '';
    if (password.length < 6) return 'Too short (min 6 characters).';
    if (password.length < 8) return 'Weak — add numbers or symbols.';
    final hasUpper  = password.contains(RegExp(r'[A-Z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));
    final hasSymbol =
        password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));
    if (hasUpper && hasNumber && hasSymbol) return '';
    if (hasNumber && hasUpper) {
      return 'Good — add a symbol for stronger security.';
    }
    return 'Fair — add uppercase letters and numbers.';
  }

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final email    = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm  = _confirmController.text;

    if (username.isEmpty || email.isEmpty ||
        password.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (!_isValidUsername(username)) {
      setState(() => _error =
          'Username: 3–20 characters, letters and numbers only. No spaces or symbols.');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() =>
          _error = 'Enter a valid email (e.g. you@gmail.com).');
      return;
    }
    if (password.length < 6) {
      setState(
          () => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      // Check if username is already taken
      final usernameQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username.toLowerCase())
          .limit(1)
          .get();

      if (usernameQuery.docs.isNotEmpty) {
        setState(() => _error =
            'Username "@$username" is already taken. Choose another.');
        return;
      }

      // Create account in Firebase Auth
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
              email: email, password: password);

      // Save profile in Firestore — role defaults to "user"
      // To grant admin access, manually change role to "admin" in Firebase Console
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'username':    username.toLowerCase(),
        'displayName': username,
        'email':       email,
        'photoUrl':    '',
        'role':        'user',   // ← NEW: default role for all new users
        'createdAt':   FieldValue.serverTimestamp(),
        'locker':      [],
        'favorites':   [],
      });

      await credential.user!.updateDisplayName(username);

      // Load profile into cache immediately after register
      await UserService.instance.loadFromFirestore();

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _authError(e.code));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _authError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered. Try signing in.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-email':
        return 'Invalid email address.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size       = MediaQuery.of(context).size;
    final isSmall    = size.height < 680;
    final logoHeight = isSmall ? 60.0 : 90.0;
    final hPad       = size.width * 0.07;
    final strengthMsg =
        _passwordStrengthMessage(_passwordController.text);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AuthBackground(
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // Back button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width:  38,
                        height: 38,
                        decoration: BoxDecoration(
                          color:        AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.surfaceLight,
                              width: 1),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: AppColors.primary,
                          size:  17,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Center(
                      child: Image.asset(
                        'assets/images/got_it_made_logo.png',
                        height: logoHeight,
                        fit:    BoxFit.contain,
                      ),
                    ),

                    const SizedBox(height: 20),

                    RichText(
                      text: const TextSpan(
                        children: [
                          TextSpan(
                            text: 'Join the\n',
                            style: TextStyle(
                              color:      AppColors.textPrimary,
                              fontSize:   26,
                              fontWeight: FontWeight.w900,
                              height:     1.15,
                            ),
                          ),
                          TextSpan(
                            text: 'community.',
                            style: TextStyle(
                              color:      AppColors.primary,
                              fontSize:   26,
                              fontWeight: FontWeight.w900,
                              height:     1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Create your YITADEE!!! account',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13),
                    ),

                    const SizedBox(height: 20),

                    AuthField(
                      controller: _usernameController,
                      hint:       'Username (e.g. yitadeefan23)',
                      icon:       Icons.alternate_email_rounded,
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      '3–20 characters · letters and numbers only',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11),
                    ),

                    const SizedBox(height: 10),

                    AuthField(
                      controller:   _emailController,
                      hint:         'Email address',
                      icon:         Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),

                    const SizedBox(height: 10),

                    StatefulBuilder(
                      builder: (context, setInner) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AuthField(
                            controller: _passwordController,
                            hint:       'Password',
                            icon:       Icons.lock_outline_rounded,
                            obscure:    _obscure,
                            suffix: GestureDetector(
                              onTap: () => setState(() => _obscure = !_obscure),
                              child: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppColors.textSecondary,
                                size:  20,
                              ),
                            ),
                          ),
                          if (strengthMsg.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              strengthMsg,
                              style: TextStyle(
                                fontSize: 11,
                                color: strengthMsg.contains('Good')
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    AuthField(
                      controller: _confirmController,
                      hint:       'Confirm password',
                      icon:       Icons.lock_outline_rounded,
                      obscure:    true,
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 24),

                    GoldButton(
                      label:     'Create Account',
                      isLoading: _isLoading,
                      onTap:     _register,
                    ),

                    const SizedBox(height: 20),

                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: RichText(
                          text: const TextSpan(
                            children: [
                              TextSpan(
                                text: 'Already have an account? ',
                                style: TextStyle(
                                    color:    AppColors.textSecondary,
                                    fontSize: 13),
                              ),
                              TextSpan(
                                text: 'Sign In',
                                style: TextStyle(
                                  color:      AppColors.primary,
                                  fontSize:   13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}