import 'package:flutter/material.dart';
class SubtitleStyle {
  final double fontSize;
  final FontWeight fontWeight;
  final double backgroundOpacity; // 0.0 - 1.0
  final Color color;
  const SubtitleStyle({
    required this.fontSize,
    required this.fontWeight,
    required this.backgroundOpacity,
    required this.color,
  });
  // Default style
  factory SubtitleStyle.defaultStyle() => const SubtitleStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600, // Semi Bold
        backgroundOpacity: 0.5,
        color: Colors.white,
      );
  SubtitleStyle copyWith({
    double? fontSize,
    FontWeight? fontWeight,
    double? backgroundOpacity,
    Color? color,
  }) =>
      SubtitleStyle(
        fontSize: fontSize ?? this.fontSize,
        fontWeight: fontWeight ?? this.fontWeight,
        backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
        color: color ?? this.color,
      );
}