import 'package:flutter/material.dart';
import 'package:floaty/features/download/views/fp_offline_library_screen.dart';
import 'package:floaty/features/download/views/fp_downloads_screen.dart';

class FPDownloadsCombinedScreen extends StatefulWidget {
  const FPDownloadsCombinedScreen({super.key});

  @override
  State<FPDownloadsCombinedScreen> createState() =>
      _FPDownloadsCombinedScreenState();
}

class _FPDownloadsCombinedScreenState extends State<FPDownloadsCombinedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(
            icon: Icon(Icons.download_done_rounded),
            text: 'Offline Library',
          ),
          Tab(
            icon: Icon(Icons.download_rounded),
            text: 'Queue',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          FPOfflineLibraryScreen(embedded: true),
          FPDownloadsScreen(embedded: true),
        ],
      ),
    );
  }
}
