import 'package:flutter/material.dart';

class SavedAddress {
  const SavedAddress({
    required this.label,
    required this.line,
    required this.icon,
    this.isDefault = false,
  });

  final String label;
  final String line;
  final IconData icon;
  final bool isDefault;
}
