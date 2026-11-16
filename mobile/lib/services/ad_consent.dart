import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google UMP consent before any ad request.
///
/// AdMob shows its published consent message (EEA, UK, Switzerland) only when
/// the app asks for it. Outside those regions no form appears and ads can be
/// requested right away. Failures never block ads that UMP already allows.
class AdConsent {
  /// Updates consent info, shows the consent form if required, then starts
  /// the Mobile Ads SDK when ads may be requested. Returns whether ads may be
  /// requested.
  static Future<bool> gatherAndStartAds() async {
    final info = ConsentInformation.instance;
    final updated = Completer<void>();
    info.requestConsentInfoUpdate(ConsentRequestParameters(), updated.complete, (_) => updated.complete());
    await updated.future;

    await ConsentForm.loadAndShowConsentFormIfRequired((_) {});

    final canRequest = await info.canRequestAds();
    if (canRequest) await MobileAds.instance.initialize();
    return canRequest;
  }

  /// Whether the user must be offered a way to change their consent (shown as
  /// a settings entry).
  static Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  /// Re-opens the consent form so the user can change their choice.
  static Future<void> showPrivacyOptions() => ConsentForm.showPrivacyOptionsForm((_) {});
}
