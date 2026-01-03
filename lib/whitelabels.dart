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
      oauthconfigurl:
          "https://auth.floatplane.com/realms/floatplane/.well-known/openid-configuration",
      sort: 0,
      features: ['live', 'downloads'],
    ),

    //TODO: RETURN SAUCE+ WHEN OAUTH IS ADDED.

    // WhiteLabel(
    //   name: 'Sauce+',
    //   friendlyName: 'sauceplus',
    //   domain: 'sauceplus.com',
    //   logoPath: 'assets/whitelabels_logos/sauceplus.png',
    //   apiUrl: 'https://www.sauceplus.com/api',
    //   cookieName: '__Host-sp-sess',
    //   format: 'hls.mpegts',
    //   oauthconfigurl:
    //       "https://auth.sauceplus.com/realms/sauceplus/.well-known/openid-configuration",
    //   sort: 1,
    //   features: ['freeSubscriptions', 'unifiedSubscription'],
    // ),
    // WhiteLabel(
    //   name: "Floatplane Pre-Prod",
    //   friendlyName: "floatplanepp",
    //   domain: 'pp.floatplane.com',
    //   logoPath: "assets/whitelabels_logos/floatplanepp.png",
    //   apiUrl: "https://pp.floatplane.com/api",
    //   chatUrl: "https://chat.floatplane.com",
    //   cookieName: "sails.sid.preprod",
    //   format: "hls.mpegts",
    //   oauthconfigurl: "https://auth.floatplane.com/realms/floatplane-pp/.well-known/openid-configuration",
    //   sort: 2,
    //   features: ['live'],
    // ),
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
    return labels.toString().split(',').where((e) => e.isNotEmpty).toList();
  }

  Future<List<WhiteLabelWithUser>> getLabelsAndUsers() async {
    final labels = getWhitelabels();
    final loggedInLabels = await getLoggedInLabels();
    final users = <WhiteLabelWithUser>[];
    for (var label in labels) {
      UserSelfV3Response? user;
      final loggedInLabel = loggedInLabels.firstWhere(
          (element) => element.split('-')[0] == label.friendlyName,
          orElse: () => '');
      if (loggedInLabel.isNotEmpty) {
        user = await fpApiRequests.getUserNOS(label.friendlyName);
      }
      users.add(WhiteLabelWithUser(
        loggedin: loggedInLabel.isNotEmpty,
        name: label.name,
        friendlyName: label.friendlyName,
        rawName: loggedInLabel,
        user: user,
        whitelabel: label,
      ));
    }
    return users;
  }

  Future<int> getLoggedInLabelsLength() async {
    final labels = await getLoggedInLabels();
    return labels.length;
  }

  Future<WhiteLabel> getFirstLoggedInLabelOrDefault() async {
    final labels = await getLoggedInLabels();
    if (labels.isEmpty) {
      return whitelabelsList.reduce((a, b) => a.sort < b.sort ? a : b);
    }

    // Get all logged-in whitelabels
    final loggedInWhitelabels = whitelabelsList
        .where(
          (whitelabel) =>
              labels.any((label) => label.startsWith(whitelabel.friendlyName)),
        )
        .toList();

    // Return the one with the lowest sort index
    return loggedInWhitelabels.reduce((a, b) => a.sort < b.sort ? a : b);
  }

  Future<void> addLoggedInLabel(String label) async {
    var labels = await getLoggedInLabels();
    labels.add(label);
    final labelsString = labels.join(',');
    await settings.setKey('LoggedInLabels', labelsString);
  }

  Future<void> removeLoggedInLabel(String label) async {
    var labels = await getLoggedInLabels();
    final matchingLabel =
        labels.firstWhere((element) => element.split('-')[0] == label);
    labels.remove(matchingLabel);
    final labelsString = labels.join(',');
    await settings.setKey('LoggedInLabels', labelsString);
  }

  Future<void> clearLoggedInLabels() async {
    await settings.removeKey('LoggedInLabels');
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
  final String? oauthconfigurl;
  final String? oauthappname;
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
    this.oauthconfigurl,
    this.oauthappname,
    required this.sort,
    required this.features,
    this.chatUrl,
  });
}

class WhiteLabelWithUser {
  final bool loggedin;
  final WhiteLabel whitelabel;
  final String name;
  final String friendlyName;
  final String? rawName;
  final UserSelfV3Response? user;

  WhiteLabelWithUser({
    required this.loggedin,
    required this.whitelabel,
    required this.name,
    required this.friendlyName,
    this.rawName,
    this.user,
  });
}
