import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/comment_model.dart';
import '../../models/song_model.dart';
import '../../services/player_service.dart';
import '../../services/favorites_service.dart';
import '../../widgets/comments_sheet.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    PlayerService.instance.addListener(_rebuild);
    FavoritesService.instance.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PlayerService.instance.removeListener(_rebuild);
    FavoritesService.instance.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerService.instance;
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();

    final isFav = FavoritesService.instance.isFavorite(song.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _Background(coverUrl: song.coverUrl),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  song: song,
                  isFav: isFav,
                  tab: _tab,
                  onTabChanged: (t) => setState(() => _tab = t),
                  onFavTap: () =>
                      FavoritesService.instance.toggleFavorite(song.id),
                  onCommentsTap: () => showCommentsSheet(
                    context,
                    parentId: song.id,
                    parentType: CommentParentType.song,
                    isPaid: song.isPaid,
                  ),
                ),
                Expanded(
                  child: _tab == 0
                      ? _PlayerView(player: player, song: song)
                      : _tab == 1
                      ? _QueueView(player: player)
                      : _LyricsView(song: song),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Background ───────────────────────────────────────────────────────────────
class _Background extends StatelessWidget {
  const _Background({required this.coverUrl});
  final String coverUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (coverUrl.isNotEmpty)
          Image.network(
            coverUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: AppColors.surface),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background.withValues(alpha: 0.70),
                AppColors.background.withValues(alpha: 0.88),
                AppColors.background,
                AppColors.background,
              ],
              stops: const [0.0, 0.3, 0.65, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Top Bar ──────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.song,
    required this.isFav,
    required this.tab,
    required this.onTabChanged,
    required this.onFavTap,
    required this.onCommentsTap,
  });
  final SongModel song;
  final bool isFav;
  final int tab;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onFavTap;
  final VoidCallback onCommentsTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              // ── Botón cerrar ───────────────────────────────────────────
              _CircleBtn(
                icon: Icons.keyboard_arrow_down_rounded,
                size: 26,
                onTap: () => Navigator.pop(context),
              ),

              // ── Título ─────────────────────────────────────────────────
              Expanded(
                child: Text(
                  song.type == SongType.albumTrack
                      ? song.albumTitle.toUpperCase()
                      : 'NOW PLAYING',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),

              // ── Comentarios ────────────────────────────────────────────
              _CircleBtn(
                icon: Icons.chat_bubble_outline_rounded,
                size: 18,
                color: song.isPaid
                    ? AppColors.surfaceLight
                    : AppColors.textSecondary,
                onTap: song.isPaid ? () {} : onCommentsTap,
              ),
              const SizedBox(width: 6),

              // ── Favorito ───────────────────────────────────────────────
              _CircleBtn(
                icon: isFav
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 20,
                color: isFav ? AppColors.primary : AppColors.textSecondary,
                onTap: onFavTap,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TabChip(
                label: 'Player',
                active: tab == 0,
                onTap: () => onTabChanged(0),
              ),
              const SizedBox(width: 8),
              _TabChip(
                label: 'Queue',
                active: tab == 1,
                onTap: () => onTabChanged(1),
              ),
              const SizedBox(width: 8),
              _TabChip(
                label: 'Lyrics',
                active: tab == 2,
                onTap: () => onTabChanged(2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.18)
              : AppColors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? AppColors.primary.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.primary : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ─── Player View ──────────────────────────────────────────────────────────────
class _PlayerView extends StatelessWidget {
  const _PlayerView({required this.player, required this.song});
  final PlayerService player;
  final SongModel song;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: _ArtworkCard(
              coverUrl: song.coverUrl,
              isPlaying: player.isPlaying,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          song.featuring.isNotEmpty
                              ? '${song.artistName}  ·  ft. ${song.featuring}'
                              : song.artistName,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (song.uploadDateDisplay.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                color: AppColors.textSecondary,
                                size: 11,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                song.uploadDateDisplay,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      song.genreDisplay.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _ProgressSection(player: player),
              const SizedBox(height: 20),
              _ControlsRow(player: player),
              const SizedBox(height: 20),
              _BottomControls(player: player),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Artwork Card ─────────────────────────────────────────────────────────────
class _ArtworkCard extends StatelessWidget {
  const _ArtworkCard({required this.coverUrl, required this.isPlaying});
  final String coverUrl;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: isPlaying ? 0.35 : 0.10),
            blurRadius: isPlaying ? 50 : 16,
            spreadRadius: isPlaying ? 4 : 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: coverUrl.isNotEmpty
            ? Image.network(
                coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _ArtFallback(),
              )
            : _ArtFallback(),
      ),
    );
  }
}

class _ArtFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surface,
    child: const Center(
      child: Icon(
        Icons.music_note_rounded,
        color: AppColors.textSecondary,
        size: 72,
      ),
    ),
  );
}

