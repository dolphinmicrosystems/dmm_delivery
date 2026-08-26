/// How someone describes themselves, for the profile form.
///
/// Stored as the snake_case `wire` value rather than the enum index, because
/// an index is meaningless in the Firestore console and reorders the moment
/// anyone adds a case. `firestore.rules` matches on these exact strings.
enum ProfileGender {
  female('female', 'Female'),
  male('male', 'Male'),
  another('another', 'Another term'),
  preferNotToSay('prefer_not_to_say', 'Prefer not to say');

  const ProfileGender(this.wire, this.label);

  final String wire;
  final String label;

  /// Unknown values read as null rather than throwing: this field is
  /// self-reported and the set of accepted answers will grow, so a document
  /// written by a newer build must not make an older one unable to open the
  /// screen.
  static ProfileGender? parse(String? raw) {
    for (final value in ProfileGender.values) {
      if (value.wire == raw) return value;
    }
    return null;
  }
}

/// The signed-in owner's own details.
///
/// Placeholder data for now - nothing in the delivery pipeline reads any of
/// it. It exists so the account has somewhere to live beyond the name and
/// avatar Google supplies, and so the screen that edits it is built against
/// a real document rather than a mock.
///
/// Every field is optional. A profile nobody has filled in is a valid
/// profile, and the form must never insist on an answer it has no use for.
///
/// Kept free of `cloud_firestore` on purpose: [fromMap] takes a plain map, so
/// all of the parsing and validation below is testable without a fake.
class OwnerProfile {
  const OwnerProfile({this.displayName, this.age, this.gender, this.phone});

  static const empty = OwnerProfile();

  /// The name the owner chose, which overrides the one Google supplied.
  /// Mirrors the precedence rule used for route names and driver names.
  final String? displayName;

  /// Stored as a number because that is what was asked for, and it is
  /// dummy data. For anything real this should be a date of birth: an age
  /// written down is wrong within a year and nothing here refreshes it.
  final int? age;

  final ProfileGender? gender;
  final String? phone;

  /// All four mirror `firestore.rules` the way `RouteName.maxLength` does -
  /// an out-of-range value comes back as a bare `permission-denied`, which
  /// reads as a sign-in failure rather than as a rejected form.
  static const int maxNameLength = 80;
  static const int maxPhoneLength = 32;
  static const int minAge = 16;
  static const int maxAge = 120;

  bool get isEmpty => displayName == null && age == null && gender == null && phone == null;

  /// The one line the Settings account card shows under the email.
  ///
  /// Joins only what is actually filled in, so a half-finished profile reads
  /// as a short line rather than as a row of dashes.
  String get summary {
    final parts = [
      if (age != null) '$age',
      if (gender != null) gender!.label,
      if (phone != null && phone!.isNotEmpty) phone!,
    ];
    return parts.isEmpty ? 'Profile not filled in' : parts.join(' · ');
  }

  /// Whether saving would actually change anything.
  ///
  /// Compared field by field rather than by raw controller text, for the same
  /// reason `RouteName.isRenameOf` exists: a confirmation prompt that fires
  /// when nothing changed is what teaches people to dismiss it unread.
  bool differsFrom(OwnerProfile other) {
    return displayName != other.displayName ||
        age != other.age ||
        gender != other.gender ||
        phone != other.phone;
  }

  factory OwnerProfile.fromMap(Map<String, dynamic>? data) {
    if (data == null) return empty;
    return OwnerProfile(
      displayName: _text(data['display_name']),
      // `num` rather than `int`: Firestore hands back whichever the document
      // happens to hold, and a profile written as 34.0 should still load.
      age: (data['age'] as num?)?.toInt(),
      gender: ProfileGender.parse(data['gender'] as String?),
      phone: _text(data['phone']),
    );
  }

  /// The document to write, with unset fields omitted rather than written as
  /// null.
  ///
  /// The distinction is load-bearing: the rules validate `'age' in
  /// request.resource.data`, so a null age would be a present key failing its
  /// `is int` check and the whole write would be refused. Callers `set()` this
  /// as a full replace, which is what lets clearing a field remove its key.
  Map<String, Object?> toMap() => {
    if (displayName != null) 'display_name': displayName,
    if (age != null) 'age': age,
    if (gender != null) 'gender': gender!.wire,
    if (phone != null) 'phone': phone,
  };

  static String? _text(Object? raw) {
    final value = raw is String ? raw.trim() : null;
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Collapses runs of whitespace so "Pawan  Arora" and "Pawan Arora" are one
  /// name, not two profiles that look identical.
  static String normalizeName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Null when acceptable. An empty value is acceptable everywhere here -
  /// leaving a field blank is an answer.
  static String? nameError(String raw) {
    final name = normalizeName(raw);
    if (name.length > maxNameLength) return 'Keep the name to $maxNameLength characters or fewer.';
    return null;
  }

  static String? ageError(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final age = int.tryParse(text);
    if (age == null) return 'Enter your age as a number.';
    if (age < minAge || age > maxAge) return 'Enter an age between $minAge and $maxAge.';
    return null;
  }

  static String? phoneError(String raw) {
    final phone = raw.trim();
    if (phone.length > maxPhoneLength) return 'Keep the phone number to $maxPhoneLength characters or fewer.';
    return null;
  }

  /// First error across the whole form, or null if it is ready to save.
  /// One place, so the save button and the leave-guard agree about whether
  /// there is anything savable.
  static String? formError({required String name, required String age, required String phone}) {
    return nameError(name) ?? ageError(age) ?? phoneError(phone);
  }

  /// Builds a profile from what is currently typed. Blank fields become null,
  /// which is what removes them from the document on save.
  static OwnerProfile fromForm({
    required String name,
    required String age,
    required String phone,
    ProfileGender? gender,
  }) {
    final trimmedName = normalizeName(name);
    final trimmedPhone = phone.trim();
    return OwnerProfile(
      displayName: trimmedName.isEmpty ? null : trimmedName,
      age: int.tryParse(age.trim()),
      gender: gender,
      phone: trimmedPhone.isEmpty ? null : trimmedPhone,
    );
  }
}
