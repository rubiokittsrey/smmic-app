import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smmic/main.dart';
import 'package:smmic/pages/register.dart';
import 'package:smmic/providers/auth_provider.dart';
import 'package:smmic/services/auth_services.dart';
import 'package:smmic/subcomponents/login/mybutton.dart';
import 'package:smmic/subcomponents/login/textfield.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  // controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // services
  final AuthService _authService = AuthService();

  bool obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onSubmitForm(BuildContext context) async {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();
      await _authService.login(
          email: _emailController.text, password: _passwordController.text);
      if (context.mounted) {
        context.read<AuthProvider>().init();
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const AuthGate()),
            (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Image(
            image: AssetImage('assets/background.jpg'),
            fit: BoxFit.cover,
            opacity: AlwaysStoppedAnimation(0.5),
          ),
          SafeArea(
              child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 35),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    //color: Colors.blue,
                    alignment: Alignment.centerLeft,
                    height: (25 / 100) * screenHeight,
                    child: _headers(),
                  ),
                  SizedBox(
                    //color: Colors.yellow,
                    height: (58 / 100) * screenHeight,
                    child: Form(
                        key: _formKey,
                        child: _form(_emailController, _passwordController)),
                  ),
                  Container(
                    //color: Colors.orange,
                    alignment: Alignment.bottomCenter,
                    height: (13 / 100) * screenHeight,
                    child: _footer(),
                  )
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _headers() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // TODO: ASSIGN STYLES FROM THEME PROVIDER
        Text('Login',
            style: TextStyle(
                fontSize: 60,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        Text('Enter your email and password to continue',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Colors.white)),
      ],
    );
  }

  Widget _form(TextEditingController emailController,
      TextEditingController passwordController) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        MyTextField(
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your email';
            } else if (!EmailValidator.validate(value)) {
              return 'Please enter a valid email address';
            }
            return null;
          },
          controller: emailController,
          hintText: 'Email',
          obscureText: false,
          suffixIcon: const Padding(
              padding: EdgeInsets.only(right: 15), child: Icon(Icons.person)),
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 10),
        MyTextField(
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your password';
            }
            return null;
          },
          controller: passwordController,
          hintText: 'Password',
          obscureText: obscurePassword,
          suffixIcon: Padding(
              padding: const EdgeInsets.all(8.0),
              child: IconButton(
                  onPressed: () {
                    setState(() {
                      obscurePassword = !obscurePassword;
                    });
                  },
                  color: Colors.black.withOpacity(0.7),
                  icon: Icon(obscurePassword
                      ? Icons.visibility_off
                      : Icons.visibility))),
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {},
            child: const Text(
              'Forgot Password',
              style: TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                  fontSize: 11),
            ),
          ),
        ),
        const SizedBox(height: 25),
        Align(
            alignment: Alignment.centerRight,
            child: MyButton(
              onTap: () async {
                await _onSubmitForm(context);
              },
              textColor: const Color.fromRGBO(194, 161, 98, 1),
              text: 'Login',
            )),
        const SizedBox(height: 100)
      ],
    );
  }

  Widget _footer() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
            context, MaterialPageRoute(builder: (context) => const Register()));
      },
      child: Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: RichText(
            text: const TextSpan(
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                    color: Colors.white),
                text: 'Don\'t have an account?',
                children: [
                  TextSpan(
                    text: ' Sign Up',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  )
                ]),
          )),
    );
  }
}
