import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// The explainer video is hosted as a static file next to the web build
/// (`web/videos/`) rather than bundled as a Flutter asset, so it doesn't add
/// ~17 MB to the iOS/Android download. On web it's loaded from the same
/// origin (rootsphere.ink or www.); native apps stream it from the site.
Uri _videoUri(String file) => kIsWeb
    ? Uri.base.resolve('/videos/$file')
    : Uri.parse('https://www.rootsphere.ink/videos/$file');

/// Edge-to-edge explainer video on the landing page. Shows a poster frame
/// with a play button and only starts downloading the video once tapped.
class ExplainerVideoSection extends StatefulWidget {
  const ExplainerVideoSection({super.key});

  @override
  State<ExplainerVideoSection> createState() => _ExplainerVideoSectionState();
}

class _ExplainerVideoSectionState extends State<ExplainerVideoSection> {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _failed = false;
  bool _showControls = true;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final VideoPlayerController controller = VideoPlayerController.networkUrl(
      _videoUri('explainer.mp4'),
    );
    try {
      await controller.initialize();
      controller.addListener(_onTick);
      await controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
        _showControls = false;
      });
    } catch (_) {
      controller.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _onTick() {
    final VideoPlayerController? c = _controller;
    if (c == null || !mounted) return;
    // Bring the controls back when the video ends so it can be replayed.
    final bool ended =
        c.value.duration > Duration.zero &&
        c.value.position >= c.value.duration &&
        !c.value.isPlaying;
    if (ended && !_showControls) setState(() => _showControls = true);
  }

  void _togglePlay() {
    final VideoPlayerController? c = _controller;
    if (c == null) {
      _start();
      return;
    }
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _showControls = true;
      } else {
        if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
        c.play();
        _showControls = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = _controller;
    final TextTheme text = Theme.of(context).textTheme;

    return ColoredBox(
      color: Colors.black,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: MouseRegion(
          onHover: (_) {
            if (c != null && !_showControls && !c.value.isPlaying) {
              setState(() => _showControls = true);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _loading ? null : _togglePlay,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (c != null)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: c.value.size.width,
                      height: c.value.size.height,
                      child: VideoPlayer(c),
                    ),
                  )
                else
                  Image.network(
                    _videoUri('explainer_poster.jpg').toString(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                if (c == null || _showControls)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Center(
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    c != null && c.value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 44,
                                    color: Colors.black87,
                                  ),
                                ),
                                if (c == null) ...<Widget>[
                                  const SizedBox(height: 12),
                                  Text(
                                    _failed
                                        ? "Couldn't load the video — tap to retry"
                                        : 'Watch how RootSphere works',
                                    style: text.titleMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ),
                if (c != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          tooltip: c.value.volume == 0 ? 'Unmute' : 'Mute',
                          color: Colors.white,
                          icon: Icon(
                            c.value.volume == 0
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                          ),
                          onPressed: () async {
                            await c.setVolume(c.value.volume == 0 ? 1 : 0);
                            if (mounted) setState(() {});
                          },
                        ),
                        Expanded(
                          child: VideoProgressIndicator(
                            c,
                            allowScrubbing: true,
                            padding: const EdgeInsets.only(right: 16),
                            colors: VideoProgressColors(
                              playedColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ),
                      ],
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
