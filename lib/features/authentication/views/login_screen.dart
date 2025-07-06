import 'dart:io';

import 'package:floaty/features/api/repositories/fpapi.dart';
import 'package:floaty/whitelabels.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:floaty/shared/components/switcher.dart';
import 'package:flutter/services.dart';

class LoginManager {
  Future login(String username, String password, BuildContext context,
      Function needstwofa, Function logincomplete,
      {WhiteLabel? whitelabel, bool optionalTwoFA = false}) async {
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    TextTheme textTheme = Theme.of(context).textTheme;
    Map<String, dynamic> response;
    WhiteLabel whiteLabel;
    if (whitelabel == null) {
      whiteLabel = await whitelabels.getSelectedWhitelabel();
    } else {
      whiteLabel = whitelabel;
    }
    if (username.isNotEmpty || password.isNotEmpty) {
      response = await fpApiRequests.login(
          username, password, whiteLabel.friendlyName,
          optionalTwoFA: optionalTwoFA);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            closeIconColor: Colors.white,
            content: Center(
                child: Text('Please enter both Password and username.',
                    style: textTheme.bodyLarge)),
            backgroundColor: colorScheme.surfaceContainer,
          ),
        );
        return;
      }
      return;
    }
    if (response['needs2FA'] == true) {
      needstwofa();
      return;
    }
    if (response.containsKey('message')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            closeIconColor: Colors.white,
            content: Center(
                child: Text(response['message'], style: textTheme.bodyLarge)),
            backgroundColor: colorScheme.surfaceContainer,
          ),
        );
        return;
      }
    }
    logincomplete();
    return;
  }

  Future twofa(String code, WhiteLabel labelthatneeds2fa, BuildContext context,
      Function twofacomplete,
      {bool optionalTwoFA = false}) async {
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    TextTheme textTheme = Theme.of(context).textTheme;
    Map<String, dynamic> response;
    if (code.isNotEmpty) {
      response = await fpApiRequests.twofa(code, labelthatneeds2fa.friendlyName,
          optionalTwoFA: optionalTwoFA);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            closeIconColor: Colors.white,
            content: Center(
                child:
                    Text('Please enter 2fa code.', style: textTheme.bodyLarge)),
            backgroundColor: colorScheme.surfaceContainer,
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
                child: Text(response['message'], style: textTheme.bodyLarge)),
            backgroundColor: colorScheme.surfaceContainer,
          ),
        );
        return;
      }
    }
    if (response['needs2FA'] == true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            closeIconColor: Colors.white,
            content: Center(
                child: Text('An Unknown Error has occured. Please try again.',
                    style: textTheme.bodyLarge)),
            backgroundColor: colorScheme.surfaceContainer,
          ),
        );
        return;
      }
    }
    twofacomplete();
    return;
  }
}

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
      final captchaResponse = await fpApiRequests
          .captcha((await whitelabels.getSelectedWhitelabel()).friendlyName);
      sitekey = captchaResponse['turnstile']['variants']['managed']['siteKey'];
      setState(() {
        turnstileLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: colorScheme.surface,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 16),
                            Image.asset(
                              'assets/app_foreground.png',
                              width: 80,
                              height: 80,
                              filterQuality: FilterQuality.high,
                            ),
                            const SizedBox(height: 32),
                            Text(
                              'Welcome to Floaty',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            LoginFields(
                              usernameController: _usernameController,
                              passwordController: _passwordController,
                              onSubmitted: (String username,
                                  String password,
                                  BuildContext context,
                                  Function needstwofa,
                                  Function logincomplete) {
                                LoginManager().login(username, password,
                                    context, needstwofa, logincomplete);
                              },
                              needstwofa: () {
                                if (context.mounted) {
                                  context.pushReplacement('/2fa');
                                }
                              },
                              logincomplete: () {
                                if (context.mounted) {
                                  context.pushReplacement('/home');
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Switcher(
                      onSwitch: (String value) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 5),
                              showCloseIcon: true,
                              content: Text(
                                'After you complete login you can sign into the other service and you will get the options of viewing each service individually or to get a unified view.',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                            ),
                          );
                        }
                      },
                      whitelabels: whitelabels.getWhitelabels(),
                    ),
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 3,
              margin: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 16),
                          Image.asset(
                            'assets/app_foreground.png',
                            width: 80,
                            height: 80,
                            filterQuality: FilterQuality.high,
                          ),
                          const SizedBox(height: 32),
                          Text(
                            'Enter 2FA Code',
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TwoFAFields(
                            whitelabel: labelthatneeds2fa,
                            twofaCodeController: twofaCodeController,
                            twofa: (String code,
                                    WhiteLabel whitelabel,
                                    BuildContext context,
                                    Function twofacomplete) async =>
                                await LoginManager().twofa(
                                    code, whitelabel, context, twofacomplete),
                            twofacomplete: () {
                              if (context.mounted) {
                                context.pushReplacement('/home');
                              }
                            },
                          ),
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

class LoginFields extends StatelessWidget {
  const LoginFields({
    required this.passwordController,
    required this.usernameController,
    required this.onSubmitted,
    required this.needstwofa,
    required this.logincomplete,
    super.key,
  });

  final TextEditingController passwordController;
  final TextEditingController usernameController;
  final Function(String, String, BuildContext, Function, Function) onSubmitted;
  final Function() needstwofa;
  final Function() logincomplete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: usernameController,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: true,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          decoration: InputDecoration(
            labelText: 'Email',
            hintText: 'Enter your email',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: passwordController,
          textInputAction: TextInputAction.done,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => onSubmitted(
            usernameController.text,
            passwordController.text,
            context,
            needstwofa,
            logincomplete,
          ),
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: 'Enter your password',
            border: const OutlineInputBorder(),
          ),
        ),
        // const SizedBox(height: 20),
        // if (!Platform.isLinux && turnstileLoaded)
        //   Center(
        //       child: ClourdflareTurnstile(
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
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => onSubmitted(
            usernameController.text,
            passwordController.text,
            context,
            needstwofa,
            logincomplete,
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            textStyle: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          child: const Text('Sign In'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class TwoFAFields extends StatelessWidget {
  const TwoFAFields({
    required this.whitelabel,
    required this.twofaCodeController,
    required this.twofa,
    required this.twofacomplete,
    super.key,
  });

  final TextEditingController twofaCodeController;
  final Function(String, WhiteLabel, BuildContext, Function) twofa;
  final Function() twofacomplete;
  final WhiteLabel whitelabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: twofaCodeController,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) =>
              twofa(value, whitelabel, context, twofacomplete),
          decoration: InputDecoration(
            labelText: 'Verification Code',
            hintText: 'Enter 6-digit code',
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => twofa(
              twofaCodeController.text, whitelabel, context, twofacomplete),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            textStyle: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          child: const Text('Verify Code'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
