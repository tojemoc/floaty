import 'dart:convert';
import 'package:floaty/features/helpers/respositories/capitalize.dart';
import 'package:flutter/material.dart';
import 'package:floaty/features/updater/respositories/updater_controllers.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  bool isLoading = true;
  dynamic data;

  @override
  void initState() {
    super.initState();
    checkForUpdates();
  }

  String formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoDate;
    }
  }

  List parseJsonField(dynamic field) {
    if (field == null) return [];
    if (field is List) return field;
    if (field is String) {
      try {
        final parsed = jsonDecode(field);
        return parsed is List ? parsed : [];
      } catch (e) {
        return [];
      }
    }
    return [];
  }

  Future<void> checkForUpdates() async {
    data = await updatercontroller.getUpdate();
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      body: Center(
        child: isLoading
            ? CircularProgressIndicator()
            : SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 650),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: Offset(0, 6),
                          )
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Top image area with safe crop (16:9 on mobile, full on larger screens)
                          ClipRRect(
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(16)),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isMobile = constraints.maxWidth < 600;
                                final imageWidget = Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // If thumbnail available, show it; otherwise a neutral grey
                                    if ((data['update']?['thumbnail'] ?? '') !=
                                        '')
                                      Image.network(
                                        'https://floaty.fyi${data['update']['thumbnail']}',
                                        fit: BoxFit.cover,
                                        alignment: Alignment.center,
                                      )
                                    else
                                      Container(
                                          color: colorScheme
                                              .surfaceContainerHighest),

                                    // Top-left tags (multiple badges)
                                    if (parseJsonField(data['update']?['tags'])
                                        .isNotEmpty)
                                      Positioned(
                                        left: 14,
                                        top: 14,
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            for (var tag in parseJsonField(
                                                data['update']['tags']))
                                              Container(
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Color(int.parse(
                                                      (tag['color'] ??
                                                              '#5B7CFF')
                                                          .replaceAll(
                                                              '#', '0xFF'))),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  tag['name']?.toString() ??
                                                      tag.toString(),
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                          color: Colors.white),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),

                                    // Top-right flavor pill
                                    Positioned(
                                      right: 14,
                                      top: 14,
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surface,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.star,
                                                color: colorScheme.onSurface,
                                                size: 14),
                                            SizedBox(width: 8),
                                            Text(
                                              capitalize(data['update']
                                                      ['flavor'] ??
                                                  ''),
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                      color: colorScheme
                                                          .onSurface),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );

                                // On mobile: crop to 16:9, on larger screens: show full image with max height
                                return isMobile
                                    ? AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: imageWidget,
                                      )
                                    : ConstrainedBox(
                                        constraints:
                                            BoxConstraints(maxHeight: 400),
                                        child: AspectRatio(
                                          aspectRatio: 16 / 9,
                                          child: imageWidget,
                                        ),
                                      );
                              },
                            ),
                          ),

                          // Dark content area
                          Container(
                            padding: EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.vertical(
                                  bottom: Radius.circular(16)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['update']['title'] ?? '',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                          color: colorScheme.onSurface,
                                          fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'v${data['update']['version']} | ${formatDate(data['update']['created_at'])}${data['deployment']['required'] == 1 ? ' | Required Update' : ''}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant),
                                ),
                                SizedBox(height: 14),
                                Text(
                                  data['update']['summary'] ?? '',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant),
                                ),
                                SizedBox(height: 18),

                                // Dropdowns
                                if (parseJsonField(data['update']?['dropdowns'])
                                    .isNotEmpty)
                                  ...(parseJsonField(
                                          data['update']['dropdowns'])
                                      .map((d) => _DropdownCard(
                                          iconName: d['icon'] ?? '',
                                          title: d['title'] ?? '',
                                          content: d['content'] ?? ''))),

                                SizedBox(height: 12),
                                Text(
                                  'Contributors: ${data['update']['content'] ?? ''}',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(color: colorScheme.outline),
                                ),
                                SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    if (updatercontroller.updateReady) {
                                      launchUrl(Uri.parse(
                                          'https://floaty.fyi/download'));
                                    } else {
                                      null;
                                    }
                                  },
                                  child: Text(updatercontroller.updateReady
                                      ? 'Download on Website'
                                      : 'Your up to date!'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _DropdownCard extends StatefulWidget {
  final String iconName;
  final String title;
  final String content;

  const _DropdownCard(
      {required this.iconName, required this.title, required this.content});

  @override
  State<_DropdownCard> createState() => _DropdownCardState();
}

class _DropdownCardState extends State<_DropdownCard> {
  bool expanded = false;

  TextSpan _parseBold(String text, TextStyle base) {
    final parts = text.split('**');
    final children = <TextSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (i.isOdd) {
        children.add(TextSpan(
            text: parts[i], style: base.copyWith(fontWeight: FontWeight.bold)));
      } else {
        children.add(TextSpan(text: parts[i], style: base));
      }
    }
    return TextSpan(children: children);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: Offset(0, 3),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => expanded = !expanded),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (widget.iconName.isNotEmpty)
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: Image.network(
                            'https://floaty.fyi/images/${widget.iconName}.png',
                            width: 22,
                            height: 22,
                            errorBuilder: (_, __, ___) => SizedBox.shrink(),
                          ),
                        ),
                      ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(widget.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600)),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      child: Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          color: colorScheme.onSurfaceVariant),
                    )
                  ],
                ),
                if (expanded) ...[
                  SizedBox(height: 10),
                  RichText(
                    text: _parseBold(
                        widget.content,
                        theme.textTheme.bodyMedium!
                            .copyWith(color: colorScheme.onSurfaceVariant)),
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}
