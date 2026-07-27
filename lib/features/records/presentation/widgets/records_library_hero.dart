import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_spacing.dart';

/// Hero banner used by the Records library and search screens.
///
/// A dark overlay sits on top of the supplied photo(s) so the white text
/// remains readable on both mobile and desktop. When more than one [assets]
/// entry is given, it auto-crossfades between them on a fixed ~30-second
/// total cycle (so 3 images swap every ~10s) — the form/white card is
/// intentionally left to the consuming screen.
class RecordsLibraryHero extends StatefulWidget {
  const RecordsLibraryHero({
    super.key,
    required this.assets,
    required this.title,
    this.subtitle,
  });

  final List<String> assets;
  final String title;
  final String? subtitle;

  static const Duration cycleDuration = Duration(seconds: 30);

  @override
  State<RecordsLibraryHero> createState() => _RecordsLibraryHeroState();
}

class _RecordsLibraryHeroState extends State<RecordsLibraryHero> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant RecordsLibraryHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assets != widget.assets) {
      _index = 0;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.assets.length <= 1) return;
    final Duration interval =
        RecordsLibraryHero.cycleDuration ~/ widget.assets.length;
    _timer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.assets.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.of(context).size.width > 700;
    final String asset = widget.assets[_index % widget.assets.length];

    return Container(
      height: isWide ? 360 : 320,
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            layoutBuilder: (Widget? currentChild, List<Widget> previous) {
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ...previous,
                  ?currentChild,
                ],
              );
            },
            child: Image.asset(
              asset,
              key: ValueKey<String>(asset),
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
            ),
          ),
          Container(
            width: double.infinity,
            height: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxl,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  Colors.black.withValues(alpha: 0.72),
                  Colors.black.withValues(alpha: 0.48),
                  Colors.black.withValues(alpha: 0.12),
                ],
                stops: const <double>[0.0, 0.55, 1.0],
              ),
            ),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        flex: 5,
                        child: _Headline(
                          title: widget.title,
                          subtitle: widget.subtitle,
                        ),
                      ),
                      const Expanded(flex: 5, child: SizedBox.shrink()),
                    ],
                  )
                : _Headline(title: widget.title, subtitle: widget.subtitle),
          ),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      // Anchored to the bottom rather than centred — the search screen
      // overlays a back button/title at the top of this same hero, and
      // centred text was drifting up close enough to read as cramped
      // against it.
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Text(
          title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 38,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: Colors.white,
          ),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}
