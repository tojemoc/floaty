import 'package:cached_network_image/cached_network_image.dart';
import 'package:floaty/shared/controllers/root_provider.dart';
import 'package:floaty/features/router/components/custom_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PictureSidebarItem extends StatelessWidget {
  final String picture;
  final String title;
  final String route;
  final bool isSidebarCollapsed;
  final bool isSmallScreen;
  final bool showText;
  final VoidCallback? onTap;

  const PictureSidebarItem({
    super.key,
    required this.picture,
    required this.title,
    required this.route,
    required this.isSidebarCollapsed,
    required this.isSmallScreen,
    required this.showText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = GoRouterState.of(context).uri.path == route;
    final theme = Theme.of(context);

    return CustomListTile(
      selected: isSelected,
      leading: AnimatedContainer(
        width: 24,
        height: 24,
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          border: isSelected
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : null,
          borderRadius: BorderRadius.circular(100),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: picture.isNotEmpty
              ? CachedNetworkImage(
                  width: 24,
                  height: 24,
                  imageUrl: picture,
                  fit: BoxFit.cover,
                )
              : Image.asset('assets/placeholder.png',
                  width: 24, height: 24, fit: BoxFit.cover),
        ),
      ),
      title:
          (showText || isSmallScreen) && title.isNotEmpty ? Text(title) : null,
      onTap: onTap ??
          () {
            context.pushReplacement(route);
            scaffoldKey.currentState?.closeDrawer();
          },
      isCollapsed: isSidebarCollapsed,
      minLeadingWidth: 24.0,
    );
  }
}
