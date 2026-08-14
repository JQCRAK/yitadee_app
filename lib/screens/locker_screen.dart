import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/app_theme.dart';
import '../models/song_model.dart';
import '../models/album_model.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../services/purchase_service.dart';
import 'music/album_detail_screen.dart';
import 'music/full_player_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
// LOCKER SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class LockerScreen extends StatefulWidget {
  const LockerScreen({super.key});

  @override
  State<LockerScreen> createState() => _LockerScreenState();
}

class _LockerScreenState extends State<LockerScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // ── Favorites (Songs tab) ─────────────────────────────────────────────────
  List<SongModel>  _favSongs    = [];
  bool             _loadingFavs = true;

  // ── Purchased (Purchased tab) ─────────────────────────────────────────────
  List<SongModel>  _purchasedSongs  = [];
  List<AlbumModel> _purchasedAlbums = [];
  bool             _loadingPurchased = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    FavoritesService.instance.addListener(_onFavChanged);
    PlayerService.instance.addListener(_rebuild);
    PurchaseService.instance.addListener(_onPurchaseChanged);
    _loadFavorites();
    _loadPurchased();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    FavoritesService.instance.removeListener(_onFavChanged);
    PlayerService.instance.removeListener(_rebuild);
    PurchaseService.instance.removeListener(_onPurchaseChanged);
    super.dispose();
  }

  void _rebuild()          { if (mounted) setState(() {}); }
  void _onFavChanged()     { if (mounted) _loadFavorites(); }
  void _onPurchaseChanged(){ if (mounted) _loadPurchased(); }

  // ── Load favorite songs from Firestore ───────────────────────────────────
  Future<void> _loadFavorites() async {
    final ids = FavoritesService.instance.favorites.toList();
    if (ids.isEmpty) {
      if (mounted) setState(() { _favSongs = []; _loadingFavs = false; });
      return;
    }

    const chunkSize = 30;

    Future<List<SongModel>> fetchSongs(List<String> chunk) async {
      final snap = await FirebaseFirestore.instance
          .collection('songs')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      return snap.docs.map(SongModel.fromDoc).toList();
    }

    final allSongs = <SongModel>[];

    for (int i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.skip(i).take(chunkSize).toList();
      allSongs.addAll(await fetchSongs(chunk));
    }

    allSongs.sort((a, b) => ids.indexOf(a.id).compareTo(ids.indexOf(b.id)));

    if (!mounted) return;
    setState(() {
      _favSongs    = allSongs;
      _loadingFavs = false;
    });
  }

  // ── Load purchased content from PurchaseService locker ───────────────────
  Future<void> _loadPurchased() async {
    if (!mounted) return;
    setState(() => _loadingPurchased = true);

    final locker = PurchaseService.instance.lockerEntries;

    if (locker.isEmpty) {
      if (mounted) {
        setState(() {
          _purchasedSongs  = [];
          _purchasedAlbums = [];
          _loadingPurchased = false;
        });
      }
      return;
    }

    final albumIds  = locker.where((e) => e.contentType == 'album') .map((e) => e.contentId).toList();
    final singleIds = locker.where((e) => e.contentType == 'single').map((e) => e.contentId).toList();

    final songs  = <SongModel>[];
    final albums = <AlbumModel>[];

    // Fetch purchased singles
    for (int i = 0; i < singleIds.length; i += 30) {
      final chunk = singleIds.skip(i).take(30).toList();
      final snap  = await FirebaseFirestore.instance
          .collection('songs')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      songs.addAll(snap.docs.map(SongModel.fromDoc));
    }

    // Fetch purchased albums
    for (int i = 0; i < albumIds.length; i += 30) {
      final chunk = albumIds.skip(i).take(30).toList();
      final snap  = await FirebaseFirestore.instance
          .collection('albums')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      albums.addAll(snap.docs.map(AlbumModel.fromDoc));
    }

    // Sort by purchase date (most recent first)
    final lockerMap = { for (final e in locker) e.contentId: e };
    songs.sort((a, b)  => (lockerMap[b.id]?.purchasedAt  ?? DateTime(0))
        .compareTo(lockerMap[a.id]?.purchasedAt  ?? DateTime(0)));
    albums.sort((a, b) => (lockerMap[b.id]?.purchasedAt ?? DateTime(0))
        .compareTo(lockerMap[a.id]?.purchasedAt ?? DateTime(0)));

    if (!mounted) return;
    setState(() {
      _purchasedSongs   = songs;
      _purchasedAlbums  = albums;
      _loadingPurchased = false;
    });
  }

  // ── Playback helpers ──────────────────────────────────────────────────────
  void _playSong(SongModel song) {
    // Song is paid and not unlocked → show paywall
    if (song.isPaid && !PurchaseService.instance.isUnlocked(song.id)) {
      _showSongPaywall(song);
      return;
    }
    if (song.isAlbumTrack) { _openAlbumForSong(song); return; }

    final playable = _favSongs
        .where((s) => s.isSingle &&
            (!s.isPaid || PurchaseService.instance.isUnlocked(s.id)))
        .toList();
    final idx = playable.indexWhere((s) => s.id == song.id);
    PlayerService.instance.playSong(
        song, queue: playable, index: idx < 0 ? 0 : idx);
    _openPlayer();
  }

  void _playPurchasedSong(SongModel song) {
    if (song.isAlbumTrack) { _openAlbumForSong(song); return; }
    final idx = _purchasedSongs.indexWhere((s) => s.id == song.id);
    PlayerService.instance.playSong(
        song, queue: _purchasedSongs, index: idx < 0 ? 0 : idx);
    _openPlayer();
  }

  void _openPlayer() =>
      Navigator.of(context).push(_slideUp(const FullPlayerScreen()));

  void _openAlbum(AlbumModel album) =>
      Navigator.of(context).push(_slideUp(AlbumDetailScreen(album: album)));

  Future<void> _openAlbumForSong(SongModel song) async {
    final doc = await FirebaseFirestore.instance
        .collection('albums')
        .doc(song.albumId)
        .get();
    if (!doc.exists || !mounted) return;
    _openAlbum(AlbumModel.fromDoc(doc));
  }

  void _showSongPaywall(SongModel song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SongPaywallSheet(song: song),
    );
  }

  Future<void> _refreshFavs() async {
    setState(() => _loadingFavs = true);
    await FavoritesService.instance.loadFavorites();
    await _loadFavorites();
  }

  Future<void> _refreshPurchased() async {
    await PurchaseService.instance.reloadLocker();
    await _loadPurchased();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _LockerHeader(tabCtrl: _tabCtrl),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // ── Tab 1: Favorite Songs ────────────────────────────────
              _loadingFavs
                  ? const Center(child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2))
                  : _SongsTab(
                      songs:     _favSongs,
                      onPlay:    _playSong,
                      onRefresh: _refreshFavs,
                    ),

              // ── Tab 2: Purchased ─────────────────────────────────────
              _loadingPurchased
                  ? const Center(child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2))
                  : _PurchasedTab(
                      songs:     _purchasedSongs,
                      albums:    _purchasedAlbums,
                      onPlaySong: _playPurchasedSong,
                      onOpenAlbum: _openAlbum,
                      onRefresh:  _refreshPurchased,
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HEADER
// ══════════════════════════════════════════════════════════════════════════════
class _LockerHeader extends StatelessWidget {
  const _LockerHeader({required this.tabCtrl});
  final TabController tabCtrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          _SegmentedBar(tabCtrl: tabCtrl),
        ],
      ),
    );
  }
}

