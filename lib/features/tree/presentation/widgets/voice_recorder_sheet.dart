import 'dart:async';
import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Opens a bottom sheet that records a voice note and returns the local file
/// path of the recording (or null if cancelled / no permission).
Future<String?> showVoiceRecorderSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
    ),
    builder: (_) => const _VoiceRecorderSheet(),
  );
}

class _VoiceRecorderSheet extends StatefulWidget {
  const _VoiceRecorderSheet();

  @override
  State<_VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<_VoiceRecorderSheet> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _starting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() {
          _starting = false;
          _error = 'Microphone permission is required to record.';
        });
        return;
      }
      final Directory dir = await getTemporaryDirectory();
      final String path =
          '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsed += const Duration(seconds: 1));
      });
      setState(() {
        _starting = false;
        _recording = true;
      });
    } catch (_) {
      setState(() {
        _starting = false;
        _error = 'Could not start recording.';
      });
    }
  }

  Future<void> _stopAndSave() async {
    _timer?.cancel();
    final String? path = await _recorder.stop();
    if (mounted) Navigator.pop(context, path);
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    if (_recording) await _recorder.stop();
    if (mounted) Navigator.pop(context);
  }

  String get _formatted {
    final String m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Voice note', style: text.titleLarge),
            const SizedBox(height: AppSpacing.xl),
            if (_error != null) ...<Widget>[
              const Icon(Icons.mic_off_outlined,
                  size: 48, color: AppColors.textTertiary),
              const SizedBox(height: AppSpacing.md),
              Text(_error!, textAlign: TextAlign.center, style: text.bodyMedium),
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ] else ...<Widget>[
              _PulsingMic(active: _recording),
              const SizedBox(height: AppSpacing.lg),
              Text(
                _starting ? 'Preparing…' : _formatted,
                style: text.displayMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _starting ? null : _cancel,
                      icon: const Icon(Icons.close),
                      label: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _starting ? null : _stopAndSave,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop & save'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PulsingMic extends StatefulWidget {
  const _PulsingMic({required this.active});
  final bool active;

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double scale =
            widget.active ? 1 + (_controller.value * 0.15) : 1;
        return Container(
          width: 96 * scale,
          height: 96 * scale,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(
              alpha: widget.active ? 0.12 : 0.06,
            ),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.mic,
            size: 40,
            color: widget.active ? AppColors.error : AppColors.textTertiary,
          ),
        );
      },
    );
  }
}
