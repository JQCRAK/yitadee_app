import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/app_theme.dart';
import '../../widgets/auth_widgets.dart';
import '../../services/user_service.dart';
import '../main_screen.dart';
import '../../services/notification_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
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

  Future<void> _login() async {
    final email    = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email (e.g. you@gmail.com).');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email, password: password,
      );

      // Load profile from Firestore and save to cache
      await UserService.instance.loadFromFirestore();
      await NotificationService.instance.init();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _authError(e.code));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _authError(String code) {
    switch (code) {
      case 'user-not-found':     return 'No account found with this email.';
      case 'wrong-password':     return 'Incorrect password.';
      case 'invalid-email':      return 'Invalid email address.';
      case 'invalid-credential': return 'Invalid email or password.';
      case 'too-many-requests':  return 'Too many attempts. Try again later.';
      default:                   return 'Something went wrong. Try again.';
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size       = MediaQuery.of(context).size;
    final isSmall    = size.height < 680;
    final logoHeight = isSmall ? 80.0 : size.height * 0.14;
    final topPad     = isSmall ? 24.0 : 48.0;
    final midPad     = isSmall ? 24.0 : 44.0;
    final hPad       = size.width * 0.07;

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
                    SizedBox(height: topPad),

                    Center(
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/images/got_it_made_logo.png',
                            height: logoHeight,
                            fit:    BoxFit.contain,
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width:  40,
                            height: 2,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.accent,
                                  AppColors.primary,
                                  AppColors.accent,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: midPad),

                    RichText(
                      text: const TextSpan(
                        children: [
                          TextSpan(
                            text: 'Welcome\n',
                            style: TextStyle(
                              color:      AppColors.textPrimary,
                              fontSize:   28,
                              fontWeight: FontWeight.w900,
                              height:     1.1,
                            ),
                          ),
                          TextSpan(
                            text: 'back.',
                            style: TextStyle(
                              color:      AppColors.primary,
                              fontSize:   28,
                              fontWeight: FontWeight.w900,
                              height:     1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sign in to access your music',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),

                    const SizedBox(height: 28),

                    AuthField(
                      controller:   _emailController,
                      hint:         'Email address',
                      icon:         Icons.alternate_email_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),

                    AuthField(
                      controller: _passwordController,
                      hint:       'Password',
                      icon:       Icons.lock_outline_rounded,
                      obscure:    _obscure,
                      suffix: GestureDetector(
                        onTap: () =>
                            setState(() => _obscure = !_obscure),
                        child: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppColors.textSecondary,
                          size:  20,
                        ),
                      ),
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
                      label:     'Sign In',
                      isLoading: _isLoading,
                      onTap:     _login,
                    ),

                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                            child: Container(
                                height: 1,
                                color:  AppColors.surfaceLight)),
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or',
                              style: TextStyle(
                                  color:    AppColors.textSecondary,
                                  fontSize: 12)),
                        ),
                        Expanded(
                            child: Container(
                                height: 1,
                                color:  AppColors.surfaceLight)),
                      ],
                    ),

                    const SizedBox(height: 24),

                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RegisterScreen()),
                        ),
                        child: RichText(
                          text: const TextSpan(
                            children: [
                              TextSpan(
                                text: "New to Got It Made? ",
                                style: TextStyle(
                                    color:    AppColors.textSecondary,
                                    fontSize: 13),
                              ),
                              TextSpan(
                                text: 'Create account',
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