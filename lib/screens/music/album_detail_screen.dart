import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/album_model.dart';
import '../../models/comment_model.dart';
import '../../models/song_model.dart';
import '../../services/song_service.dart';
import '../../services/player_service.dart';
import '../../services/favorites_service.dart';
import '../../services/purchase_service.dart';
import '../../widgets/mini_player_bar.dart';
import '../../widgets/comments_sheet.dart';
import 'full_player_screen.dart';

class AlbumDetailScreen extends StatefulWidget {
  const AlbumDetailScreen({super.key, required this.album});
  final AlbumModel album;

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<SongModel> _tracks = [];
  List<SongModel> _playableTracks = []; // free + unlocked paid tracks
  bool _loading = true;

  // Album is effectively unlocked if: not paid OR user bought it
  bool get _albumUnlocked =>
      !widget.album.isPaid ||
      PurchaseService.instance.isUnlocked(widget.album.id);

  @override
  void initState() {
    super.initState();
    _loadTracks();
    PlayerService.instance.addListener(_rebuild);
    FavoritesService.instance.addListener(_rebuild);
    PurchaseService.instance.addListener(_rebuildAndRefreshPlayable);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // Called when purchase state changes — refresh playable tracks too
  void _rebuildAndRefreshPlayable() {
    if (!mounted) return;
    setState(() {
      _playableTracks = _tracks
          .where((s) => !s.isPaid || PurchaseService.instance.isUnlocked(s.id))
          .toList();
    });
  }

  @override
  void dispose() {
    PlayerService.instance.removeListener(_rebuild);
    FavoritesService.instance.removeListener(_rebuild);
    PurchaseService.instance.removeListener(_rebuildAndRefreshPlayable);
    super.dispose();
  }

  Future<void> _loadTracks() async {
    final list = await SongService.instance.fetchAlbumTracks(widget.album.id);
    if (!mounted) return;

    setState(() {
      _tracks = list;
      _playableTracks = list
          .where((s) => !s.isPaid || PurchaseService.instance.isUnlocked(s.id))
          .toList();
      _loading = false;
    });
  }

  // ─── Play All ──────────────────────────────────────────────────────────────
  Future<void> _playAll() async {
    // Album is paid and not unlocked → show paywall
    if (!_albumUnlocked) {
      _showAlbumPaywall();
      return;
    }
    if (_playableTracks.isEmpty) return;

    await PlayerService.instance.playSong(
      _playableTracks.first,
      queue: _playableTracks,
      index: 0,
    );
    if (!mounted) return;
    _openPlayer();
  }

  // ─── Paywalls ──────────────────────────────────────────────────────────────
  void _showAlbumPaywall() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AlbumPaywallSheet(album: widget.album),
    );
  }

  void _showSongPaywall(SongModel song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SongPaywallSheet(song: song),
    );
  }

  void _openPlayer() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const FullPlayerScreen(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPlayer = PlayerService.instance.hasTrack;
    final albumUnlocked = _albumUnlocked;

    // Count of playable tracks for subtitle
    final playableCount = _playableTracks.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _HeroSliver(
                album: widget.album,
                albumUnlocked: albumUnlocked,
                playableCount: playableCount,
                onPlay: _playAll,
                onComments: () => showCommentsSheet(
                  context,
                  parentId: widget.album.id,
                  parentType: CommentParentType.album,
                  isPaid: widget.album.isPaid && !albumUnlocked,
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, hasPlayer ? 150 : 40),
                sliver: _loading
                    ? const SliverFillRemaining(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : _tracks.isEmpty
                    ? const SliverFillRemaining(
                        child: Center(
                          child: Text(
                            'No tracks yet.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate((ctx, i) {
                          final song = _tracks[i];

                          // A track is locked if:
                          // - The album is paid and not unlocked (whole album locked), OR
                          // - The individual song is paid and not unlocked
                          final bool trackLocked =
                              (!albumUnlocked && widget.album.isPaid) ||
                              (song.isPaid &&
                                  !PurchaseService.instance.isUnlocked(
                                    song.id,
                                  ));

                          final playableIdx = _playableTracks.indexWhere(
                            (s) => s.id == song.id,
                          );

                          return _TrackRow(
                            song: song,
                            displayIndex: i,
                            trackLocked: trackLocked,
                            playableIndex: playableIdx,
                            playableTracks: _playableTracks,
                            onLockedTap: widget.album.isPaid && !albumUnlocked
                                ? _showAlbumPaywall
                                : () => _showSongPaywall(song),
                            onPlay: _openPlayer,
                          );
                        }, childCount: _tracks.length),
                      ),
              ),
            ],
          ),

          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayerBar(),
          ),
        ],
      ),
    );
  }
}

