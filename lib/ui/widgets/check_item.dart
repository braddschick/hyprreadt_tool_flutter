import 'package:flutter/material.dart';

import '../../checks/check.dart';

class CheckItem extends StatelessWidget {
  final Check check;
  final CheckResult? result;

  const CheckItem({super.key, required this.check, this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = result == null
        ? Colors.white10
        : _getStatusColor(result!.status).withOpacity(0.3);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF1C1C1E),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => _buildDetailsSheet(context, theme),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIcon(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        check.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (result != null)
                        Text(
                          result!.message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[300],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        Text(
                          check.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[500],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsSheet(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 24),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Row(
            children: [
              _buildIcon(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  check.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Text(
            "Status",
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: result == null
                  ? Colors.white10
                  : _getStatusColor(result!.status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: result == null
                    ? Colors.white24
                    : _getStatusColor(result!.status).withOpacity(0.3),
              ),
            ),
            child: Text(
              result?.status.name.toUpperCase() ?? "PENDING",
              style: theme.textTheme.labelMedium?.copyWith(
                color: result == null
                    ? Colors.grey
                    : _getStatusColor(result!.status),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            "Details",
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            result?.message ?? check.description,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.5,
              color: Colors.grey[300],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    if (result == null) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white10,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.circle_outlined, size: 16, color: Colors.grey),
      );
    }

    final status = result!.status;
    Color color = _getStatusColor(status);
    IconData iconData = Icons.help;

    switch (status) {
      case CheckStatus.pass:
        iconData = Icons.check;
        break;
      case CheckStatus.fail:
        iconData = Icons.close;
        break;
      case CheckStatus.warning:
        iconData = Icons.warning_amber_rounded;
        break;
      case CheckStatus.manual:
        iconData = Icons.question_mark;
        break;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Icon(iconData, size: 18, color: color),
    );
  }

  Color _getStatusColor(CheckStatus status) {
    switch (status) {
      case CheckStatus.pass:
        return Colors.greenAccent;
      case CheckStatus.fail:
        return Colors.redAccent;
      case CheckStatus.warning:
        return Colors.amberAccent;
      case CheckStatus.manual:
        return Colors.blueAccent;
    }
  }
}