class _SegmentedBar extends StatefulWidget {
  const _SegmentedBar({required this.tabCtrl});
  final TabController tabCtrl;

  @override
  State<_SegmentedBar> createState() => _SegmentedBarState();
}

class _SegmentedBarState extends State<_SegmentedBar> {
  int _sel = 0;

  @override
  void initState() {
    super.initState();
    widget.tabCtrl.addListener(_sync);
  }

  void _sync() {
    if (mounted && widget.tabCtrl.index != _sel) {
      setState(() => _sel = widget.tabCtrl.index);
    }
  }

  @override
  void dispose() {
    widget.tabCtrl.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show purchase count badge on Purchased tab
    final purchaseCount = PurchaseService.instance.lockerEntries.length;

    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border:       Border.all(color: AppColors.surfaceLight),
      ),
      child: Row(children: [
        _SegTab(
          label:  'Songs',
          active: _sel == 0,
          onTap:  () { widget.tabCtrl.animateTo(0); setState(() => _sel = 0); },
        ),
        _SegTab(
          label:  purchaseCount > 0
              ? 'Purchased ($purchaseCount)'
              : 'Purchased',
          active: _sel == 1,
          onTap:  () { widget.tabCtrl.animateTo(1); setState(() => _sel = 1); },
        ),
      ]),
    );
  }
}

