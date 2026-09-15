import 'package:flutter/material.dart';

class DocumentUploadCard extends StatelessWidget {
  const DocumentUploadCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
    this.fileName,
    this.preview,
    super.key,
  });
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;
  final String? fileName;
  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    fileName == null ? icon : Icons.check_circle_rounded,
                    color: theme.colorScheme.secondary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(description, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              if (preview != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: preview!,
                  ),
                ),
              ],
              if (fileName != null) ...[
                const SizedBox(height: 12),
                Text(fileName!),
              ],
              const SizedBox(height: 12),
              Text(
                fileName == null
                    ? 'Tap to choose a file'
                    : 'Tap to replace file',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
