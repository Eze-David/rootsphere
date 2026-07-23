import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/person.dart';

/// A single person card rendered in the tree.
///
/// Supports two layouts:
///  * **portrait** (vertical view): sex-tinted photo on top, name + years below;
///  * **landscape** (horizontal view): a photo thumbnail beside the name.
///
/// The focus person may show an inline "+ Add relative" footer via
/// [onAddRelative], and in landscape gets a dark highlighted header.
class PersonCardWidget extends StatefulWidget {
  const PersonCardWidget({
    super.key,
    required this.person,
    required this.isFocus,
    required this.onTap,
    this.horizontal = false,
    this.onAddRelative,
  });

  final Person person;
  final bool isFocus;
  final bool horizontal;
  final VoidCallback onTap;
  final VoidCallback? onAddRelative;

  @override
  State<PersonCardWidget> createState() => _PersonCardWidgetState();
}

class _PersonCardWidgetState extends State<PersonCardWidget> {
  bool _hovered = false;

  Person get person => widget.person;
  bool get isFocus => widget.isFocus;
  bool get horizontal => widget.horizontal;
  VoidCallback? get onAddRelative => widget.onAddRelative;

  static const Color _focusDark = Color(0xFF2E2A26);

  Color get _tint => switch (person.sex) {
    Sex.male => AppColors.maleTint,
    Sex.female => AppColors.femaleTint,
    Sex.unknown => AppColors.neutralTint,
  };

  /// Compact year span, e.g. "1960–2020" or "1992–Living".
  String get _yearSpan {
    final int? b = person.birthDate?.year;
    final int? d = person.deathDate?.year;
    if (b == null && d == null) return person.isLiving ? 'Living' : '';
    final String birth = b?.toString() ?? '?';
    final String death = d?.toString() ?? (person.isLiving ? 'Living' : '?');
    return '$birth–$death';
  }

  bool get _onDark => horizontal && isFocus;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color cardSurface = theme.colorScheme.surface;
    final Color border = _hovered
        ? AppColors.sunGold
        : isFocus
        ? AppColors.primaryHover
        : theme.dividerColor;
    final double borderWidth = isFocus || _hovered ? 2 : 1;
    final Color headerBg = _onDark ? _focusDark : cardSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Ink(
            decoration: BoxDecoration(
              color: cardSurface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: border, width: borderWidth),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: ColoredBox(
                      color: headerBg,
                      child: horizontal ? _landscape(theme) : _portrait(theme),
                    ),
                  ),
                  if (onAddRelative != null) _addRelativeBar(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Portrait (vertical view) ────────────────────────────────────────────
  Widget _portrait(ThemeData theme) {
    final Color silhouette = Color.lerp(_tint, Colors.black, 0.32)!;
    final String span = _yearSpan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: _photo(silhouette)),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            children: <Widget>[
              Text(
                person.fullName,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              if (span.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  span,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
              if ((person.code ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  person.code!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Landscape (horizontal view) ──────────────────────────────────────────
  Widget _landscape(ThemeData theme) {
    final Color silhouette = Color.lerp(_tint, Colors.black, 0.32)!;
    final String span = _yearSpan;
    final Color nameColor = _onDark
        ? Colors.white
        : theme.textTheme.bodyLarge!.color!;
    final Color spanColor = _onDark ? Colors.white70 : AppColors.textTertiary;
    return Row(
      children: <Widget>[
        SizedBox(width: 54, child: _photo(silhouette)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  person.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: nameColor,
                  ),
                ),
                if (span.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    span,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: spanColor,
                    ),
                  ),
                ],
                if ((person.code ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    person.code!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: spanColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _photo(Color silhouette) {
    final bool hasPhoto =
        person.photoUrl != null && person.photoUrl!.isNotEmpty;
    return Container(
      color: _tint,
      child: hasPhoto
          ? Image.network(
              person.photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Center(
                child: Icon(Icons.person, size: 40, color: silhouette),
              ),
            )
          : Center(child: Icon(Icons.person, size: 40, color: silhouette)),
    );
  }

  Widget _addRelativeBar(ThemeData theme) {
    return Material(
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: onAddRelative,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          alignment: Alignment.center,
          // Scale the label down on the narrow portrait card so it never
          // overflows horizontally.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.add, size: 18, color: AppColors.primaryHover),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Add relative',
                  maxLines: 1,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.primaryHover,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
