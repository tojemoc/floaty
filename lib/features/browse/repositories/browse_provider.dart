import 'dart:io';
import 'package:floaty/features/api/utils/error_handler.dart';
import 'package:floaty/shared/utils/exceptions.dart';
import 'package:floaty/whitelabels.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:floaty/features/api/models/definitions.dart';
import 'package:floaty/features/api/repositories/fpapi.dart';
import 'package:floaty/features/router/views/root_layout.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class BrowseState {
  final List<CreatorDiscoveryResponse> creators;
  final bool isLoading;
  final FloatyException? error;
  Timer? debounce;
  TextEditingController searchController = TextEditingController();

  BrowseState({
    required this.creators,
    required this.isLoading,
    required this.searchController,
    this.error,
    this.debounce,
  });

  BrowseState copyWith({
    List<CreatorDiscoveryResponse>? creators,
    bool? isLoading,
    TextEditingController? searchController,
    FloatyException? error,
    Timer? debounce,
    bool clearError = false,
  }) {
    return BrowseState(
      creators: creators ?? this.creators,
      isLoading: isLoading ?? this.isLoading,
      searchController: searchController ?? this.searchController,
      error: clearError ? null : (error ?? this.error),
      debounce: debounce ?? this.debounce,
    );
  }

  bool get hasError => error != null;
}

class BrowseNotifier extends Notifier<BrowseState> {
  @override
  BrowseState build() {
    return BrowseState(
      creators: [],
      isLoading: true,
      searchController: TextEditingController(),
      debounce: null,
    );
  }

  void fetchCreators() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      fpApiRequests
          .getCreatorDiscovery(
              (await whitelabels.getSelectedWhitelabel()).friendlyName)
          .listen(
        (fetchedCreators) {
          state = state.copyWith(
            creators: fetchedCreators,
            isLoading: false,
            clearError: true,
          );
        },
        onError: (error) {
          final exception = _toFloatyException(error);
          state = state.copyWith(
            creators: [],
            isLoading: false,
            error: exception,
          );
        },
      );
    } on SocketException catch (e) {
      state = state.copyWith(
        creators: [],
        isLoading: false,
        error: NoInternetException(details: e.message, originalError: e),
      );
    } catch (e) {
      final exception = _toFloatyException(e);
      state = state.copyWith(
        creators: [],
        isLoading: false,
        error: exception,
      );
    }
  }

  void retry() {
    state = state.copyWith(clearError: true);
    if (state.searchController.text.isNotEmpty) {
      _performSearch(state.searchController.text);
    } else {
      fetchCreators();
    }
  }

  FloatyException _toFloatyException(dynamic error) {
    if (error is FloatyException) return error;
    if (error is SocketException) {
      return NoInternetException(details: error.message, originalError: error);
    }
    if (FPApiErrorHandler.isConnectivityError(error)) {
      return NoInternetException(details: error.toString());
    }
    return UnexpectedException(details: error.toString(), originalError: error);
  }

  void setAppTitle() {
    rootLayoutKey.currentState?.setAppBar(
      TextField(
        controller: state.searchController,
        onChanged: (value) {
          //being kind to the floatplane api
          if (state.debounce?.isActive ?? false) state.debounce!.cancel();
          state.debounce = Timer(const Duration(seconds: 1), () {
            _performSearch(value);
          });
        },
        decoration: const InputDecoration(
          hintText: 'Search creators...',
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search),
        ),
      ),
    );
  }

  void _performSearch(String query) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      fpApiRequests
          .getCreatorDiscovery(
              (await whitelabels.getSelectedWhitelabel()).friendlyName,
              query: query)
          .listen(
        (fetchedCreators) {
          state = state.copyWith(
            creators: fetchedCreators,
            isLoading: false,
            clearError: true,
          );
        },
        onError: (error) {
          final exception = _toFloatyException(error);
          state = state.copyWith(
            isLoading: false,
            error: exception,
          );
        },
      );
    } on SocketException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: NoInternetException(details: e.message, originalError: e),
      );
    } catch (e) {
      final exception = _toFloatyException(e);
      state = state.copyWith(
        isLoading: false,
        error: exception,
      );
    }
  }
}

final browseProvider = NotifierProvider<BrowseNotifier, BrowseState>(() {
  return BrowseNotifier();
});
