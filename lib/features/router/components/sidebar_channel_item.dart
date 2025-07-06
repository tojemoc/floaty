import 'package:cached_network_image/cached_network_image.dart';
import 'package:floaty/features/api/models/definitions.dart';
import 'package:floaty/shared/controllers/elements_provider.dart';
import 'package:floaty/shared/controllers/root_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:floaty/features/router/components/custom_list_tile.dart';

class SidebarChannelItem extends ConsumerStatefulWidget {
  final String id;
  final CreatorModelV3 response;
  final bool isSidebarCollapsed;
  final bool isSmallScreen;
  final bool showText;
  final VoidCallback? onTap;

  const SidebarChannelItem({
    super.key,
    required this.id,
    required this.response,
    required this.isSidebarCollapsed,
    required this.isSmallScreen,
    required this.showText,
    this.onTap,
  });

  @override
  ConsumerState<SidebarChannelItem> createState() => _SidebarChannelItemState();
}

class _SidebarChannelItemState extends ConsumerState<SidebarChannelItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool get isExpanded => ref.watch(channelExpansionProvider(widget.id));
  bool autoClosed = true;
  bool manualExpansion = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    if (widget.showText || widget.isSmallScreen) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(SidebarChannelItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if ((widget.showText || widget.isSmallScreen) &&
        !_animationController.isCompleted) {
      _animationController.forward();
    } else if (!(widget.showText || widget.isSmallScreen) &&
        _animationController.isCompleted) {
      _animationController.reverse();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpansion() {
    ref.read(channelExpansionProvider(widget.id).notifier).state =
        !ref.read(channelExpansionProvider(widget.id));
    manualExpansion = true;
  }

  List<ChannelModel> _sortedChannels(List<ChannelModel> channels) {
    return List<ChannelModel>.from(channels)
      ..sort((a, b) => a.order!.compareTo(b.order ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    bool hasSubChannels = widget.response.channels!.length > 1;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (GoRouterState.of(context)
              .uri
              .path
              .contains('/channel/${widget.response.urlname}') &&
          hasSubChannels) {
        if (autoClosed) {
          ref.read(channelExpansionProvider(widget.id).notifier).state = true;
        }
        autoClosed = false;
      } else {
        if (!autoClosed) {
          ref.read(channelExpansionProvider(widget.id).notifier).state = false;
          autoClosed = true;
          manualExpansion = false;
        }
      }
    });
    final bool isSelected = GoRouterState.of(context).uri.path ==
        '/channel/${widget.response.urlname}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomListTile(
          selected: isSelected,
          isCollapsed: widget.isSidebarCollapsed,
          leading: AnimatedContainer(
            width: 24,
            height: 24,
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              border: isSelected
                  ? Border.all(color: colorScheme.primary, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(100),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: widget.response.icon?.path?.isNotEmpty == true
                  ? CachedNetworkImage(
                      width: 24,
                      height: 24,
                      imageUrl: widget.response.icon!.path ?? '',
                    )
                  : Image.asset('assets/placeholder.png'),
            ),
          ),
          title: !widget.isSidebarCollapsed
              ? FadeTransition(
                  opacity: _fadeAnimation,
                  child: (widget.showText || widget.isSmallScreen)
                      ? Text(
                          widget.response.title ?? '',
                        )
                      : const SizedBox.shrink(),
                )
              : null,
          onTap: () {
            context.push('/channel/${widget.response.urlname}');
            if (widget.isSmallScreen) {
              scaffoldKey.currentState?.closeDrawer();
            }
          },
          trailing: hasSubChannels && !widget.isSidebarCollapsed
              ? AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: IconButton(
                    key: ValueKey<bool>(isExpanded),
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    onPressed: _toggleExpansion,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 20,
                  ),
                )
              : null,
        ),
        if (hasSubChannels && isExpanded)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _sortedChannels(widget.response.channels ?? [])
                .map((subChannel) {
              final bool isSubSelected = GoRouterState.of(context).uri.path ==
                  '/channel/${widget.response.urlname}/${subChannel.urlname}';

              return Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: CustomListTile(
                  selected: isSubSelected,
                  isCollapsed: widget.isSidebarCollapsed,
                  leading: Padding(
                    padding: widget.isSidebarCollapsed
                        ? EdgeInsets.zero
                        : const EdgeInsets.only(left: 20.0),
                    child: AnimatedContainer(
                      width: 20,
                      height: 20,
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        border: isSubSelected
                            ? Border.all(color: colorScheme.primary, width: 2)
                            : null,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: subChannel.icon?.path?.isNotEmpty == true
                            ? CachedNetworkImage(
                                width: 20,
                                height: 20,
                                imageUrl: subChannel.icon!.path!,
                              )
                            : Icon(
                                Icons.tag,
                                size: 14,
                              ),
                      ),
                    ),
                  ),
                  title: !widget.isSidebarCollapsed
                      ? FadeTransition(
                          opacity: _fadeAnimation,
                          child: (widget.showText || widget.isSmallScreen)
                              ? Text(
                                  subChannel.title ?? '',
                                  style: TextStyle(
                                    color: isSubSelected
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: isSubSelected
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        )
                      : null,
                  onTap: () {
                    context.push(
                        '/channel/${widget.response.urlname}/${subChannel.urlname}');
                    if (widget.isSmallScreen) {
                      scaffoldKey.currentState?.closeDrawer();
                    }
                  },
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