// ─── Hero Sliver ──────────────────────────────────────────────────────────────
class _HeroSliver extends StatelessWidget {
  const _HeroSliver({
    required this.album,
    required this.albumUnlocked,
    required this.playableCount,
    required this.onPlay,
    required this.onComments,
  });
  final AlbumModel album;
  final bool albumUnlocked;
  final int playableCount;
  final VoidCallback onPlay;
  final VoidCallback onComments;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 310,
      pinned: true,
      backgroundColor: AppColors.background,
      elevation: 0,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.primary,
            size: 18,
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Cover — desaturated if locked
            ColorFiltered(
              colorFilter: !albumUnlocked
                  ? const ColorFilter.matrix([
                      0.2126,
                      0.7152,
                      0.0722,
                      0,
                      0,
                      0.2126,
                      0.7152,
                      0.0722,
                      0,
                      0,
                      0.2126,
                      0.7152,
                      0.0722,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ])
                  : const ColorFilter.mode(
                      Colors.transparent,
                      BlendMode.multiply,
                    ),
              child: album.coverUrl.isNotEmpty
                  ? Image.network(
                      album.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: AppColors.surface),
                    )
                  : Container(color: AppColors.surface),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.background.withValues(alpha: 0.6),
                    AppColors.background,
                  ],
                  stops: const [0.35, 0.75, 1.0],
                ),
              ),
            ),

            // Info bottom left
            Positioned(
              bottom: 18,
              left: 20,
              right: 76,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge: PAID or OWNED
                  if (album.isPaid)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: albumUnlocked
                              ? [
                                  const Color(0xFF00C37A),
                                  const Color(0xFF00A060),
                                ]
                              : [AppColors.accent, AppColors.primary],
                        ),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            albumUnlocked
                                ? Icons.check_circle_rounded
                                : Icons.lock_rounded,
                            color: AppColors.background,
                            size: 10,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            albumUnlocked
                                ? 'OWNED'
                                : 'PREMIUM  ·  \$${album.price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppColors.background,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    album.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    album.artistName,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    albumUnlocked
                        ? '${album.trackCount} track${album.trackCount == 1 ? "" : "s"}'
                        : '${album.trackCount} tracks  ·  $playableCount free',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (album.uploadDateDisplay.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      const Icon(Icons.calendar_today_rounded,
                          color: AppColors.textSecondary, size: 11),
                      const SizedBox(width: 4),
                      Text(
                        album.uploadDateDisplay,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ]),
                  ],
                ],
              ),
            ),

            // Buttons bottom right
            Positioned(
              bottom: 18,
              right: 20,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: onComments,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surface.withValues(alpha: 0.85),
                        border: Border.all(
                          color: AppColors.surfaceLight,
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: onPlay,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: albumUnlocked
                              ? [AppColors.accent, AppColors.primary]
                              : [
                                  const Color(0xFF555555),
                                  const Color(0xFF333333),
                                ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (albumUnlocked
                                        ? AppColors.primary
                                        : Colors.black)
                                    .withValues(alpha: 0.4),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        albumUnlocked
                            ? Icons.play_arrow_rounded
                            : Icons.lock_rounded,
                        color: AppColors.background,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Track Row ────────────────────────────────────────────────────────────────
class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.song,
    required this.displayIndex,
    required this.trackLocked,
    required this.playableIndex,
    required this.playableTracks,
    required this.onLockedTap,
    required this.onPlay,
  });

  final SongModel song;
  final int displayIndex;
  final bool trackLocked;
  final int playableIndex;
  final List<SongModel> playableTracks;
  final VoidCallback onLockedTap;
  final VoidCallback onPlay;

  bool get _isActive => PlayerService.instance.currentSong?.id == song.id;
  bool get _isPlaying => _isActive && PlayerService.instance.isPlaying;
  bool get _isFav => FavoritesService.instance.isFavorite(song.id);

  Future<void> _handleTap(BuildContext context) async {
    if (trackLocked) {
      onLockedTap();
      return;
    }
    if (_isActive) {
      onPlay();
      return;
    }

    await PlayerService.instance.playSong(
      song,
      queue: playableTracks,
      index: playableIndex < 0 ? 0 : playableIndex,
    );

    if (!context.mounted) return;
    onPlay();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _isActive;
    final isPlaying = _isPlaying;
    final isFav = _isFav;

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: trackLocked
              ? AppColors.surface.withValues(alpha: 0.5)
              : isActive
              ? AppColors.primary.withValues(alpha: 0.07)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: trackLocked
                ? AppColors.surfaceLight.withValues(alpha: 0.5)
                : isActive
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.surfaceLight,
            width: isActive && !trackLocked ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // ── Track number / state ───────────────────────────────────
            SizedBox(
              width: 26,
              child: trackLocked
                  ? const Icon(
                      Icons.lock_rounded,
                      color: AppColors.primary,
                      size: 15,
                    )
                  : isActive
                  ? Icon(
                      isPlaying
                          ? Icons.volume_up_rounded
                          : Icons.pause_circle_outline_rounded,
                      color: AppColors.primary,
                      size: 17,
                    )
                  : Text(
                      '${displayIndex + 1}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
            const SizedBox(width: 10),

            // ── Cover ──────────────────────────────────────────────────
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColorFiltered(
                    colorFilter: trackLocked
                        ? const ColorFilter.matrix([
                            0.2126,
                            0.7152,
                            0.0722,
                            0,
                            0,
                            0.2126,
                            0.7152,
                            0.0722,
                            0,
                            0,
                            0.2126,
                            0.7152,
                            0.0722,
                            0,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0,
                          ])
                        : const ColorFilter.mode(
                            Colors.transparent,
                            BlendMode.multiply,
                          ),
                    child: song.coverUrl.isNotEmpty
                        ? Image.network(
                            song.coverUrl,
                            width: 42,
                            height: 42,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const _TrackCoverFallback(),
                          )
                        : const _TrackCoverFallback(),
                  ),
                ),
                if (trackLocked)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.accent, AppColors.primary],
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        song.isPaid
                            ? '\$${song.price.toStringAsFixed(0)}'
                            : '\$${0}',
                        style: const TextStyle(
                          color: AppColors.background,
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),

            // ── Info ───────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: TextStyle(
                      color: trackLocked
                          ? AppColors.textSecondary
                          : isActive
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (song.featuring.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'ft. ${song.featuring}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  if (trackLocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            color: AppColors.primary,
                            size: 10,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            song.isPaid
                                ? 'Premium  ·  \$${song.price.toStringAsFixed(0)}'
                                : 'Premium Album',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // ── Favorite (only for unlocked tracks) ───────────────────
            if (!trackLocked)
              GestureDetector(
                onTap: () => FavoritesService.instance.toggleFavorite(song.id),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      isFav
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      key: ValueKey(isFav),
                      color: isFav
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      size: 18,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(width: 8),

            // ── Duration ───────────────────────────────────────────────
            Text(
              song.durationDisplay,
              style: TextStyle(
                color: trackLocked
                    ? AppColors.textSecondary.withValues(alpha: 0.5)
                    : AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 8),

            // ── Play / Lock button ─────────────────────────────────────
            if (trackLocked)
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.accent, AppColors.primary],
                  ),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: AppColors.background,
                  size: 13,
                ),
              )
            else
              Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
                size: 19,
              ),
          ],
        ),
      ),
    );
  }
}

