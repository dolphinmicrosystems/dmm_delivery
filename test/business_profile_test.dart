import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dmm_delivery/models/business_profile.dart';
import 'package:dmm_delivery/services/business_profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('BusinessProfile.fromMap', () {
    test('no document reads as New Zealand, no branding, photos optional', () {
      final profile = BusinessProfile.fromMap(null);
      expect(profile.country, 'NZ');
      expect(profile.timezone, 'Pacific/Auckland');
      expect(profile.requirePhoto, isFalse);
      expect(profile.hasBranding, isFalse);
    });

    test('reads every field', () {
      final logo = Uint8List.fromList([1, 2, 3]);
      final profile = BusinessProfile.fromMap({
        'business_name': '  Dunedin Milk  ',
        'logo': Blob(logo),
        'country': 'AU',
        'timezone': 'Australia/Perth',
        'require_photo': true,
      });
      expect(profile.name, 'Dunedin Milk');
      expect(profile.logo, logo);
      expect(profile.country, 'AU');
      expect(profile.timezone, 'Australia/Perth');
      expect(profile.requirePhoto, isTrue);
      expect(profile.hasBranding, isTrue);
    });

    test("a zone outside the country reads as the country's main one", () {
      final profile = BusinessProfile.fromMap({'country': 'AU', 'timezone': 'Pacific/Auckland'});
      expect(profile.timezone, 'Australia/Sydney');
    });

    test('an unknown country falls back to New Zealand', () {
      final profile = BusinessProfile.fromMap({'country': 'XX', 'timezone': 'Europe/London'});
      expect(profile.country, 'NZ');
      expect(profile.timezone, 'Pacific/Auckland');
    });

    test('a removed logo reads as none', () {
      expect(BusinessProfile.fromMap({'logo': null}).logo, isNull);
    });
  });

  group('Country', () {
    test('codes are unique two-letter codes, each with a zone', () {
      final codes = Country.all.map((c) => c.code).toList();
      expect(codes.toSet().length, codes.length);
      for (final country in Country.all) {
        expect(country.code.length, 2);
        expect(country.timezones, isNotEmpty);
      }
    });

    test('zone labels read as city names', () {
      expect(Country.zoneLabel('Pacific/Auckland'), 'Auckland');
      expect(Country.zoneLabel('America/St_Johns'), 'St Johns');
    });
  });

  group('shrinkLogo', () {
    test('a large image comes back at most 256 px on its long side', () {
      final big = img.encodePng(img.Image(width: 1200, height: 600));
      final shrunk = shrinkLogo(big)!;
      final decoded = img.decodeImage(shrunk)!;
      expect(decoded.width, 256);
      expect(decoded.height, 128);
      expect(shrunk.length, lessThanOrEqualTo(BusinessProfile.maxLogoBytes));
    });

    test('a small image keeps its size', () {
      final small = img.encodePng(img.Image(width: 40, height: 80));
      final decoded = img.decodeImage(shrinkLogo(small)!)!;
      expect((decoded.width, decoded.height), (40, 80));
    });

    test('something that is not an image is refused', () {
      expect(shrinkLogo(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });
}
