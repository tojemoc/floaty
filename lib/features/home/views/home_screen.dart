import 'dart:io';
import 'package:floaty/features/api/models/definitions.dart';
import 'package:floaty/features/api/utils/error_handler.dart';
import 'package:floaty/features/post/components/blog_post_card.dart';
import 'package:floaty/shared/utils/exceptions.dart';
import 'package:floaty/shared/views/error_screen.dart';
import 'package:floaty/whitelabels.dart';
import 'package:flutter/material.dart';
import 'package:floaty/features/api/repositories/fpapi.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:floaty/features/router/views/root_layout.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _pageSize = 20;
  late final PagingController<int, BlogPostCard> _pagingController;
  List<String> creatorIds = [];
  List<ContentCreatorListLastItems> lastElements = [];
  FloatyException? _error;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _pagingController = PagingController<int, BlogPostCard>(
      getNextPageKey: (state) => (state.keys?.last ?? 0) + 1,
      fetchPage: _fetchPage,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setAppTitle();
    });
  }

  void setAppTitle() {
    rootLayoutKey.currentState?.setAppBar(const Text('Home'));
  }

  Future<List<String>> _getCreatorIds() async {
    if (!mounted) return [];
    if (creatorIds.isNotEmpty) return creatorIds;
    try {
      creatorIds = await fpApiRequests
          .getSubscribedCreatorsIds(
              (await whitelabels.getSelectedWhitelabel()).friendlyName)
          .first;
    } on SocketException catch (e) {
      throw NoInternetException(details: e.message, originalError: e);
    } on TimeoutException catch (e) {
      throw TimeoutException(details: e.message, originalError: e)
          as FloatyException;
    } catch (error) {
      if (FPApiErrorHandler.isConnectivityError(error)) {
        throw NoInternetException(details: error.toString());
      }
      creatorIds = [];
    }
    return creatorIds;
  }

  void _handleRetry() {
    setState(() {
      _hasError = false;
      _error = null;
    });
    lastElements = [];
    creatorIds = [];
    _pagingController.refresh();
  }

  Future<List<BlogPostCard>> _fetchPage(int pageKey) async {
    if (!mounted) return [];
    try {
      creatorIds = await _getCreatorIds();
      if (!mounted || creatorIds.isEmpty) return [];

      ContentCreatorListV3Response? home;
      if (lastElements.isNotEmpty) {
        home = await fpApiRequests.getMultiCreatorVideoFeed(
            (await whitelabels.getSelectedWhitelabel()).friendlyName,
            creatorIds,
            _pageSize,
            lastElements: lastElements);
      } else {
        home = await fpApiRequests.getMultiCreatorVideoFeed(
            (await whitelabels.getSelectedWhitelabel()).friendlyName,
            creatorIds,
            _pageSize);
      }

      if (!mounted) return [];

      // Clear any previous error state on successful fetch
      if (_hasError) {
        setState(() {
          _hasError = false;
          _error = null;
        });
      }

      final newPosts = home.blogPosts ?? [];
      lastElements = home.lastElements ?? [];

      if (newPosts.length < _pageSize) {
        _pagingController.value = _pagingController.value.copyWith(
          hasNextPage: false,
          isLoading: false,
        );
      }

      List<String> blogPostIds = newPosts
          .map((post) => post.id)
          .where((id) => id != null)
          .cast<String>()
          .toList();
      List<GetProgressResponse> progressResponses =
          await fpApiRequests.getVideoProgress(
              (await whitelabels.getSelectedWhitelabel()).friendlyName,
              blogPostIds);

      if (!mounted) return [];

      Map<String, GetProgressResponse?> progressMap = {
        for (var progress in progressResponses) progress.id!: progress
      };

      return newPosts.map((post) {
        return BlogPostCard(post, response: progressMap[post.id]);
      }).toList();
    } on FloatyException catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _error = e;
        });
      }
      return [];
    } on SocketException catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _error = NoInternetException(details: e.message, originalError: e);
        });
      }
      return [];
    } catch (error) {
      if (mounted) {
        setState(() {
          _hasError = true;
          if (FPApiErrorHandler.isConnectivityError(error)) {
            _error = NoInternetException(details: error.toString());
          } else {
            _error = UnexpectedException(
                details: error.toString(), originalError: error);
          }
        });
      }
      return [];
    }
  }

  @override
  void dispose() {
    if (mounted) {
      _pagingController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show full-screen error if we have an error and no items
    if (_hasError &&
        _error != null &&
        _pagingController.value.items?.isEmpty != false) {
      return Scaffold(
        body: ErrorScreen.fromException(
          _error!,
          onRetry: _handleRetry,
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          lastElements = [];
          if (mounted) {
            _pagingController.refresh();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: LayoutBuilder(builder: (context, constraints) {
            final useList = constraints.maxWidth <= 450;
            return PagingListener<int, BlogPostCard>(
              controller: _pagingController,
              builder: (context, state, fetchNextPage) {
                return useList
                    ? PagedListView<int, BlogPostCard>(
                        state: state,
                        fetchNextPage: fetchNextPage,
                        builderDelegate:
                            PagedChildBuilderDelegate<BlogPostCard>(
                          invisibleItemsThreshold: 6,
                          animateTransitions: true,
                          itemBuilder: (context, item, index) => Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: BlogPostCard(item.blogPost,
                                response: item.response,
                                key: Key(item.blogPost.id ?? '')),
                          ),
                          noItemsFoundIndicatorBuilder: (context) =>
                              _hasError && _error != null
                                  ? ErrorScreen.fromException(_error!,
                                      onRetry: _handleRetry)
                                  : const Center(
                                      child: Text("No items found."),
                                    ),
                          firstPageErrorIndicatorBuilder: (context) =>
                              ErrorScreen.fromException(
                            _error ?? const UnexpectedException(),
                            onRetry: _handleRetry,
                          ),
                          newPageErrorIndicatorBuilder: (context) =>
                              InlineErrorIndicator(
                            message:
                                _error?.userMessage ?? 'Failed to load more',
                            onRetry: _handleRetry,
                          ),
                        ),
                      )
                    : PagedGridView<int, BlogPostCard>(
                        state: state,
                        fetchNextPage: fetchNextPage,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 300,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                          childAspectRatio: 1.175,
                        ),
                        builderDelegate:
                            PagedChildBuilderDelegate<BlogPostCard>(
                          invisibleItemsThreshold: 12,
                          animateTransitions: true,
                          itemBuilder: (context, item, index) => Padding(
                            padding: const EdgeInsets.all(4),
                            child: BlogPostCard(item.blogPost,
                                response: item.response,
                                key: Key(item.blogPost.id ?? '')),
                          ),
                          noItemsFoundIndicatorBuilder: (context) =>
                              _hasError && _error != null
                                  ? ErrorScreen.fromException(_error!,
                                      onRetry: _handleRetry)
                                  : const Center(
                                      child: Text("No items found."),
                                    ),
                          firstPageErrorIndicatorBuilder: (context) =>
                              ErrorScreen.fromException(
                            _error ?? const UnexpectedException(),
                            onRetry: _handleRetry,
                          ),
                          newPageErrorIndicatorBuilder: (context) =>
                              InlineErrorIndicator(
                            message:
                                _error?.userMessage ?? 'Failed to load more',
                            onRetry: _handleRetry,
                          ),
                        ),
                      );
              },
            );
          }),
        ),
      ),
    );
  }
}
