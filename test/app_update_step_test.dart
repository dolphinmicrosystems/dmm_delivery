import 'package:dmm_delivery/models/app_update_step.dart';
import 'package:flutter_test/flutter_test.dart';

AppUpdateStep _decide({
  String availability = 'updateAvailable',
  String installStatus = 'unknown',
  bool flexibleAllowed = true,
  bool alreadyAsked = false,
}) => AppUpdateStep.decide(
  availability: availability,
  installStatus: installStatus,
  flexibleAllowed: flexibleAllowed,
  alreadyAsked: alreadyAsked,
);

void main() {
  test('a newer version on Play is downloaded', () {
    expect(_decide(), AppUpdateStep.download);
  });

  test('nothing newer means nothing to do', () {
    expect(_decide(availability: 'updateNotAvailable'), AppUpdateStep.none);
  });

  test('an update already downloaded is offered for install, even if asked before', () {
    expect(_decide(installStatus: 'downloaded', alreadyAsked: true), AppUpdateStep.install);
    expect(_decide(availability: 'updateNotAvailable', installStatus: 'downloaded'), AppUpdateStep.install);
  });

  test('a download in progress is left alone', () {
    for (final status in ['pending', 'downloading', 'installing']) {
      expect(_decide(installStatus: status), AppUpdateStep.none, reason: status);
    }
  });

  test('saying no is not asked again in the same session', () {
    expect(_decide(alreadyAsked: true), AppUpdateStep.none);
  });

  test('when Play does not allow a background update, it is not attempted', () {
    expect(_decide(flexibleAllowed: false), AppUpdateStep.none);
  });
}
