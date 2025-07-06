import 'package:floaty/settings.dart';
import 'package:flutter/material.dart';
import 'package:floaty/whitelabels.dart';

class Switcher extends StatefulWidget {
  const Switcher({
    required this.onSwitch,
    required this.whitelabels,
    this.sidebar = false,
    this.compact = false,
    super.key,
  });

  final Function onSwitch;
  final List<WhiteLabel> whitelabels;
  final bool sidebar;
  final bool compact;

  @override
  State<Switcher> createState() => _SwitcherState();
}

class _SwitcherState extends State<Switcher> {
  String selected = '';
  String? hoveredItem;
  bool isLoading = true;
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: 0.5,
      initialPage: 0, // Initialize with a safe default
    );
    _initializeSwitcher();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure the PageView is built before trying to animate
    if (widget.compact && !isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients && mounted) {
          _pageController.jumpToPage(_currentPage);
        }
      });
    }
  }

  Future<void> _initializeSwitcher() async {
    final selectedWhitelabel = await whitelabels.getSelectedWhitelabel();
    _currentPage = widget.whitelabels
        .indexWhere(
          (w) => w.friendlyName == selectedWhitelabel.friendlyName,
        )
        .clamp(0,
            widget.whitelabels.isNotEmpty ? widget.whitelabels.length - 1 : 0);

    if (mounted) {
      setState(() {
        selected = selectedWhitelabel.friendlyName;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.compact) {
      return _buildCarouselSwitcher();
    }

    return _buildHorizontalSwitcher();
  }

  Widget _buildHorizontalSwitcher() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: widget.whitelabels.map((whitelabel) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: _buildLogoButton(
                    whitelabel: whitelabel,
                    isSelected: selected == whitelabel.friendlyName,
                    isHovered: hoveredItem == whitelabel.friendlyName,
                    currentHovered: hoveredItem,
                    onHover: (isHovered) {
                      setState(() {
                        hoveredItem =
                            isHovered ? whitelabel.friendlyName : null;
                      });
                    },
                    onTap: _handleWhitelabelTap(whitelabel.friendlyName),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCarouselSwitcher() {
    if (widget.whitelabels.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 45,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: MediaQuery.of(context).size.width / 2 - 20,
            child: Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              if (index < widget.whitelabels.length && index != _currentPage) {
                final whitelabel = widget.whitelabels[index];
                _handleWhitelabelTap(whitelabel.friendlyName)();
              }
            },
            itemCount: widget.whitelabels.length,
            itemBuilder: (context, index) {
              if (index >= widget.whitelabels.length) {
                return const SizedBox.shrink();
              }

              final whitelabel = widget.whitelabels[index];
              final isSelected = whitelabel.friendlyName == selected;

              return GestureDetector(
                onTap: _handleWhitelabelTap(whitelabel.friendlyName),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    width: isSelected ? 30 : 25,
                    height: isSelected ? 30 : 25,
                    child: _buildLogoButton(
                      whitelabel: whitelabel,
                      isSelected: isSelected,
                      isHovered: false,
                      currentHovered: null,
                      onHover: (_) {},
                      onTap: _handleWhitelabelTap(whitelabel.friendlyName),
                      size: isSelected ? 30.0 : 20.0,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  VoidCallback _handleWhitelabelTap(String friendlyName) {
    return () {
      final newIndex =
          widget.whitelabels.indexWhere((w) => w.friendlyName == friendlyName);
      if (newIndex != -1 && mounted) {
        setState(() {
          selected = friendlyName;
          _currentPage = newIndex;
        });
        if (widget.compact && _pageController.hasClients) {
          // Only animate if the page is not already at the target index
          if (_pageController.page?.round() != newIndex) {
            _pageController.animateToPage(
              newIndex,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        }
        settings.setKey('whitelabel', friendlyName);
        widget.onSwitch(friendlyName);
      }
    };
  }

  Widget _buildLogoButton({
    required WhiteLabel whitelabel,
    required bool isSelected,
    required bool isHovered,
    required String? currentHovered,
    required ValueChanged<bool> onHover,
    required VoidCallback onTap,
    double? size,
  }) {
    final bool shouldHighlight = isSelected;
    final double targetSize = size ?? (widget.sidebar ? 35.0 : 45.0);
    final double scale = shouldHighlight ? 1.0 : 0.85;

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: targetSize,
          height: targetSize,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(150),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedOpacity(
                    opacity: shouldHighlight || isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Image.asset(
                      whitelabel.logoPath,
                      width: targetSize,
                      height: targetSize,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: shouldHighlight || isHovered ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 250),
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Colors.grey,
                        BlendMode.saturation,
                      ),
                      child: Image.asset(
                        whitelabel.logoPath,
                        width: targetSize,
                        height: targetSize,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
