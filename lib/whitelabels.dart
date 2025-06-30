import 'package:floaty/features/api/models/definitions.dart';
import 'package:floaty/features/api/repositories/fpapi.dart';
import 'package:floaty/settings.dart';
import 'package:get_it/get_it.dart';

final Whitelabels whitelabels = GetIt.I<Whitelabels>();

class Whitelabels {
  List<WhiteLabel> whitelabelsList = [
    WhiteLabel(
      name: "Floatplane",
      friendlyName: "floatplane",
      domain: 'floatplane.com',
      logoPath: "assets/whitelabels_logos/floatplane.png",
      apiUrl: "https://www.floatplane.com/api",
      chatUrl: "https://chat.floatplane.com",
      cookieName: "sails.sid",
      format: "hls.mpegts",
      sort: 0,
      features: ['live', 'chat'],
    ),
    WhiteLabel(
      name: 'Sauce+',
      friendlyName: 'sauceplus',
      domain: 'sauceplus.com',
      logoPath: 'assets/whitelabels_logos/sauceplus.png',
      apiUrl: 'https://www.sauceplus.com/api',
      cookieName: '__Host-sp-sess',
      format: 'hls.mpegts',
      sort: 1,
      features: ['freeSubscriptions', 'unifiedSubscription'],
    ),
  ];

  WhiteLabel getWhitelabel(String name) {
    return whitelabelsList.firstWhere(
      (whitelabel) => whitelabel.friendlyName == name,
      orElse: () => whitelabelsList.reduce((a, b) => a.sort < b.sort ? a : b),
    );
  }

  List<WhiteLabel> getWhitelabels() {
    return whitelabelsList;
  }

  Future<WhiteLabel> getSelectedWhitelabel() async {
    final selectedName = await settings.getKey('whitelabel');
    return whitelabelsList.firstWhere(
      (whitelabel) => whitelabel.friendlyName == selectedName,
      orElse: () => whitelabelsList.reduce((a, b) => a.sort < b.sort ? a : b),
    );
  }

  Future<String> getSelectedWhitelabelNameWithUnified() async {
    final selectedName = await settings.getKey('whitelabel');
    final unified = await settings.getBool('unified');
    if (unified) {
      return 'unified';
    }
    return selectedName;
  }

  Future<bool> toggleUnifiedView() async {
    final unified = await settings.toggleBool('unified');
    return unified;
  }

  Future<WhiteLabel?> get2faWhitelabel() async {
    for (var whitelabel in whitelabelsList) {
      final bool twoFARequired =
          await settings.getBool('${whitelabel.friendlyName}-2faRequired');
      if (twoFARequired) {
        return whitelabel;
      } else {
        continue;
      }
    }
    return null;
  }

  Future<List<String>> getLoggedInLabels() async {
    final labels = await settings.getKey('LoggedInLabels');
    return labels.toString().split(',');
  }

  Future<List<WhiteLabelWithUser>> getLoggedInUsers() async {
    final labels = await getLoggedInLabels();
    final users = <WhiteLabelWithUser>[];
    for (var label in labels) {
      final user = await fpApiRequests.getUserNOS(label.split(',')[0]);
      final whitelabel = getWhitelabel(label.split(',')[0]);
      users.add(WhiteLabelWithUser(
        whitelabel: whitelabel,
        friendlyName: whitelabel.friendlyName,
        rawName: label,
        user: user,
      ));
    }
    return users;
  }

  Future<void> addLoggedInLabel(String label) async {
    var labels = await getLoggedInLabels();
    labels.add(label);
    final labelsString = labels.join(',');
    await settings.setKey('LoggedInLabels', labelsString);
  }

  Future<void> removeLoggedInLabel(String label) async {
    var labels = await getLoggedInLabels();
    labels.remove(label);
    final labelsString = labels.join(',');
    await settings.setKey('LoggedInLabels', labelsString);
  }
}

class WhiteLabel {
  final String name;
  final String friendlyName;
  final String domain;
  final String logoPath;
  final String apiUrl;
  final String? chatUrl;
  final String cookieName;
  final String format;
  final int sort;
  final List<String> features;

  WhiteLabel({
    required this.name,
    required this.friendlyName,
    required this.domain,
    required this.logoPath,
    required this.apiUrl,
    required this.cookieName,
    required this.format,
    required this.sort,
    required this.features,
    this.chatUrl,
  });
}

class WhiteLabelWithUser {
  final WhiteLabel whitelabel;
  final String friendlyName;
  final String rawName;
  final UserSelfV3Response user;

  WhiteLabelWithUser({
    required this.whitelabel,
    required this.friendlyName,
    required this.rawName,
    required this.user,
  });
}