class _SegTab extends StatelessWidget {
  const _SegTab({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String       label;
  final bool         active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve:    Curves.easeOutCubic,
        decoration: BoxDecoration(
          color:        active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active
              ? [BoxShadow(
                  color:      AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 8,
                  offset:     const Offset(0, 2))]
              : null,
        ),
        child: Center(
          child: Text(label,
            style: TextStyle(
              color:      active ? AppColors.background : AppColors.textSecondary,
              fontSize:   12,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            )),
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SONGS TAB — favorites
// ══════════════════════════════════════════════════════════════════════════════
class _SongsTab extends StatelessWidget {
  const _SongsTab({
    required this.songs,
    required this.onPlay,
    required this.onRefresh,
  });

  final List<SongModel>          songs;
  final void Function(SongModel) onPlay;
  final Future<void> Function()  onRefresh;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const _EmptyState(
        icon:    Icons.favorite_border_rounded,
        title:   'No favorite songs yet',
        message: 'Tap the ♥ on any song\nto save it here.',
      );
    }

    return RefreshIndicator(
      color:           AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh:       onRefresh,
      child: ListView.builder(
        padding:   const EdgeInsets.fromLTRB(16, 4, 16, 140),
        itemCount: songs.length,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: _FavSongRow(
            song:  songs[i],
            index: i,
            onTap: () => onPlay(songs[i]),
          ),
        ),
      ),
    );
  }
}

// ── Favorite Song Row ─────────────────────────────────────────────────────────
class _FavSongRow extends StatelessWidget {
  const _FavSongRow({
    required this.song,
    required this.index,
    required this.onTap,
  });

  final SongModel    song;
  final int          index;
  final VoidCallback onTap;

  bool get _isLocked  => song.isPaid && !PurchaseService.instance.isUnlocked(song.id);
  bool get _isActive  => PlayerService.instance.currentSong?.id == song.id;
  bool get _isPlaying => _isActive && PlayerService.instance.isPlaying;