class _TrackCoverFallback extends StatelessWidget {
  const _TrackCoverFallback();
  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    color: AppColors.surfaceLight,
    child: const Icon(
      Icons.music_note_rounded,
      color: AppColors.textSecondary,
      size: 18,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// ALBUM PAYWALL SHEET
// ══════════════════════════════════════════════════════════════════════════════
class _AlbumPaywallSheet extends StatefulWidget {
  const _AlbumPaywallSheet({required this.album});
  final AlbumModel album;

  @override
  State<_AlbumPaywallSheet> createState() => _AlbumPaywallSheetState();
}

class _AlbumPaywallSheetState extends State<_AlbumPaywallSheet> {
  bool _loading = false;
  String? _errorMsg;

  Future<void> _handleBuy() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    final result = await PurchaseService.instance.buyAlbum(
      albumId: widget.album.id,
      price: widget.album.price,
    );

    if (!mounted) return;

    switch (result) {
      case PurchaseResult.success:
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: const Color(0xFF00C37A).withValues(alpha: 0.4),
              ),
            ),
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF00C37A),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '"${widget.album.title}" unlocked!',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        break;

      case PurchaseResult.alreadyOwned:
        Navigator.pop(context);
        break;

      case PurchaseResult.cancelled:
        setState(() {
          _loading = false;
        });
        break;

