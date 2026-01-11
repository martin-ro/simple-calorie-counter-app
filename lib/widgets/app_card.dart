import 'package:flutter/material.dart';

/// A styled card widget with optional title slot.
///
/// Uses Card.outlined with white background and consistent styling.
/// Supports either a simple string [title] or a custom [header] widget.
class AppCard extends StatelessWidget {
  /// Simple string title - rendered with standard styling
  final String? title;

  /// Trailing widget shown to the right of title (e.g., action buttons)
  final Widget? trailing;

  /// Custom header widget - use for complex headers with multiple elements
  final Widget? header;

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  const AppCard({
    super.key,
    this.title,
    this.trailing,
    this.header,
    required this.child,
    this.margin,
    this.padding,
  }) : assert(
          title == null || header == null,
          'Cannot provide both title and header',
        );

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      color: Colors.white,
      margin: margin ?? const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16), // corner radius
      side: BorderSide(
        color: Colors.grey.shade300, // border color
      ),
    ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title!,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (trailing != null) ...[
                    const Spacer(),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (header != null) ...[
              header!,
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