  @override
  Widget build(BuildContext context) {
    final isLocked  = _isLocked;
    final isActive  = _isActive;
    final isPlaying = _isPlaying;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.07)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.38)
                : AppColors.surfaceLight,
            width: isActive ? 1.2 : 1,
          ),
        ),
        child: Row(children: [
          // Index / wave
          SizedBox(
            width: 26,
            child: isLocked
                ? const Icon(Icons.lock_rounded,
                    color: AppColors.primary, size: 13)
                : isActive
                    ? (isPlaying
                        ? const _MiniWave()
                        : const Icon(Icons.pause_rounded,
                            color: AppColors.primary, size: 15))
                    : Text(
                        '${(index + 1).toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color:      AppColors.textSecondary,
                          fontSize:   11,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
          ),
          const SizedBox(width: 8),

          // Cover
          Stack(clipBehavior: Clip.none, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColorFiltered(
                colorFilter: isLocked
                    ? const ColorFilter.matrix([
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0,      0,      0,      1, 0,
                      ])
                    : const ColorFilter.mode(
                        Colors.transparent, BlendMode.multiply),
                child: _Cover(url: song.coverUrl, size: 44),
              ),
            ),
            if (isLocked)
              Positioned(
                top: -3, right: -3,
                child: Container(
                  width: 13, height: 13,
                  decoration: const BoxDecoration(
                    shape:    BoxShape.circle,
                    gradient: LinearGradient(
                        colors: [AppColors.accent, AppColors.primary]),
                  ),
                  child: const Icon(Icons.lock_rounded,
                      color: AppColors.background, size: 7),
                ),
              ),
          ]),
          const SizedBox(width: 10),

          // Info
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(song.title,
                style: TextStyle(
                  color: isActive
                      ? AppColors.primary
                      : isLocked
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                  fontSize:      13,
                  fontWeight:    FontWeight.w800,
                  letterSpacing: -0.2,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(
                  child: Text(
                    song.featuring.isNotEmpty
                        ? '${song.artistName} · ft. ${song.featuring}'
                        : song.artistName,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10.5),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color:        AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(song.genreDisplay,
                    style: const TextStyle(
                      color:      AppColors.textSecondary,
                      fontSize:   9,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
              if (song.isAlbumTrack && song.albumTitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(children: [
                    const Icon(Icons.album_rounded,
                        color: AppColors.primary, size: 9),
                    const SizedBox(width: 3),
                    Flexible(child: Text(song.albumTitle,
                      style: const TextStyle(
                        color:      AppColors.primary,
                        fontSize:   9.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ],
          )),
          const SizedBox(width: 8),

          // Right
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PricePill(
                isPaid:     song.isPaid,
                price:      song.price,
                isUnlocked: !isLocked && song.isPaid,
              ),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: () =>
                      FavoritesService.instance.toggleFavorite(song.id),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.favorite_rounded,
                        color: AppColors.primary, size: 15),
                  ),
                ),
                const SizedBox(width: 2),
                Text(song.durationDisplay,
                  style: TextStyle(
                    color: isLocked
                        ? AppColors.textSecondary.withValues(alpha: 0.5)
                        : AppColors.textSecondary,
                    fontSize:   10,
                    fontWeight: FontWeight.w600,
                  )),
              ]),
            ],
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PURCHASED TAB — albums + singles from locker
// ══════════════════════════════════════════════════════════════════════════════
class _PurchasedTab extends StatelessWidget {
  const _PurchasedTab({
    required this.songs,
    required this.albums,
    required this.onPlaySong,
    required this.onOpenAlbum,
    required this.onRefresh,
  });

  final List<SongModel>           songs;
  final List<AlbumModel>          albums;
  final void Function(SongModel)  onPlaySong;
  final void Function(AlbumModel) onOpenAlbum;
  final Future<void> Function()   onRefresh;

  bool get _empty => songs.isEmpty && albums.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (_empty) {
      return RefreshIndicator(
        color:           AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh:       onRefresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 140),
          children: const [
            SizedBox(height: 100),
            _EmptyState(
              icon:    Icons.shopping_bag_outlined,
              title:   'No purchases yet',
              message: 'Your purchased albums\nand singles will appear here.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color:           AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh:       onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
        children: [
          // ── Purchased Albums ───────────────────────────────────────
          if (albums.isNotEmpty) ...[
            _SectionLabel(
              icon: Icons.album_rounded,
              text: 'Albums',
              sub:  '· ${albums.length}',
            ),
            GridView.builder(
              shrinkWrap:  true,
              physics:     const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:   2,
                crossAxisSpacing: 10,
                mainAxisSpacing:  10,
                childAspectRatio: 0.72,
              ),
              itemCount:   albums.length,
              itemBuilder: (ctx, i) => _PurchasedAlbumCard(
                album: albums[i],
                onTap: () => onOpenAlbum(albums[i]),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Purchased Singles ──────────────────────────────────────
          if (songs.isNotEmpty) ...[
            _SectionLabel(
              icon: Icons.music_note_rounded,
              text: 'Singles',
              sub:  '· ${songs.length}',
            ),
            ...songs.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _PurchasedSongRow(
                song:  e.value,
                index: e.key,
                onTap: () => onPlaySong(e.value),
              ),
            )),
          ],
        ],
      ),
    );
  }
}

// ── Purchased Album Card ──────────────────────────────────────────────────────
class _PurchasedAlbumCard extends StatelessWidget {
  const _PurchasedAlbumCard({required this.album, required this.onTap});

  final AlbumModel   album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: AppColors.surfaceLight),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Stack(fit: StackFit.expand, children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft:  Radius.circular(13),
                topRight: Radius.circular(13),
              ),
              child: _Cover(url: album.coverUrl),
            ),
            // Bottom fade
            Positioned(
              bottom: 0, left: 0, right: 0, height: 36,
              child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin:  Alignment.bottomCenter,
                  end:    Alignment.topCenter,
                  colors: [AppColors.surface, Colors.transparent],
                ),
              )),
            ),
            // OWNED badge top-right
            Positioned(
              top: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:        const Color(0xFF00C37A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                      color: const Color(0xFF00C37A).withValues(alpha: 0.35)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded,
                      color: Color(0xFF00C37A), size: 8),
                  SizedBox(width: 3),
                  Text('OWNED',
                    style: TextStyle(
                      color:         Color(0xFF00C37A),
                      fontSize:      8,
                      fontWeight:    FontWeight.w900,
                      letterSpacing: 0.5,
                    )),
                ]),
              ),
            ),
            // Open arrow bottom-right
            Positioned(
              bottom: 5, right: 6,
              child: Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(
                  shape:    BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [AppColors.accent, AppColors.primary]),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: AppColors.background, size: 12),
              ),
            ),
          ])),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(album.title,
                style: const TextStyle(
                  color:         AppColors.textPrimary,
                  fontWeight:    FontWeight.w800,
                  fontSize:      12.5,
                  letterSpacing: -0.2,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(album.artistName,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10.5),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 7),
              Row(children: [
                Text('${album.trackCount} tracks',
                  style: const TextStyle(
                    color:      AppColors.textSecondary,
                    fontSize:   9.5,
                    fontWeight: FontWeight.w600,
                  )),
                const Spacer(),
                Container(
                  width: 22, height: 22,
                  decoration: const BoxDecoration(
                    shape:    BoxShape.circle,
                    gradient: LinearGradient(
                        colors: [AppColors.accent, AppColors.primary]),
                  ),
                  child: const Icon(Icons.arrow_forward_ios_rounded,
                      color: AppColors.background, size: 9),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Purchased Song Row ────────────────────────────────────────────────────────
class _PurchasedSongRow extends StatelessWidget {
  const _PurchasedSongRow({
    required this.song,
    required this.index,
    required this.onTap,
  });

  final SongModel    song;
  final int          index;
  final VoidCallback onTap;

  bool get _isActive  => PlayerService.instance.currentSong?.id == song.id;
  bool get _isPlaying => _isActive && PlayerService.instance.isPlaying;

  @override
  Widget build(BuildContext context) {
    final isActive  = _isActive;
    final isPlaying = _isPlaying;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.07)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.38)
                : AppColors.surfaceLight,
            width: isActive ? 1.2 : 1,
          ),
        ),
        child: Row(children: [
          // Index / wave
          SizedBox(
            width: 26,
            child: isActive
                ? (isPlaying
                    ? const _MiniWave()
                    : const Icon(Icons.pause_rounded,
                        color: AppColors.primary, size: 15))
                : Text(
                    '${(index + 1).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color:      AppColors.textSecondary,
                      fontSize:   11,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
          ),
          const SizedBox(width: 8),

          // Cover
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _Cover(url: song.coverUrl, size: 44),
          ),
          const SizedBox(width: 10),

          // Info
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(song.title,
                style: TextStyle(
                  color:         isActive ? AppColors.primary : AppColors.textPrimary,
                  fontSize:      13,
                  fontWeight:    FontWeight.w800,
                  letterSpacing: -0.2,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                song.featuring.isNotEmpty
                    ? '${song.artistName} · ft. ${song.featuring}'
                    : song.artistName,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10.5),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ],
          )),
          const SizedBox(width: 8),

          // Right — OWNED badge + duration
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:        const Color(0xFF00C37A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                      color: const Color(0xFF00C37A).withValues(alpha: 0.35)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded,
                      color: Color(0xFF00C37A), size: 8),
                  SizedBox(width: 3),
                  Text('OWNED',
                    style: TextStyle(
                      color:         Color(0xFF00C37A),
                      fontSize:      8,
                      fontWeight:    FontWeight.w900,
                      letterSpacing: 0.5,
                    )),
                ]),
              ),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                  size: 14),
                const SizedBox(width: 3),
                Text(song.durationDisplay,
                  style: const TextStyle(
                    color:      AppColors.textSecondary,
                    fontSize:   10,
                    fontWeight: FontWeight.w600,
                  )),
              ]),
            ],
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SONG PAYWALL SHEET — real purchase
// ══════════════════════════════════════════════════════════════════════════════
class _SongPaywallSheet extends StatefulWidget {
  const _SongPaywallSheet({required this.song});
  final SongModel song;

