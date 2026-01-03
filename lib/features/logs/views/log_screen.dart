import 'package:flutter/material.dart';
import 'package:floaty/features/logs/repositories/log_service.dart';

enum LogType { app, download }

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  List<String> logs = [];
  bool loading = true;
  LogType selectedLogType = LogType.app;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => loading = true);
    if (selectedLogType == LogType.app) {
      logs = await LogService.getLogs();
    } else {
      logs = await LogService.getDownloadLogs();
    }
    setState(() => loading = false);
  }

  Future<void> _clearLogs() async {
    if (selectedLogType == LogType.app) {
      await LogService.clearLogs();
    } else {
      await LogService.clearDownloadLogs();
    }
    await _loadLogs();
  }

  void _switchLogType(LogType? type) {
    if (type != null && type != selectedLogType) {
      setState(() {
        selectedLogType = type;
      });
      _loadLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: logs.isEmpty ? null : _clearLogs,
            tooltip: 'Clear Logs',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Log type switcher
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<LogType>(
              segments: const [
                ButtonSegment<LogType>(
                  value: LogType.app,
                  label: Text('App Logs'),
                  icon: Icon(Icons.bug_report),
                ),
                ButtonSegment<LogType>(
                  value: LogType.download,
                  label: Text('Download Logs'),
                  icon: Icon(Icons.download),
                ),
              ],
              selected: {selectedLogType},
              onSelectionChanged: (Set<LogType> selection) {
                _switchLogType(selection.first);
              },
            ),
          ),
          // Logs display
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : logs.isEmpty
                    ? Center(
                        child: Text(
                          'No ${selectedLogType == LogType.app ? 'app' : 'download'} logs found.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      )
                    : ListView.builder(
                        itemCount: logs.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: SelectableText(
                            logs[i],
                            style: const TextStyle(
                              fontSize: 14,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
