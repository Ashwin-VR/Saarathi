class AppLog {
  final String type;
  final DateTime time;

  AppLog(this.type, this.time);
}

final List<AppLog> appLogs = <AppLog>[];

void addLog(String type, {bool testMode = false}) {
  appLogs.add(
    AppLog(
      testMode ? '$type (TEST)' : type,
      DateTime.now(),
    ),
  );
}