  @override
  State<_SongPaywallSheet> createState() => _SongPaywallSheetState();
}

class _SongPaywallSheetState extends State<_SongPaywallSheet> {
  bool    _loading  = false;
  String? _errorMsg;

  Future<void> _handleBuy() async {
    setState(() { _loading = true; _errorMsg = null; });

    final result = await PurchaseService.instance.buySingle(
      songId: widget.song.id,
      price:  widget.song.price,
    );

    if (!mounted) return;

    switch (result) {
      case PurchaseResult.success:
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: const Color(0xFF00C37A).withValues(alpha: 0.4)),
          ),
          content: Row(children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF00C37A), size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text('"${widget.song.title}" unlocked!',
              style: const TextStyle(
                  color:      AppColors.textPrimary,
                  fontSize:   13,
                  fontWeight: FontWeight.w700))),
          ]),
          duration: const Duration(seconds: 3),
        ));
        break;
      case PurchaseResult.alreadyOwned:
        Navigator.pop(context);
        break;
      case PurchaseResult.cancelled:
        setState(() { _loading = false; });
        break;
      case PurchaseResult.error:
        setState(() { _loading = false; _errorMsg = 'Purchase failed. Please try again.'; });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin:  const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border:       Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _Cover(url: widget.song.coverUrl, size: 90),
          ),
          const SizedBox(height: 14),
          Text(widget.song.title,
            style: const TextStyle(color: AppColors.textPrimary,
                fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.4),
            textAlign: TextAlign.center),
          const SizedBox(height: 3),
          Text(widget.song.artistName,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:        AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border:       Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
            ),
            child: Row(children: [
              Container(width: 38, height: 38,
                decoration: const BoxDecoration(shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [AppColors.accent, AppColors.primary])),
                child: const Icon(Icons.lock_rounded, color: AppColors.background, size: 16)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Premium Track',
                  style: TextStyle(color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700, fontSize: 13)),
                Text('Unlock for \$${widget.song.price.toStringAsFixed(0)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ])),
            ]),
          ),
          const SizedBox(height: 18),
          if (_errorMsg != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMsg!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
              ])),
            const SizedBox(height: 12),
          ],
          GestureDetector(
            onTap: _loading ? null : _handleBuy,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity, height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _loading
                    ? [AppColors.primary.withValues(alpha: 0.5),
                       AppColors.accent.withValues(alpha: 0.5)]
                    : [AppColors.accent, AppColors.primary]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: _loading ? null : [BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 14, offset: const Offset(0, 4))],
              ),
              child: Center(child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Buy for \$${widget.song.price.toStringAsFixed(0)}',
                    style: const TextStyle(color: AppColors.background,
                        fontWeight: FontWeight.w900, fontSize: 15))))),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Maybe later',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)))),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.text,
    this.sub,
  });
  final IconData icon;
  final String   text;
  final String?  sub;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
    child: Row(children: [
      Icon(icon, size: 13, color: AppColors.primary),
      const SizedBox(width: 6),
      Text(text,
        style: const TextStyle(
          color:         AppColors.textPrimary,
          fontSize:      13,
          fontWeight:    FontWeight.w800,
          letterSpacing: 0.1,
        )),
      if (sub != null) ...[
        const SizedBox(width: 5),
        Text(sub!, style: const TextStyle(
            color: AppColors.textSecondary, fontSize: 11)),
      ],
    ]),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String   title;
  final String   message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color:  AppColors.surface,
          shape:  BoxShape.circle,
          border: Border.all(color: AppColors.surfaceLight),
        ),
        child: Icon(icon, color: AppColors.surfaceLight, size: 32),
      ),
      const SizedBox(height: 16),
      Text(title,
        style: const TextStyle(
          color:      AppColors.textPrimary,
          fontSize:   15,
          fontWeight: FontWeight.w700,
        )),
      const SizedBox(height: 6),
      Text(message,
        style: const TextStyle(
          color:    AppColors.textSecondary,
          fontSize: 13,
          height:   1.6,
        ),
        textAlign: TextAlign.center),
    ]),
  );
}

