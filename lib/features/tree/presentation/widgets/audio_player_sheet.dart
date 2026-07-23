import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Opens a bottom sheet that plays a voice note from [reference] (a network
/// URL or local file path) with simple play/pause and a seek bar.
Future<void> showAudioPlayerSheet(
  BuildContext context, {
  required String reference,
}) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
    ),
    builder: (_) => _AudioPlayerSheet(reference: reference),
  );
}

class _AudioPlayerSheet extends StatefulWidget {
  const _AudioPlayerSheet({required this.reference});
  final String reference;

  @override
  State<_AudioPlayerSheet> createState() => _AudioPlayerSheetState();
}

class _AudioPlayerSheetState extends State<_AudioPlayerSheet> {
  final AudioPlayer _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
    _toggle();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Source get _source => widget.reference.startsWith('http')
      ? UrlSource(widget.reference)
      : DeviceFileSource(widget.reference);

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(_source);
    }
  }

  String _fmt(Duration d) {
    final String m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double max =
        _duration.inMilliseconds.toDouble().clamp(1, double.infinity);
    final double value =
        _position.inMilliseconds.toDouble().clamp(0, max);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.graphic_eq, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Text('Voice note', style: text.titleMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                IconButton.filled(
                  iconSize: 32,
                  onPressed: _toggle,
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                ),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: max,
                    value: value,
                    onChanged: (v) =>
                        _player.seek(Duration(milliseconds: v.round())),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(_fmt(_position), style: text.bodySmall),
                  Text(_fmt(_duration), style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
