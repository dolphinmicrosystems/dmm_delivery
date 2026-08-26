import 'package:flutter_test/flutter_test.dart';

import 'package:dmm_delivery/models/owner_profile.dart';

void main() {
  group('ProfileGender', () {
    test('round-trips through the wire value the rules match on', () {
      for (final gender in ProfileGender.values) {
        expect(ProfileGender.parse(gender.wire), gender);
      }
    });

    test('an unknown value reads as null rather than throwing', () {
      // Self-reported, so the accepted set will grow. A document written by
      // a newer build must not stop an older one opening the screen.
      expect(ProfileGender.parse('something-new'), isNull);
      expect(ProfileGender.parse(null), isNull);
    });

    test('wire values are snake_case, not enum indexes', () {
      // An index means nothing in the Firestore console and shifts the
      // moment anyone adds a case.
      expect(ProfileGender.preferNotToSay.wire, 'prefer_not_to_say');
    });
  });

  group('fromMap', () {
    test('a missing document is an empty profile, not a crash', () {
      expect(OwnerProfile.fromMap(null).isEmpty, isTrue);
      expect(OwnerProfile.fromMap({}).isEmpty, isTrue);
    });

    test('reads every field', () {
      final profile = OwnerProfile.fromMap({
        'display_name': 'Pawan Arora',
        'age': 34,
        'gender': 'male',
        'phone': '+64 21 555 0100',
      });

      expect(profile.displayName, 'Pawan Arora');
      expect(profile.age, 34);
      expect(profile.gender, ProfileGender.male);
      expect(profile.phone, '+64 21 555 0100');
    });

    test('an age stored as a double still loads', () {
      // Firestore hands back whichever numeric type the document holds.
      expect(OwnerProfile.fromMap({'age': 34.0}).age, 34);
    });

    test('blank strings read as absent, so they never render as empty rows', () {
      final profile = OwnerProfile.fromMap({'display_name': '   ', 'phone': ''});

      expect(profile.displayName, isNull);
      expect(profile.phone, isNull);
    });
  });

  group('toMap', () {
    test('omits unset fields rather than writing null', () {
      // Load-bearing: the rules check `'age' in request.resource.data`, so a
      // null age would be a present key failing `is int` and the whole write
      // would be refused.
      final map = const OwnerProfile(age: 34).toMap();

      expect(map, {'age': 34});
    });

    test('writes the gender wire value, not the enum', () {
      final map = const OwnerProfile(gender: ProfileGender.another).toMap();

      expect(map['gender'], 'another');
    });

    test('an empty profile writes an empty document', () {
      expect(OwnerProfile.empty.toMap(), isEmpty);
    });

    test('every key it can emit is one firestore.rules allows', () {
      const full = OwnerProfile(
        displayName: 'Pawan Arora',
        age: 34,
        gender: ProfileGender.male,
        phone: '021',
      );

      expect(full.toMap().keys.toSet(), {'display_name', 'age', 'gender', 'phone'});
    });
  });

  group('summary', () {
    test('an untouched profile says so rather than showing dashes', () {
      expect(OwnerProfile.empty.summary, 'Profile not filled in');
    });

    test('joins only what is actually filled in', () {
      expect(const OwnerProfile(age: 34).summary, '34');
      expect(const OwnerProfile(age: 34, gender: ProfileGender.male).summary, '34 · Male');
    });

    test('reads as one line when everything is there', () {
      const profile = OwnerProfile(
        displayName: 'Pawan Arora',
        age: 34,
        gender: ProfileGender.male,
        phone: '+64 21 555 0100',
      );

      // The name is already the card's title, so it is not repeated here.
      expect(profile.summary, '34 · Male · +64 21 555 0100');
    });
  });

  group('differsFrom', () {
    const original = OwnerProfile(displayName: 'Pawan Arora', age: 34, gender: ProfileGender.male);

    test('an identical profile is not a change', () {
      const same = OwnerProfile(displayName: 'Pawan Arora', age: 34, gender: ProfileGender.male);

      expect(same.differsFrom(original), isFalse);
    });

    test('each field on its own counts', () {
      expect(
        const OwnerProfile(displayName: 'P.', age: 34, gender: ProfileGender.male).differsFrom(original),
        isTrue,
      );
      expect(
        const OwnerProfile(
          displayName: 'Pawan Arora',
          age: 35,
          gender: ProfileGender.male,
        ).differsFrom(original),
        isTrue,
      );
      expect(const OwnerProfile(displayName: 'Pawan Arora', age: 34).differsFrom(original), isTrue);
    });

    test('clearing a field is a change', () {
      expect(OwnerProfile.empty.differsFrom(original), isTrue);
    });
  });

  group('fromForm', () {
    test('blank fields become null, which is what removes them on save', () {
      final profile = OwnerProfile.fromForm(name: '  ', age: '', phone: '   ');

      expect(profile.isEmpty, isTrue);
      expect(profile.toMap(), isEmpty);
    });

    test('collapses whitespace in the name', () {
      final profile = OwnerProfile.fromForm(name: ' Pawan   Arora ', age: '', phone: '');

      expect(profile.displayName, 'Pawan Arora');
    });

    test('respacing a name is not a change worth prompting about', () {
      // The dirty test compares parsed fields, never raw controller text -
      // a prompt that fires when nothing changed teaches people to dismiss
      // it unread.
      const saved = OwnerProfile(displayName: 'Pawan Arora');
      final typed = OwnerProfile.fromForm(name: ' Pawan  Arora ', age: '', phone: '');

      expect(typed.differsFrom(saved), isFalse);
    });
  });

  group('validation', () {
    test('every field may be left blank - a blank is an answer', () {
      expect(OwnerProfile.formError(name: '', age: '', phone: ''), isNull);
    });

    test('accepts a name at the limit firestore.rules enforces', () {
      expect(OwnerProfile.nameError('x' * OwnerProfile.maxNameLength), isNull);
    });

    test('rejects one past it client-side, not as a permission-denied', () {
      expect(OwnerProfile.nameError('x' * (OwnerProfile.maxNameLength + 1)), isNotNull);
    });

    test('measures the collapsed name, not what was typed', () {
      expect(OwnerProfile.nameError('  ${'x' * OwnerProfile.maxNameLength}  '), isNull);
    });

    test('an age has to be a number', () {
      expect(OwnerProfile.ageError('thirty'), isNotNull);
    });

    test('accepts the range the rules accept, and nothing outside it', () {
      expect(OwnerProfile.ageError('${OwnerProfile.minAge}'), isNull);
      expect(OwnerProfile.ageError('${OwnerProfile.maxAge}'), isNull);
      expect(OwnerProfile.ageError('${OwnerProfile.minAge - 1}'), isNotNull);
      expect(OwnerProfile.ageError('${OwnerProfile.maxAge + 1}'), isNotNull);
    });

    test('caps the phone at the length the rules accept', () {
      expect(OwnerProfile.phoneError('0' * OwnerProfile.maxPhoneLength), isNull);
      expect(OwnerProfile.phoneError('0' * (OwnerProfile.maxPhoneLength + 1)), isNotNull);
    });

    test('formError reports the first problem, so the form fixes one thing at a time', () {
      final error = OwnerProfile.formError(
        name: 'x' * (OwnerProfile.maxNameLength + 1),
        age: 'thirty',
        phone: '',
      );

      expect(error, contains('name'));
    });
  });
}
