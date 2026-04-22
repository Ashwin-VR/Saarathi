import 'package:flutter/material.dart';
import 'package:accident_app/shared/services/app_log_service.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity Logs')),
      body: appLogs.isEmpty
          ? const Center(child: Text('No logs yet'))
          : ListView.builder(
              itemCount: appLogs.length,
              itemBuilder: (context, index) {
                final log = appLogs[index];
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(log.type),
                  subtitle: Text(log.time.toString()),
                );
              },
            ),
    );
  }
}