      case PurchaseResult.error:
        setState(() {
          _loading = false;
          _errorMsg = 'Purchase failed. Please try again.';
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: widget.album.coverUrl.isNotEmpty
                  ? Image.network(
                      widget.album.coverUrl,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 100,
                        height: 100,
                        color: AppColors.surfaceLight,
                        child: const Icon(
                          Icons.album_rounded,
                          color: AppColors.textSecondary,
                          size: 44,
                        ),
                      ),
                    )
                  : Container(
                      width: 100,
                      height: 100,
                      color: AppColors.surfaceLight,
                      child: const Icon(
                        Icons.album_rounded,
                        color: AppColors.textSecondary,
                        size: 44,
                      ),
                    ),
            ),
            const SizedBox(height: 14),

            // Title + artist
            Text(
              widget.album.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 3),
            Text(
              widget.album.artistName,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.album.trackCount} tracks',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),

            // Info card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.accent, AppColors.primary],
                      ),
                    ),
                    child: const Icon(
                      Icons.album_rounded,
                      color: AppColors.background,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Premium Album',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Unlock all ${widget.album.trackCount} tracks for \$${widget.album.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Error
            if (_errorMsg != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMsg!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Buy button
            GestureDetector(
              onTap: _loading ? null : _handleBuy,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _loading
                        ? [
                            AppColors.primary.withValues(alpha: 0.5),
                            AppColors.accent.withValues(alpha: 0.5),
                          ]
                        : [AppColors.accent, AppColors.primary],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _loading
                      ? null
                      : [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 5),
                          ),
                        ],
                ),
                child: Center(
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Buy Album for \$${widget.album.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.background,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Dismiss
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Maybe later',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SONG PAYWALL SHEET
// ══════════════════════════════════════════════════════════════════════════════
class _SongPaywallSheet extends StatefulWidget {
  const _SongPaywallSheet({required this.song});
  final SongModel song;

  @override
  State<_SongPaywallSheet> createState() => _SongPaywallSheetState();
}

class _SongPaywallSheetState extends State<_SongPaywallSheet> {
  bool _loading = false;
  String? _errorMsg;

  Future<void> _handleBuy() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    final result = await PurchaseService.instance.buySingle(
      songId: widget.song.id,
      price: widget.song.price,
    );

    if (!mounted) return;

    switch (result) {
      case PurchaseResult.success:
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: const Color(0xFF00C37A).withValues(alpha: 0.4),
              ),
            ),
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF00C37A),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '"${widget.song.title}" unlocked!',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        break;

      case PurchaseResult.alreadyOwned:
        Navigator.pop(context);
        break;

      case PurchaseResult.cancelled:
        setState(() {
          _loading = false;
        });
        break;

      case PurchaseResult.error:
        setState(() {
          _loading = false;
          _errorMsg = 'Purchase failed. Please try again.';
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 22),

            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: widget.song.coverUrl.isNotEmpty
                  ? Image.network(
                      widget.song.coverUrl,
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 88,
                        height: 88,
                        color: AppColors.surfaceLight,
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: AppColors.textSecondary,
                          size: 36,
                        ),
                      ),
                    )
                  : Container(
                      width: 88,
                      height: 88,
                      color: AppColors.surfaceLight,
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: AppColors.textSecondary,
                        size: 36,
                      ),
                    ),
            ),
            const SizedBox(height: 14),

            // Title + artist
            Text(
              widget.song.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 3),
            Text(
              widget.song.artistName,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),

            // Info card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.accent, AppColors.primary],
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: AppColors.background,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Premium Track',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Unlock this track for \$${widget.song.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Error
            if (_errorMsg != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMsg!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Buy button
            GestureDetector(
              onTap: _loading ? null : _handleBuy,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _loading
                        ? [
                            AppColors.primary.withValues(alpha: 0.5),
                            AppColors.accent.withValues(alpha: 0.5),
                          ]
                        : [AppColors.accent, AppColors.primary],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _loading
                      ? null
                      : [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Center(
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Buy for \$${widget.song.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.background,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Maybe later',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
