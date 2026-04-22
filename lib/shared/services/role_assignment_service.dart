enum Role { CALL_AMBULANCE, FIRST_AID, SUPPORT }

Role assignRole(int rssi, String deviceId) {
  if (rssi > -60) {
    return Role.CALL_AMBULANCE;
  }

  if (rssi > -75) {
    return _stableHash(deviceId).isEven ? Role.FIRST_AID : Role.SUPPORT;
  }

  return Role.SUPPORT;
}

int _stableHash(String input) {
  var hash = 0;
  for (final code in input.codeUnits) {
    hash = ((hash * 31) + code) & 0x7fffffff;
  }
  return hash;
}
