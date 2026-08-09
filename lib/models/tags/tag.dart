import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// A single reusable tag a task can be assigned to. Tasks hold at most one
/// tag (Task.tagId) — tags themselves are a flat list the user builds up
/// over time via TaskFormScreen's inline "+ new tag", not a per-task
/// nested structure.
class Tag {
  final String id;
  final String name;

  /// Hex color string, e.g. '#7C6CFF'. Assigned deterministically from the
  /// tag's name at creation time (see TagService._colorForName) rather
  /// than user-picked, to keep tag creation a single quick step.
  final String colorHex;

  Tag({
    required this.id,
    required this.name,
    required this.colorHex,
  });

  factory Tag.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Tag(
      id: doc.id,
      name: data['name'] as String? ?? '',
      colorHex: data['colorHex'] as String? ?? _fallbackColorHex,
    );
  }

  /// Falls back to the first color in AppColors.tagPalette rather than an
  /// arbitrary hardcoded hex — TagService._colorForName always draws new
  /// tag colors from that same palette, so an old/malformed doc missing
  /// colorHex should still render a color that's actually part of the
  /// app's theme instead of an unrelated purple. Computed the same way
  /// TagService._colorForName converts a Color to a hex string, so this
  /// stays correct if the palette itself ever changes.
  static String get _fallbackColorHex {
    final hex =
        AppColors.tagPalette.first.value.toRadixString(16).padLeft(8, '0');
    return '#${hex.substring(2).toUpperCase()}';
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'colorHex': colorHex,
      };

  Color get color => Color(
        int.parse(colorHex.replaceFirst('#', '0xFF')),
      );
}