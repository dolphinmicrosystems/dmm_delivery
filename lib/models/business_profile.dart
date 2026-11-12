import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// How a business presents itself and runs its deliveries:
/// `business_profile/{ownerUid}`, written from the owner's Settings and read
/// by the owner and their drivers (firestore.rules).
///
///  * [name] and [logo] - shown in the app bar after sign-in, for drivers
///    and owners, in place of the Blue Dot mark.
///  * [country] and [timezone] - where the business delivers. Saved now for
///    address lookups and day boundaries, which still assume New Zealand.
///  * [requirePhoto] - every delivery needs a photo: the driving screen
///    drops "Deliver without a photo", and driving away from a stop asks for
///    one instead of confirming by itself.
///
/// Separate from `app_settings/{ownerUid}`, which only owners may read: a
/// driver needs these.
class BusinessProfile {
  const BusinessProfile({
    this.name,
    this.logo,
    this.country = defaultCountry,
    this.timezone = defaultTimezone,
    this.requirePhoto = false,
  });

  static const empty = BusinessProfile();
  static const defaultCountry = 'NZ';
  static const defaultTimezone = 'Pacific/Auckland';

  /// Same limits as firestore.rules.
  static const maxNameLength = 60;
  static const maxLogoBytes = 200 * 1024;

  final String? name;

  /// A small PNG or JPEG (resized on the phone before it is saved).
  final Uint8List? logo;
  final String country;
  final String timezone;
  final bool requirePhoto;

  bool get hasBranding => logo != null || (name?.isNotEmpty ?? false);

  factory BusinessProfile.fromMap(Map<String, dynamic>? data) {
    if (data == null) return empty;
    final country = data['country'] as String?;
    final zone = data['timezone'] as String?;
    final known = Country.byCode(country);
    return BusinessProfile(
      name: (data['business_name'] as String?)?.trim(),
      logo: switch (data['logo']) {
        final Blob blob => blob.bytes,
        _ => null,
      },
      country: known?.code ?? defaultCountry,
      // A zone that doesn't belong to the country reads as the country's first.
      timezone: known != null && known.timezones.contains(zone)
          ? zone!
          : (known?.timezones.first ?? defaultTimezone),
      requirePhoto: data['require_photo'] == true,
    );
  }
}

/// The countries a business can choose, each with the time zones it spans
/// (IANA names, the first being the most common). A short list on purpose:
/// where Blue Dot is likely to be used, kept in step with firestore.rules.
class Country {
  const Country(this.code, this.name, this.timezones);

  final String code;
  final String name;
  final List<String> timezones;

  static const all = [
    Country('NZ', 'New Zealand', ['Pacific/Auckland', 'Pacific/Chatham']),
    Country('AU', 'Australia', [
      'Australia/Sydney',
      'Australia/Melbourne',
      'Australia/Brisbane',
      'Australia/Adelaide',
      'Australia/Perth',
      'Australia/Hobart',
      'Australia/Darwin',
    ]),
    Country('GB', 'United Kingdom', ['Europe/London']),
    Country('IE', 'Ireland', ['Europe/Dublin']),
    Country('US', 'United States', [
      'America/New_York',
      'America/Chicago',
      'America/Denver',
      'America/Phoenix',
      'America/Los_Angeles',
      'America/Anchorage',
      'Pacific/Honolulu',
    ]),
    Country('CA', 'Canada', [
      'America/Toronto',
      'America/Vancouver',
      'America/Edmonton',
      'America/Winnipeg',
      'America/Halifax',
      'America/St_Johns',
    ]),
    Country('IN', 'India', ['Asia/Kolkata']),
    Country('SG', 'Singapore', ['Asia/Singapore']),
    Country('AE', 'United Arab Emirates', ['Asia/Dubai']),
    Country('ZA', 'South Africa', ['Africa/Johannesburg']),
  ];

  static Country? byCode(String? code) {
    for (final country in all) {
      if (country.code == code) return country;
    }
    return null;
  }

  /// "Pacific/Auckland" -> "Auckland", "America/St_Johns" -> "St Johns".
  static String zoneLabel(String zone) => zone.split('/').last.replaceAll('_', ' ');
}
