import 'dart:io';

import 'package:floaty/whitelabels.dart';
import 'package:flutter/material.dart';
import 'package:floaty/features/authentication/repositories/login_api.dart';
import 'package:go_router/go_router.dart';
import 'package:floaty/shared/widgets/switcher.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool turnstileLoaded = false;
  String? sitekey;
  String? token;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    if (!Platform.isLinux) {
      final captchaResponse = await loginApi
          .captcha((await whitelabels.getSelectedWhitelabel()).friendlyName);
      sitekey = captchaResponse['turnstile']['variants']['managed']['siteKey'];
      setState(() {
        turnstileLoaded = true;
      });
    }
  }

  Future login(String username, String password, BuildContext context) async {
    Map<String, dynamic> response;
    final whiteLabel = await whitelabels.getSelectedWhitelabel();
    if (username.isNotEmpty || password.isNotEmpty) {
      response =
          await loginApi.login(username, password, whiteLabel.friendlyName);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            closeIconColor: Colors.white,
            content: const Center(
                child: Text('Please enter both Password and username.',
                    style: TextStyle(color: Colors.white))),
            backgroundColor: Colors.black.withValues(alpha: 0.4),
          ),
        );
      }
      return;
    }
    if (response['needs2FA'] == true) {
      if (context.mounted) {
        context.pushReplacement('/2fa');
      }
    }
    if (response.containsKey('message')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            closeIconColor: Colors.white,
            content: Center(
                child: Text(response['message'],
                    style: const TextStyle(color: Colors.white))),
            backgroundColor: Colors.black.withValues(alpha: 0.4),
          ),
        );
      }
    }
    if (context.mounted) {
      context.pushReplacement('/home');
    }
    return;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0d47a1),
              Color(0xFF1976d2),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 350,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Image(
                        image: AssetImage('assets/app_foreground.png'),
                        width: 60,
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        'Welcome to Floaty',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: 300,
                        child: TextField(
                          controller: _usernameController,
                          style: const TextStyle(color: Colors.white),
                          onSubmitted: (String value) {
                            login(value, _passwordController.text, context);
                          },
                          decoration: InputDecoration(
                            labelText: 'Email',
                            labelStyle: const TextStyle(color: Colors.white),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: 300,
                        child: TextField(
                          controller: _passwordController,
                          style: const TextStyle(color: Colors.white),
                          onSubmitted: (String value) {
                            login(_usernameController.text, value, context);
                          },
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: const TextStyle(color: Colors.white),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          obscureText: true,
                        ),
                      ),
                      // const SizedBox(height: 20),
                      // if (!Platform.isLinux && turnstileLoaded)
                      //   Center(
                      //       child: CloudflareTurnstile(
                      //     siteKey: sitekey!,
                      //     options: options,
                      //     baseUrl: 'https://www.floatplane.com/',
                      //     onTokenReceived: (String token) {
                      //       this.token = token;
                      //     },
                      //     onTokenExpired: () {
                      //       token = null;
                      //       if (context.mounted) {
                      //         ScaffoldMessenger.of(context).showSnackBar(
                      //           SnackBar(
                      //             showCloseIcon: true,
                      //             closeIconColor: Colors.white,
                      //             content: const Center(
                      //                 child: Text('Turnstile Token Expired',
                      //                     style:
                      //                         TextStyle(color: Colors.white))),
                      //             backgroundColor:
                      //                 Colors.black.withValues(alpha: 0.4),
                      //           ),
                      //         );
                      //       }
                      //     },
                      //     onError: (TurnstileException e) {
                      //       token = null;
                      //       if (context.mounted) {
                      //         ScaffoldMessenger.of(context).showSnackBar(
                      //           SnackBar(
                      //             showCloseIcon: true,
                      //             closeIconColor: Colors.white,
                      //             content: Center(
                      //                 child: Text(
                      //                     'Turnstile Error: ${e.message}',
                      //                     style: const TextStyle(
                      //                         color: Colors.white))),
                      //             backgroundColor:
                      //                 Colors.black.withValues(alpha: 0.4),
                      //           ),
                      //         );
                      //       }
                      //     },
                      //   )),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: 300,
                        child: ElevatedButton(
                          onPressed: () {
                            login(_usernameController.text,
                                _passwordController.text, context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1e88e5),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Login',
                            style: TextStyle(fontSize: 18, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Switcher(
                    onSwitch: (String value) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 5),
                            showCloseIcon: true,
                            closeIconColor: Colors.white,
                            content: Center(
                                child: Text(
                                    'After you complete login you can sign into the other service and you will get the options of viewing each service indivdually or to get a unified view.',
                                    style:
                                        const TextStyle(color: Colors.white))),
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.4),
                          ),
                        );
                      }
                    },
                    whitelabels: whitelabels.getWhitelabels()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TwoFaScreen extends StatefulWidget {
  const TwoFaScreen({super.key});

  @override
  State<TwoFaScreen> createState() => _TwoFaScreenState();
}

class _TwoFaScreenState extends State<TwoFaScreen> {
  final TextEditingController twofaCodeController = TextEditingController();
  late WhiteLabel labelthatneeds2fa;
  bool isLoading = false;
  bool turnstileLoaded = false;
  String? sitekey;
  String? token;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    final whiteLabel = await whitelabels.get2faWhitelabel();
    if (whiteLabel != null) {
      labelthatneeds2fa = whiteLabel;
    }
    setState(() {
      isLoading = false;
    });
  }

  Future twofa(String code, BuildContext context) async {
    Map<String, dynamic> response;
    if (code.isNotEmpty) {
      response = await loginApi.twofa(code, labelthatneeds2fa.friendlyName);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            closeIconColor: Colors.white,
            content: const Center(
                child: Text('Please enter 2fa code.',
                    style: TextStyle(color: Colors.white))),
            backgroundColor: Colors.black.withValues(alpha: 0.4),
          ),
        );
      }
      return;
    }
    if (response.containsKey('message')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            closeIconColor: Colors.white,
            content: Center(
                child: Text(response['message'],
                    style: const TextStyle(color: Colors.white))),
            backgroundColor: Colors.black.withValues(alpha: 0.4),
          ),
        );
      }
    }
    if (response['needs2FA'] == true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            closeIconColor: Colors.white,
            content: const Center(
                child: Text('An Unknown Error has occured. Please try again.',
                    style: TextStyle(color: Colors.white))),
            backgroundColor: Colors.black.withValues(alpha: 0.4),
          ),
        );
      }
    }

    if (context.mounted) {
      context.pushReplacement('/home');
    }
    return;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0d47a1),
              Color(0xFF1976d2),
            ],
          ),
        ),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: SingleChildScrollView(
                  child: Container(
                    width: 350,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Image(
                          image: AssetImage('assets/app_foreground.png'),
                          width: 60,
                        ),
                        const SizedBox(height: 30),
                        const Text(
                          'Enter 2FA Code',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: 300,
                          child: TextField(
                            controller: twofaCodeController,
                            style: const TextStyle(color: Colors.white),
                            onSubmitted: (String value) {
                              twofa(value, context);
                            },
                            decoration: InputDecoration(
                              labelText: 'Code',
                              labelStyle: const TextStyle(color: Colors.white),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: 300,
                          child: ElevatedButton(
                            onPressed: () async {
                              twofa(twofaCodeController.text, context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1e88e5),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Login',
                              style:
                                  TextStyle(fontSize: 18, color: Colors.white),
                            ),
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
