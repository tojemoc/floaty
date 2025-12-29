import 'package:floaty/features/browse/components/creator_card.dart';
import 'package:floaty/shared/views/error_screen.dart';
import 'package:flutter/material.dart';
import 'package:floaty/features/browse/repositories/browse_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => BrowseScreenState();
}

class BrowseScreenState extends ConsumerState<BrowseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(browseProvider.notifier).setAppTitle();
      ref.read(browseProvider.notifier).fetchCreators();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final browseState = ref.watch(browseProvider);
        final creators = browseState.creators;
        final width = constraints.maxWidth;
        final crossAxisCount = (width / 300).floor().clamp(1, 3);

        // Show error state if there's an error and no creators
        if (browseState.hasError && creators.isEmpty) {
          return Scaffold(
            body: ErrorScreen.fromException(
              browseState.error!,
              onRetry: () => ref.read(browseProvider.notifier).retry(),
            ),
          );
        }

        // Show loading state
        if (browseState.isLoading && creators.isEmpty) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        List<Widget> rows = [];
        for (int i = 0; i < creators.length; i += crossAxisCount) {
          final rowItems = creators.skip(i).take(crossAxisCount).toList();

          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rowItems.map((creator) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: CreatorCard(creator),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          body: RefreshIndicator(
            onRefresh: () async {
              ref.read(browseProvider.notifier).retry();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: width > 1500 ? 1500 : double.infinity,
                  child: Column(
                    children: [
                      // Show inline error if there's an error but we have cached creators
                      if (browseState.hasError && creators.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InlineErrorIndicator(
                            message: browseState.error?.userMessage,
                            onRetry: () =>
                                ref.read(browseProvider.notifier).retry(),
                          ),
                        ),
                      ...rows,
                      // Show empty state if no creators found
                      if (creators.isEmpty && !browseState.isLoading)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'No creators found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