class _PricePill extends StatelessWidget {
  const _PricePill({
    required this.isPaid,
    required this.price,
    this.isUnlocked = false,
  });
  final bool   isPaid;
  final double price;
  final bool   isUnlocked;

  @override
  Widget build(BuildContext context) {
    if (!isPaid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color:        const Color(0xFF00C37A).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF00C37A).withValues(alpha: 0.35)),
        ),
        child: const Text('FREE',
          style: TextStyle(color: Color(0xFF00C37A),
              fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)));
    }
    if (isUnlocked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color:        const Color(0xFF00C37A).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF00C37A).withValues(alpha: 0.35)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF00C37A), size: 8),
          SizedBox(width: 3),
          Text('OWNED',
            style: TextStyle(color: Color(0xFF00C37A),
                fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ]));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient:     const LinearGradient(
            colors: [AppColors.accent, AppColors.primary]),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text('\$${price.toStringAsFixed(0)}',
        style: const TextStyle(color: AppColors.background,
            fontSize: 9, fontWeight: FontWeight.w900)));
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, this.size});
  final String  url;
  final double? size;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _CoverFallback(size: size);
    return Image.network(
      url, width: size, height: size, fit: BoxFit.cover,
      cacheWidth: size != null
          ? (size! * MediaQuery.of(context).devicePixelRatio).toInt()
          : null,
      errorBuilder: (_, __, ___) => _CoverFallback(size: size),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({this.size});
  final double? size;

  @override
  Widget build(BuildContext context) => Container(
    width:  size, height: size,
    color:  AppColors.surfaceLight,
    child:  const Center(child: Icon(Icons.music_note_rounded,
        color: AppColors.textSecondary, size: 22)),
  );
}

class _MiniWave extends StatefulWidget {
  const _MiniWave();
  @override
  State<_MiniWave> createState() => _MiniWaveState();
}

class _MiniWaveState extends State<_MiniWave> with TickerProviderStateMixin {
  late final List<AnimationController> _c;

  @override
  void initState() {
    super.initState();
    _c = List.generate(3, (i) => AnimationController(
      vsync:    this,
      duration: Duration(milliseconds: 350 + i * 100),
    )..repeat(reverse: true));
  }

  @override
  void dispose() {
    for (final c in _c) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize:       MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: List.generate(3, (i) => AnimatedBuilder(
      animation: _c[i],
      builder: (_, __) => Container(
        width: 2.5, height: 5 + _c[i].value * 9,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color:        AppColors.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    )),
  );
}

PageRoute _slideUp(Widget page) => PageRouteBuilder(
  pageBuilder:        (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) => SlideTransition(
    position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child,
  ),
  transitionDuration: const Duration(milliseconds: 370),
);