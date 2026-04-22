import 'package:shared_preferences/shared_preferences.dart';

/// Stores and retrieves user profile data from SharedPreferences.
class ProfileService {
  static const _keyName = 'profile_name';
  static const _keyGender = 'profile_gender';
  static const _keyAge = 'profile_age';
  static const _keyBloodGroup = 'profile_blood_group';
  static const _keySos1 = 'profile_sos1';
  static const _keySos2 = 'profile_sos2';

  Future<UserProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    return UserProfile(
      name: prefs.getString(_keyName),
      gender: prefs.getString(_keyGender),
      age: prefs.getString(_keyAge),
      bloodGroup: prefs.getString(_keyBloodGroup),
      sos1: prefs.getString(_keySos1),
      sos2: prefs.getString(_keySos2),
    );
  }

  Future<void> save(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    _set(prefs, _keyName, profile.name);
    _set(prefs, _keyGender, profile.gender);
    _set(prefs, _keyAge, profile.age);
    _set(prefs, _keyBloodGroup, profile.bloodGroup);
    _set(prefs, _keySos1, profile.sos1);
    _set(prefs, _keySos2, profile.sos2);
  }

  void _set(SharedPreferences prefs, String key, String? value) {
    if (value != null && value.isNotEmpty) {
      prefs.setString(key, value);
    } else {
      prefs.remove(key);
    }
  }
}

class UserProfile {
  final String? name;
  final String? gender;
  final String? age;
  final String? bloodGroup;
  final String? sos1;
  final String? sos2;

  const UserProfile({
    this.name,
    this.gender,
    this.age,
    this.bloodGroup,
    this.sos1,
    this.sos2,
  });

  UserProfile copyWith({
    String? name,
    String? gender,
    String? age,
    String? bloodGroup,
    String? sos1,
    String? sos2,
  }) {
    return UserProfile(
      name: name ?? this.name,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      sos1: sos1 ?? this.sos1,
      sos2: sos2 ?? this.sos2,
    );
  }
}
