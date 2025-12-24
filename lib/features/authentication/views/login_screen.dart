import 'package:floaty/features/authentication/services/oauth2_service.dart';
import 'package:floaty/features/api/repositories/fpapi.dart';
import 'package:floaty/whitelabels.dart';
import 'package:floaty/settings.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:floaty/shared/components/switcher.dart';
import 'package:flutter/services.dart';
import 'package:cookie_jar/cookie_jar.dart';

class LoginManager {
  final OAuth2Service _oauth2Service = OAuth2Service.instance;

  /// Manual cookie login for testing
  Future<void> loginWithCookie(
      BuildContext context, String cookieString, Function logincomplete) async {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    try {
      if (cookieString.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Please enter a cookie.', style: textTheme.bodyLarge),
              backgroundColor: colorScheme.error,
            ),
          );
        }
        return;
      }

      // Store the cookie in the cookie jar
      final whiteLabel = await whitelabels.getSelectedWhitelabel();
      final uri = Uri.parse('https://${whiteLabel.domain}/');

      // Create cookie with far-future expiration (1 year from now)
      // Use the actual domain from the whitelabel (not the URI domain)
      // For multi-subdomain support, we could use .floatplane.com, but for now use exact domain
      final cookie = Cookie(whiteLabel.cookieName, cookieString)
        ..expires = DateTime.now().add(const Duration(days: 365))
        ..domain = whiteLabel.domain // Use the exact domain from whitelabel
        ..path = '/'
        ..httpOnly = true;

      // Save cookie to the domain's URI
      await fpApiRequests.cookieJar.saveFromResponse(
        uri,
        [cookie],
      );

      // Mark this whitelabel as using cookie auth
      await settings.setKey('${whiteLabel.friendlyName}_auth_method', 'cookie');

      await whitelabels
          .addLoggedInLabel('${whiteLabel.friendlyName}-aaaaaaaaaa');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Cookie saved successfully!', style: textTheme.bodyLarge),
            backgroundColor: colorScheme.surfaceContainer,
          ),
        );
      }

      logincomplete();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            closeIconColor: Colors.white,
            content: Text('Cookie error: $e', style: textTheme.bodyLarge),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  /// OAuth2 login flow
  Future<void> loginWithOAuth2(
      BuildContext context, Function logincomplete) async {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    try {
      // Show loading indicator
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 30),
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text('Opening browser for authentication...',
                    style: textTheme.bodyLarge),
              ],
            ),
            backgroundColor: colorScheme.surfaceContainer,
          ),
        );
      }

      final result = await _oauth2Service.login();

      // Clear loading indicator
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }

      if (result.isSuccess && result.accessToken != null) {
        // Get whitelabel info
        final whiteLabel = await whitelabels.getSelectedWhitelabel();

        // Store tokens with whitelabel
        await _oauth2Service.storeTokens(result,
            whitelabel: whiteLabel.friendlyName);

        // Mark as logged in
        final userId = result.userInfo?['sub'] ?? 'oauth2_user';
        await whitelabels
            .addLoggedInLabel('${whiteLabel.friendlyName}-$userId');

        logincomplete();
      } else if (result.isCancelled) {
        // User cancelled authentication
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Authentication was cancelled.',
                  style: textTheme.bodyLarge),
              backgroundColor: colorScheme.surfaceContainer,
            ),
          );
        }
      } else {
        // Authentication failed
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              showCloseIcon: true,
              closeIconColor: Colors.white,
              content: Text(result.error ?? 'OAuth2 authentication failed.',
                  style: textTheme.bodyLarge),
              backgroundColor: colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      // Clear loading indicator
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            closeIconColor: Colors.white,
            content:
                Text('Authentication error: $e', style: textTheme.bodyLarge),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _cookieController = TextEditingController();
  bool _showCookieInput = false;
  String? sitekey;
  String? token;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Feature flag for cookie testing
    const bool useCookieAuth =
        bool.fromEnvironment('USE_COOKIE_AUTH', defaultValue: false);

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
                            Text(
                              'Sign in to access your Floatplane content',
                              style: textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            if (!_showCookieInput) ...[
                              FilledButton.icon(
                                onPressed: () {
                                  LoginManager().loginWithOAuth2(
                                    context,
                                    () {
                                      if (context.mounted) {
                                        context.pushReplacement('/home');
                                      }
                                    },
                                  );
                                },
                                icon: const Icon(Icons.login),
                                label: const Text('Sign In with OAuth2'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(56),
                                  textStyle: textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              if (useCookieAuth) ...[
                                const SizedBox(height: 16),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _showCookieInput = true;
                                    });
                                  },
                                  child: const Text('Use Cookie (Testing)'),
                                ),
                              ],
                            ] else ...[
                              TextField(
                                controller: _cookieController,
                                decoration: const InputDecoration(
                                  labelText: 'Cookie',
                                  hintText: 'Paste sails.sid cookie value',
                                  border: OutlineInputBorder(),
                                  helperText: 'For testing purposes only',
                                ),
                                maxLines: 3,
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () {
                                  LoginManager().loginWithCookie(
                                    context,
                                    _cookieController.text,
                                    () {
                                      if (context.mounted) {
                                        context.pushReplacement('/home');
                                      }
                                    },
                                  );
                                },
                                icon: const Icon(Icons.cookie),
                                label: const Text('Login with Cookie'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(56),
                                  textStyle: textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _showCookieInput = false;
                                  });
                                },
                                child: const Text('Back to OAuth2'),
                              ),
                            ],
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
                                'After you complete login you can sign into the other service and you will get the options of viewing each service individually.',
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

class LoginFields extends StatelessWidget {
  const LoginFields({
    required this.passwordController,
    required this.usernameController,
    required this.onSubmitted,
    required this.needstwofa,
    required this.logincomplete,
    this.onOAuth2Login,
    super.key,
  });

  final TextEditingController passwordController;
  final TextEditingController usernameController;
  final Function(String, String, BuildContext, Function, Function) onSubmitted;
  final Function() needstwofa;
  final Function() logincomplete;
  final Function()? onOAuth2Login;

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
        if (onOAuth2Login != null) ...[
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('or'),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onOAuth2Login,
            icon: const Icon(Icons.login),
            label: const Text('Sign in with OAuth2'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              textStyle: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