// ─── Progress Section ─────────────────────────────────────────────────────────
class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.player});
  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.surfaceLight,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withValues(alpha: 0.18),
          ),
          child: Slider(
            value: player.progress,
            onChanged: (val) {
              final ms = (val * player.duration.inMilliseconds).round();
              player.seekTo(Duration(milliseconds: ms));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                player.formatDuration(player.position),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              Text(
                player.formatDuration(player.duration),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Controls Row ─────────────────────────────────────────────────────────────
class _ControlsRow extends StatelessWidget {
  const _ControlsRow({required this.player});
  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _CtrlBtn(
          icon: Icons.skip_previous_rounded,
          size: 36,
          enabled: player.hasPrevious,
          onTap: player.skipPrevious,
        ),
        GestureDetector(
          onTap: player.togglePlay,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.45),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: player.isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.background,
                      ),
                    )
                  : Icon(
                      player.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: AppColors.background,
                      size: 34,
                    ),
            ),
          ),
        ),
        _CtrlBtn(
          icon: Icons.skip_next_rounded,
          size: 36,
          enabled: player.hasNext,
          onTap: player.skipNext,
        ),
      ],
    );
  }
}

// ─── Bottom Controls ──────────────────────────────────────────────────────────
class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.player});
  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    final repeatMode = player.repeatMode;
    final shuffle = player.shuffle;

    IconData repeatIcon;
    String repeatLabel;
    Color repeatColor;

    switch (repeatMode) {
      case PlayerRepeatMode.none:
        repeatIcon = Icons.repeat_rounded;
        repeatLabel = 'Repeat';
        repeatColor = AppColors.textSecondary;
        break;
      case PlayerRepeatMode.all:
        repeatIcon = Icons.repeat_rounded;
        repeatLabel = 'Repeat All';
        repeatColor = AppColors.primary;
        break;
      case PlayerRepeatMode.one:
        repeatIcon = Icons.repeat_one_rounded;
        repeatLabel = 'Repeat One';
        repeatColor = AppColors.primary;
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        GestureDetector(
          onTap: player.toggleShuffle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shuffle_rounded,
                  color: shuffle ? AppColors.primary : AppColors.textSecondary,
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  'Shuffle',
                  style: TextStyle(
                    color: shuffle
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: shuffle ? 4 : 0,
                  height: shuffle ? 4 : 0,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: player.toggleRepeat,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(repeatIcon, color: repeatColor, size: 24),
                const SizedBox(height: 4),
                Text(
                  repeatLabel,
                  style: TextStyle(
                    color: repeatColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: repeatMode != PlayerRepeatMode.none ? 4 : 0,
                  height: repeatMode != PlayerRepeatMode.none ? 4 : 0,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Queue View ───────────────────────────────────────────────────────────────
class _QueueView extends StatelessWidget {
  const _QueueView({required this.player});
  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    final queue = player.queue;
    final currentIdx = player.queueIndex;

    if (queue.isEmpty) {
      return const Center(
        child: Text(
          'Queue is empty.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      itemCount: queue.length,
      itemBuilder: (ctx, i) {
        final s = queue[i];
        final isActive = i == currentIdx;
        return GestureDetector(
          onTap: () {
            if (!isActive) {
              PlayerService.instance.playSong(s, queue: queue, index: i);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.10)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.40)
                    : AppColors.surfaceLight,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: s.coverUrl.isNotEmpty
                      ? Image.network(
                          s.coverUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _QueueFallback(),
                        )
                      : _QueueFallback(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        style: TextStyle(
                          color: isActive
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        s.artistName,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  const _SmallWave()
                else
                  Text(
                    s.durationDisplay,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QueueFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    color: AppColors.surfaceLight,
    child: const Icon(
      Icons.music_note_rounded,
      color: AppColors.textSecondary,
      size: 18,
    ),
  );
}

// ─── Small Wave ───────────────────────────────────────────────────────────────
class _SmallWave extends StatefulWidget {
  const _SmallWave();
  @override
  State<_SmallWave> createState() => _SmallWaveState();
}

class _SmallWaveState extends State<_SmallWave> with TickerProviderStateMixin {
  late final List<AnimationController> _c;

  @override
  void initState() {
    super.initState();
    _c = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 350 + i * 100),
      )..repeat(reverse: true),
    );
  }

  @override
  void dispose() {
    for (final c in _c) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
          animation: _c[i],
          builder: (_, __) => Container(
            width: 2.5,
            height: 5 + _c[i].value * 8,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Lyrics View ──────────────────────────────────────────────────────────────
class _LyricsView extends StatelessWidget {
  const _LyricsView({required this.song});
  final SongModel song;

  @override
  Widget build(BuildContext context) {
    final hasLyrics = song.lyrics.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasLyrics)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(
                  children: [
                    Icon(
                      Icons.lyrics_rounded,
                      color: AppColors.surfaceLight,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No lyrics available for this track.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              song.lyrics,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                height: 2.0,
                letterSpacing: 0.2,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Shared Buttons ───────────────────────────────────────────────────────────
class _CircleBtn extends StatelessWidget {
  const _CircleBtn({
    required this.icon,
    required this.onTap,
    this.size = 22,
    this.color,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color ?? AppColors.textPrimary, size: size),
      ),
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  const _CtrlBtn({
    required this.icon,
    required this.size,
    required this.onTap,
    this.enabled = true,
  });
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Icon(
        icon,
        size: size,
        color: enabled ? AppColors.textPrimary : AppColors.surfaceLight,
      ),
    );
  }
}
