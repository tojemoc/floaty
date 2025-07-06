import 'package:flutter/material.dart';

class CustomListTile extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final bool isCollapsed;
  final double? minLeadingWidth;
  final double iconSize;
  final bool dense;
  final bool isThreeLine;

  const CustomListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.contentPadding,
    this.isCollapsed = false,
    this.minLeadingWidth,
    this.iconSize = 24.0,
    this.dense = false,
    this.isThreeLine = false,
  });

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMaterial(context));
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextTheme textTheme = theme.textTheme;

    // Calculate dimensions based on density
    final double tileHeight = dense ? 40.0 : 48.0;
    final double effectiveIconSize = dense ? 20.0 : iconSize;
    final double horizontalPadding =
        isCollapsed ? 0.0 : 12.0; // Reduced from 16.0 to 12.0

    // Text styles
    final TextStyle? titleStyle = textTheme.titleMedium?.copyWith(
      color: selected ? colorScheme.primary : colorScheme.onSurface,
      fontSize: dense ? 13.0 : 16.0,
    );

    final TextStyle? subtitleStyle = textTheme.bodyMedium?.copyWith(
      color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      fontSize: dense ? 12.0 : 14.0,
    );

    final TextStyle? leadingAndTrailingStyle = textTheme.bodyMedium?.copyWith(
      color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      fontSize: dense ? 13.0 : 14.0,
    );

    // Build the row children
    final List<Widget> rowChildren = [];

    // Add leading widget
    if (leading != null) {
      rowChildren.add(
        ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 0, // Allow the container to be as small as possible
            maxHeight: effectiveIconSize,
          ),
          child: Align(
            alignment: isCollapsed ? Alignment.center : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(
                  right: 8.0), // Add right padding to the icon
              child: DefaultTextStyle.merge(
                style: leadingAndTrailingStyle,
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    size: effectiveIconSize,
                  ),
                  child: leading!,
                ),
              ),
            ),
          ),
        ),
      );
      // Removed the extra SizedBox gap
    }

    // Add title and subtitle if not collapsed
    if (title != null && !isCollapsed) {
      final List<Widget> titleChildren = [
        DefaultTextStyle(
          style: titleStyle!,
          overflow: TextOverflow.ellipsis,
          maxLines: isThreeLine ? 1 : null,
          child: title!,
        ),
      ];

      if (subtitle != null) {
        titleChildren.addAll([
          const SizedBox(height: 2.0),
          DefaultTextStyle(
            style: subtitleStyle!,
            overflow: TextOverflow.ellipsis,
            maxLines: isThreeLine ? 2 : 1,
            child: subtitle!,
          ),
        ]);
      }

      rowChildren.add(
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: titleChildren,
          ),
        ),
      );
    }

    // Add trailing if not collapsed
    if (trailing != null && !isCollapsed) {
      rowChildren.add(
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: DefaultTextStyle.merge(
            style: leadingAndTrailingStyle,
            child: IconTheme.merge(
              data: IconThemeData(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                size: 20.0,
              ),
              child: trailing!,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.0),
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            minHeight: tileHeight,
            minWidth: isCollapsed ? tileHeight : 0.0,
          ),
          padding: contentPadding ??
              EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: isThreeLine ? 8.0 : 4.0,
              ),
          alignment: isCollapsed ? Alignment.center : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: isCollapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: rowChildren,
          ),
        ),
      ),
    );
  }
}
