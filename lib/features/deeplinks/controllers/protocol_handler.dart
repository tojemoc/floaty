import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class ProtocolHandler {
  static const String protocol = 'floaty';

  // Private constructor to prevent instantiation
  ProtocolHandler._();

  static Future<void> register() async {
    if (kIsWeb) return; // Skip for web

    if (Platform.isWindows) {
      await _registerWindows();
    } else if (Platform.isMacOS) {
      await _registerMacOS();
    } else if (Platform.isLinux) {
      await _registerLinux();
    }
  }

  static Future<void> _registerWindows() async {
    try {
      final exePath = Platform.resolvedExecutable.replaceAll('\\', '\\\\');
      debugPrint('Registering protocol handler with executable path: $exePath');

      // Create a .reg file content
      final regContent = '''
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\Classes\\$protocol]
@="URL:$protocol Protocol"
"URL Protocol"=""

[HKEY_CURRENT_USER\\Software\\Classes\\$protocol\\shell]

[HKEY_CURRENT_USER\\Software\\Classes\\$protocol\\shell\\open]

[HKEY_CURRENT_USER\\Software\\Classes\\$protocol\\shell\\open\\command]
@=""$exePath" "%1""

[HKEY_CURRENT_USER\\Software\\$protocol]

[HKEY_CURRENT_USER\\Software\\$protocol\\Capabilities]
"ApplicationName"="Floaty"
"ApplicationDescription"="Floaty Desktop Client"

[HKEY_CURRENT_USER\\Software\\$protocol\\Capabilities\\URLAssociations]
"$protocol"="$protocol"

[HKEY_CURRENT_USER\\Software\\RegisteredApplications]
"Floaty"="Software\\\\$protocol\\\\Capabilities"

[HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\Shell\\Associations\\UrlAssociations\\$protocol]
"ProgId"="$protocol"
"ApplicationName"="Floaty"
''';

      debugPrint('Registry file content:');
      debugPrint(regContent);

      // Create a temporary .reg file
      final tempDir = await Directory.systemTemp.createTemp('floaty_protocol');
      final regFile = File('${tempDir.path}\\register_$protocol.reg');
      await regFile.writeAsString(regContent);

      // Import the .reg file using reg.exe
      final result = await Process.run('reg', ['import', regFile.path]);

      if (result.exitCode != 0) {
        throw Exception('Failed to register protocol: ${result.stderr}');
      }

      debugPrint(
          'Successfully registered $protocol:// protocol handler (current user)');

      // Clean up
      try {
        await regFile.delete();
        await tempDir.delete(recursive: true);
      } catch (e) {
        debugPrint('Failed to clean up temporary files: $e');
      }
    } catch (e) {
      debugPrint('Failed to register protocol on Windows: $e');
      rethrow;
    }
  }

  static Future<void> _registerMacOS() async {
    try {
      // On macOS, protocol handling is configured in Info.plist
      // We just need to ensure the app is set as the default handler
      debugPrint('Protocol handling on macOS is configured via Info.plist');

      // Optional: Verify the app is registered as the default handler
      final result = await Process.run('defaults', [
        'read',
        'com.apple.LaunchServices/com.apple.launchservices.secure',
        'LSHandlers'
      ]);
      if (result.exitCode == 0 && result.stdout.toString().contains(protocol)) {
        debugPrint('$protocol: protocol handler is registered on macOS');
      } else {
        debugPrint(
            'Note: $protocol protocol handler may need to be set as default in System Preferences > Default Apps');
      }
    } catch (e) {
      debugPrint('Error checking protocol registration on macOS: $e');
    }
  }

  static Future<void> _registerLinux() async {
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      if (homeDir.isEmpty) {
        debugPrint('Could not determine home directory on Linux');
        return;
      }

      // Check if xdg-utils is available
      final xdgCheck = await Process.run('which', ['xdg-mime']);
      if (xdgCheck.exitCode != 0) {
        debugPrint(
            'xdg-utils not found. Protocol handling might not work properly on this Linux system.');
        return;
      }

      final exePath = Platform.resolvedExecutable;
      final desktopFile = '''
[Desktop Entry]
Type=Application
Name=Floaty
Exec=$exePath %u
MimeType=x-scheme-handler/$protocol;
StartupNotify=true
NoDisplay=true
''';

      final appsDir = path.join(homeDir, '.local', 'share', 'applications');
      await Directory(appsDir).create(recursive: true);

      final desktopFilePath = path.join(appsDir, '$protocol-handler.desktop');
      await File(desktopFilePath).writeAsString(desktopFile);

      // Make the desktop file executable
      final chmodResult = await Process.run('chmod', ['+x', desktopFilePath]);
      if (chmodResult.exitCode != 0) {
        throw Exception(
            'Failed to make desktop file executable: ${chmodResult.stderr}');
      }

      // Register the MIME type
      final xdgResult = await Process.run('xdg-mime', [
        'default',
        '$protocol-handler.desktop',
        'x-scheme-handler/$protocol'
      ]);

      if (xdgResult.exitCode != 0) {
        throw Exception('Failed to register MIME type: ${xdgResult.stderr}');
      }

      final updateResult =
          await Process.run('update-desktop-database', [appsDir]);
      if (updateResult.exitCode != 0) {
        throw Exception(
            'Failed to update desktop database: ${updateResult.stderr}');
      }

      debugPrint(
          'Successfully registered $protocol:// protocol handler on Linux');
    } catch (e) {
      debugPrint('Failed to register protocol on Linux: $e');
    }
  }
}
