import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../models/song_model.dart';
import '../../models/album_model.dart';
import '../../services/player_service.dart';
import '../../services/favorites_service.dart';
import '../../services/purchase_service.dart';
import '../../services/merch_banner_service.dart';
import 'music/album_detail_screen.dart';
import 'music/full_player_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
// SEARCH SERVICE — Firestore queries
// ══════════════════════════════════════════════════════════════════════════════
class _SearchService {
  static final _songs  = FirebaseFirestore.instance.collection('songs');
  static final _albums = FirebaseFirestore.instance.collection('albums');

  static Future<List<SongModel>> fetchTrendingSongs({int limit = 6}) async {
    final snap = await _songs
        .orderBy('plays', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(SongModel.fromDoc).toList();
  }

  static Future<List<AlbumModel>> fetchFeaturedAlbums({int limit = 4}) async {
    final snap = await _albums
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(AlbumModel.fromDoc).toList();
  }

  static Future<List<SongModel>> searchSongs(String query) async {
    if (query.trim().isEmpty) return [];
    final q    = query.trim().toLowerCase();
    final snap = await _songs.orderBy('title').get();
    return snap.docs
        .map(SongModel.fromDoc)
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            s.artistName.toLowerCase().contains(q) ||
            s.featuring.toLowerCase().contains(q) ||
            s.genreDisplay.toLowerCase().contains(q))
        .toList();
  }

  static Future<List<AlbumModel>> searchAlbums(String query) async {
    if (query.trim().isEmpty) return [];
    final q    = query.trim().toLowerCase();
    final snap = await _albums.orderBy('title').get();
    return snap.docs
        .map(AlbumModel.fromDoc)
        .where((a) =>
            a.title.toLowerCase().contains(q) ||
            a.artistName.toLowerCase().contains(q))
        .toList();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SEARCH SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _ctrl   = TextEditingController();
  final _focus  = FocusNode();
  final _scroll = ScrollController();

  String _query       = '';
  bool   _searching   = false;
  bool   _hasSearched = false;

  List<SongModel>  _songResults  = [];
  List<AlbumModel> _albumResults = [];

  List<SongModel>  _trending         = [];
  List<AlbumModel> _featured         = [];
  bool             _loadingDiscovery = true;

  String? _shopifyUrl;
  bool    _bannerLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    PlayerService.instance.addListener(_rebuild);
    FavoritesService.instance.addListener(_rebuild);
    PurchaseService.instance.addListener(_rebuild); // ← NEW
    _loadDiscovery();
    _loadBannerUrl();
  }

  void _rebuild() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    PlayerService.instance.removeListener(_rebuild);
    FavoritesService.instance.removeListener(_rebuild);
    PurchaseService.instance.removeListener(_rebuild); // ← NEW
    super.dispose();
  }

  Future<void> _loadBannerUrl() async {
    final url = await MerchBannerService.instance.fetchShopifyUrl();
    if (mounted) setState(() { _shopifyUrl = url ?? ''; _bannerLoaded = true; });
  }

  Future<void> _loadDiscovery() async {
    final results = await Future.wait([
      _SearchService.fetchTrendingSongs(),
      _SearchService.fetchFeaturedAlbums(),
    ]);
    if (!mounted) return;
    setState(() {
      _trending         = results[0] as List<SongModel>;
      _featured         = results[1] as List<AlbumModel>;
      _loadingDiscovery = false;
    });
  }

  Future<void> _runSearch(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _query        = '';
        _hasSearched  = false;
        _songResults  = [];
        _albumResults = [];
        _searching    = false;
      });
      return;
    }
    setState(() { _query = trimmed; _searching = true; _hasSearched = true; });
    final results = await Future.wait([
      _SearchService.searchSongs(trimmed),
      _SearchService.searchAlbums(trimmed),
    ]);
    if (!mounted) return;
    setState(() {
      _songResults  = results[0] as List<SongModel>;
      _albumResults = results[1] as List<AlbumModel>;
      _searching    = false;
    });
  }

  void _clearSearch() {
    _ctrl.clear();
    _runSearch('');
    _focus.unfocus();
  }

  // ── Play logic — checks unlock state before showing paywall ──────────────
  void _playSong(SongModel song, List<SongModel> pool) {
    // Song is paid AND not unlocked → show paywall
    if (song.isPaid && !PurchaseService.instance.isUnlocked(song.id)) {
      _showSongPaywall(song);
      return;
    }
    if (song.isAlbumTrack) {
      _openAlbumForSong(song);
      return;
    }
    // Only free + unlocked singles in the queue
    final playable = pool
        .where((s) => s.isSingle &&
            (!s.isPaid || PurchaseService.instance.isUnlocked(s.id)))
        .toList();
    final idx = playable.indexWhere((s) => s.id == song.id);
    PlayerService.instance.playSong(
        song, queue: playable, index: idx < 0 ? 0 : idx);
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
    final album = AlbumModel.fromDoc(doc);
    Navigator.of(context).push(_slideUp(AlbumDetailScreen(album: album)));
  }

  void _showSongPaywall(SongModel song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SongPaywallSheet(song: song),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GestureDetector(
      onTap: () => _focus.unfocus(),
      child: Column(
        children: [
          _SearchHeader(
            ctrl:      _ctrl,
            focus:     _focus,
            onChanged: _runSearch,
            onClear:   _clearSearch,
            hasText:   _query.isNotEmpty,
          ),
          Expanded(
            child: _hasSearched
                ? _SearchResults(
                    query:         _query,
                    searching:     _searching,
                    songs:         _songResults,
                    albums:        _albumResults,
                    onPlaySong:    _playSong,
                    onOpenAlbum:   _openAlbum,
                    onShowPaywall: _showSongPaywall,
                    bannerLoaded:  _bannerLoaded,
                    shopifyUrl:    _shopifyUrl,
                    onLaunch:      _launch,
                  )
                : _DiscoveryBody(
                    loading:      _loadingDiscovery,
                    trending:     _trending,
                    featured:     _featured,
                    onPlay:       _playSong,
                    onAlbum:      _openAlbum,
                    onPaywall:    _showSongPaywall,
                    bannerLoaded: _bannerLoaded,
                    shopifyUrl:   _shopifyUrl,
                    onLaunch:     _launch,
                  ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SEARCH HEADER
// ══════════════════════════════════════════════════════════════════════════════
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.ctrl,
    required this.focus,
    required this.onChanged,
    required this.onClear,
    required this.hasText,
  });

  final TextEditingController ctrl;
  final FocusNode             focus;
  final ValueChanged<String>  onChanged;
  final VoidCallback          onClear;
  final bool                  hasText;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: AppColors.surfaceLight),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.search_rounded,
                color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller:      ctrl,
                focusNode:       focus,
                onChanged:       onChanged,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14),
                cursorColor:     AppColors.primary,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText:       'Songs, artists, albums…',
                  hintStyle:      TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                  border:         InputBorder.none,
                  isDense:        true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (hasText)
              GestureDetector(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.close_rounded,
                      color: AppColors.textSecondary, size: 18),
                ),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DISCOVERY BODY
// ══════════════════════════════════════════════════════════════════════════════
class _DiscoveryBody extends StatelessWidget {
  const _DiscoveryBody({
    required this.loading,
    required this.trending,
    required this.featured,
    required this.onPlay,
    required this.onAlbum,
    required this.onPaywall,
    required this.bannerLoaded,
    required this.shopifyUrl,
    required this.onLaunch,
  });

  final bool              loading;
  final List<SongModel>   trending;
  final List<AlbumModel>  featured;
  final void Function(SongModel, List<SongModel>) onPlay;
  final void Function(AlbumModel)                 onAlbum;
  final void Function(SongModel)                  onPaywall;
  final bool                                      bannerLoaded;
  final String?                                   shopifyUrl;
  final void Function(String)                     onLaunch;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(
            color: AppColors.primary, strokeWidth: 2),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 140),
      children: [
        if (trending.isNotEmpty) ...[
          _SectionLabel(
            icon:      Icons.local_fire_department_rounded,
            text:      'Trending Now',
            sub:       '· most played',
            iconColor: const Color(0xFFFF6B00),
          ),
          ...trending.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: _TrendingSongRow(
              song:  e.value,
              rank:  e.key + 1,
              pool:  trending,
              onTap: () {
                final song     = e.value;
                final isLocked = song.isPaid &&
                    !PurchaseService.instance.isUnlocked(song.id);
                if (isLocked) {
                  onPaywall(song);
                } else {
                  onPlay(song, trending);
                }
              },
            ),
          )),
          const _Divider(),
        ],

        if (featured.isNotEmpty) ...[
          _SectionLabel(
            icon: Icons.album_rounded,
            text: 'Featured Albums',
            sub:  '· latest drops',
          ),
          SizedBox(
            height: 170,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding:         const EdgeInsets.fromLTRB(16, 0, 16, 0),
              itemCount:       featured.length,
              itemBuilder: (ctx, i) => _FeaturedAlbumCard(
                album: featured[i],
                onTap: () => onAlbum(featured[i]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const _Divider(),
        ],

        const _SectionLabel(
          icon: Icons.category_rounded,
          text: 'Browse by Genre',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing:    8,
            runSpacing: 8,
            children: SongGenre.values
                .where((g) => g != SongGenre.other)
                .map((g) => _GenreChip(genre: g))
                .toList(),
          ),
        ),

        if (bannerLoaded) ...[
          const _Divider(),
          _SearchMerchBanner(shopifyUrl: shopifyUrl, onLaunch: onLaunch),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SEARCH RESULTS
// ══════════════════════════════════════════════════════════════════════════════
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.searching,
    required this.songs,
    required this.albums,
    required this.onPlaySong,
    required this.onOpenAlbum,
    required this.onShowPaywall,
    required this.bannerLoaded,
    required this.shopifyUrl,
    required this.onLaunch,
  });

  final String             query;
  final bool               searching;
  final List<SongModel>    songs;
  final List<AlbumModel>   albums;
  final void Function(SongModel, List<SongModel>) onPlaySong;
  final void Function(AlbumModel)                 onOpenAlbum;
  final void Function(SongModel)                  onShowPaywall;
  final bool                                      bannerLoaded;
  final String?                                   shopifyUrl;
  final void Function(String)                     onLaunch;

  bool get _empty => songs.isEmpty && albums.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2),
            SizedBox(height: 14),
            Text('Searching…',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    if (_empty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color:  AppColors.surface,
                shape:  BoxShape.circle,
                border: Border.all(color: AppColors.surfaceLight),
              ),
              child: const Icon(Icons.search_off_rounded,
                  color: AppColors.surfaceLight, size: 32),
            ),
            const SizedBox(height: 16),
            Text('No results for "$query"',
                style: const TextStyle(
                    color:      AppColors.textPrimary,
                    fontSize:   15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Try a different song, artist or album.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 140),
      children: [
        if (songs.isNotEmpty) ...[
          _SectionLabel(
            icon: Icons.music_note_rounded,
            text: 'Songs',
            sub:  '· ${songs.length} found',
          ),
          ...songs.map((s) {
            final isLocked =
                s.isPaid && !PurchaseService.instance.isUnlocked(s.id);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: _SearchSongRow(
                song: s,
                pool: songs,
                onTap: () {
                  if (isLocked) {
                    onShowPaywall(s);
                  } else {
                    onPlaySong(s, songs);
                  }
                },
              ),
            );
          }),
          if (albums.isNotEmpty) const _Divider(),
        ],

        if (albums.isNotEmpty) ...[
          _SectionLabel(
            icon: Icons.album_rounded,
            text: 'Albums',
            sub:  '· ${albums.length} found',
          ),
          ...albums.map((a) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: _SearchAlbumRow(
              album: a,
              onTap: () => onOpenAlbum(a),
            ),
          )),
        ],

        if (bannerLoaded) ...[
          const _Divider(),
          _SearchMerchBanner(shopifyUrl: shopifyUrl, onLaunch: onLaunch),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MERCH BANNER
// ══════════════════════════════════════════════════════════════════════════════
class _SearchMerchBanner extends StatelessWidget {
  const _SearchMerchBanner({required this.shopifyUrl, required this.onLaunch});
  final String?               shopifyUrl;
  final void Function(String) onLaunch;

  Future<void> _handleTap(BuildContext ctx) async {
    final url = shopifyUrl;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        content: Row(children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
                colors: [AppColors.accent, AppColors.primary])
                .createShader(b),
            child: const Icon(Icons.rocket_launch_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text(
            'Merch store coming soon! Stay tuned.',
            style: TextStyle(
                color:      AppColors.textPrimary,
                fontSize:   12,
                fontWeight: FontWeight.w600),
          )),
        ]),
        duration: const Duration(seconds: 3),
      ));
      return;
    }
    onLaunch(url);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 5,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color:      Colors.black.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset:     const Offset(0, 6)),
                    BoxShadow(
                        color:      AppColors.primary.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset:     const Offset(0, 4)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/merch_banner.png',
                    
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            if (shopifyUrl == null || shopifyUrl!.isEmpty)
              Positioned(
                top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:        Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color:
                            AppColors.surfaceLight.withValues(alpha: 0.4)),
                  ),
                  child: const Text('Coming Soon',
                    style: TextStyle(
                        color:         AppColors.textSecondary,
                        fontSize:      9,
                        fontWeight:    FontWeight.w700,
                        letterSpacing: 0.5)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TRENDING SONG ROW
// ══════════════════════════════════════════════════════════════════════════════
class _TrendingSongRow extends StatelessWidget {
  const _TrendingSongRow({
    required this.song,
    required this.rank,
    required this.pool,
    required this.onTap,
  });

  final SongModel       song;
  final int             rank;
  final List<SongModel> pool;
  final VoidCallback    onTap;

  bool get _isLocked  => song.isPaid && !PurchaseService.instance.isUnlocked(song.id);
  bool get _isActive  => PlayerService.instance.currentSong?.id == song.id;
  bool get _isPlaying => _isActive && PlayerService.instance.isPlaying;
  bool get _isFav     => FavoritesService.instance.isFavorite(song.id);

  @override
  Widget build(BuildContext context) {
    final isLocked  = _isLocked;
    final isActive  = _isActive;
    final isPlaying = _isPlaying;
    final isFav     = _isFav;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
        child: Row(
          children: [
            // Rank
            SizedBox(
              width: 28,
              child: isActive
                  ? (isPlaying
                      ? const _MiniWave()
                      : const Icon(Icons.play_arrow_rounded,
                          color: AppColors.primary, size: 18))
                  : Text(
                      rank <= 3 ? _rankEmoji(rank) : '$rank',
                      style: TextStyle(
                        color:      rank <= 3
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize:   rank <= 3 ? 16 : 12,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
            const SizedBox(width: 8),

            // Cover
            Stack(clipBehavior: Clip.none, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
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
                  child: _Cover(url: song.coverUrl, size: 46),
                ),
              ),
              if (isLocked)
                Positioned(
                  top: -3, right: -3,
                  child: Container(
                    width: 14, height: 14,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                    style: TextStyle(
                      color:         isActive
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
                            color: AppColors.textSecondary, fontSize: 11),
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
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Right: plays + fav + button
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize:       MainAxisSize.min,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.play_circle_outline_rounded,
                      color: AppColors.textSecondary, size: 11),
                  const SizedBox(width: 3),
                  Text(_formatPlays(song.plays),
                    style: const TextStyle(
                      color:      AppColors.textSecondary,
                      fontSize:   10,
                      fontWeight: FontWeight.w600,
                    )),
                ]),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!isLocked)
                    GestureDetector(
                      onTap: () =>
                          FavoritesService.instance.toggleFavorite(song.id),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (c, a) =>
                              ScaleTransition(scale: a, child: c),
                          child: Icon(
                            isFav
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            key:   ValueKey(isFav),
                            color: isFav
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            size:  15,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 8),
                  const SizedBox(width: 2),
                  Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isLocked
                          ? const LinearGradient(
                              colors: [AppColors.accent, AppColors.primary])
                          : isActive
                              ? const LinearGradient(
                                  colors: [AppColors.accent, AppColors.primary])
                              : null,
                      color: (!isLocked && !isActive)
                          ? AppColors.surfaceLight
                          : null,
                    ),
                    child: Icon(
                      isLocked
                          ? Icons.lock_rounded
                          : (isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                      color: (isLocked || isActive)
                          ? AppColors.background
                          : AppColors.textSecondary,
                      size: 12,
                    ),
                  ),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _rankEmoji(int rank) {
    switch (rank) {
      case 1:  return '🥇';
      case 2:  return '🥈';
      case 3:  return '🥉';
      default: return '$rank';
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SEARCH SONG ROW
// ══════════════════════════════════════════════════════════════════════════════
class _SearchSongRow extends StatelessWidget {
  const _SearchSongRow({
    required this.song,
    required this.pool,
    required this.onTap,
  });

  final SongModel       song;
  final List<SongModel> pool;
  final VoidCallback    onTap;

  bool get _isLocked  => song.isPaid && !PurchaseService.instance.isUnlocked(song.id);
  bool get _isActive  => PlayerService.instance.currentSong?.id == song.id;
  bool get _isPlaying => _isActive && PlayerService.instance.isPlaying;
  bool get _isFav     => FavoritesService.instance.isFavorite(song.id);

  @override
  Widget build(BuildContext context) {
    final isLocked  = _isLocked;
    final isActive  = _isActive;
    final isPlaying = _isPlaying;
    final isFav     = _isFav;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
        child: Row(
          children: [
            // Cover
            Stack(clipBehavior: Clip.none, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
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
                  child: _Cover(url: song.coverUrl, size: 48),
                ),
              ),
              if (isActive && !isLocked)
                Positioned.fill(child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: Center(
                      child: isPlaying
                          ? const _MiniWave()
                          : const Icon(Icons.play_arrow_rounded,
                              color: AppColors.primary, size: 20),
                    ),
                  ),
                )),
              if (isLocked)
                Positioned(
                  top: -3, right: -3,
                  child: Container(
                    width: 14, height: 14,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                    style: TextStyle(
                      color:         isActive
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
                  Text(
                    song.featuring.isNotEmpty
                        ? '${song.artistName} · ft. ${song.featuring}'
                        : song.artistName,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  if (isLocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(children: [
                        const Icon(Icons.lock_outline_rounded,
                            color: AppColors.primary, size: 10),
                        const SizedBox(width: 3),
                        Text(
                          'Premium · \$${song.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color:      AppColors.primary,
                            fontSize:   10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ]),
                    )
                  else if (song.isAlbumTrack && song.albumTitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(children: [
                        const Icon(Icons.album_rounded,
                            color: AppColors.primary, size: 10),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(song.albumTitle,
                            style: const TextStyle(
                              color:      AppColors.primary,
                              fontSize:   10,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Right
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize:       MainAxisSize.min,
              children: [
                _PricePill(
                  isPaid:     song.isPaid,
                  price:      song.price,
                  isUnlocked: !isLocked && song.isPaid,
                ),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!isLocked)
                    GestureDetector(
                      onTap: () =>
                          FavoritesService.instance.toggleFavorite(song.id),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (c, a) =>
                              ScaleTransition(scale: a, child: c),
                          child: Icon(
                            isFav
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            key:   ValueKey(isFav),
                            color: isFav
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            size:  14,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 8),
                  const SizedBox(width: 2),
                  Text(song.durationDisplay,
                    style: TextStyle(
                        color: isLocked
                            ? AppColors.textSecondary.withValues(alpha: 0.5)
                            : AppColors.textSecondary,
                        fontSize:   10,
                        fontWeight: FontWeight.w600)),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SEARCH ALBUM ROW
// ══════════════════════════════════════════════════════════════════════════════
class _SearchAlbumRow extends StatelessWidget {
  const _SearchAlbumRow({required this.album, required this.onTap});

  final AlbumModel   album;
  final VoidCallback onTap;

  bool get _isUnlocked =>
      !album.isPaid || PurchaseService.instance.isUnlocked(album.id);

  @override
  Widget build(BuildContext context) {
    final isUnlocked = _isUnlocked;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(13),
          border:       Border.all(color: AppColors.surfaceLight),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: ColorFiltered(
                colorFilter: !isUnlocked
                    ? const ColorFilter.matrix([
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0,      0,      0,      1, 0,
                      ])
                    : const ColorFilter.mode(
                        Colors.transparent, BlendMode.multiply),
                child: _Cover(url: album.coverUrl, size: 52),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album.title,
                    style: const TextStyle(
                      color:         AppColors.textPrimary,
                      fontSize:      13,
                      fontWeight:    FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(album.artistName,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.queue_music_rounded,
                        color: AppColors.textSecondary, size: 11),
                    const SizedBox(width: 3),
                    Text('${album.trackCount} tracks',
                      style: const TextStyle(
                          color:      AppColors.textSecondary,
                          fontSize:   10,
                          fontWeight: FontWeight.w600)),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize:       MainAxisSize.min,
              children: [
                _PricePill(
                  isPaid:     album.isPaid,
                  price:      album.price,
                  isUnlocked: isUnlocked && album.isPaid,
                ),
                const SizedBox(height: 8),
                Container(
                  width: 32, height: 32,
                  decoration: const BoxDecoration(
                    shape:    BoxShape.circle,
                    gradient: LinearGradient(
                        colors: [AppColors.accent, AppColors.primary]),
                  ),
                  child: Icon(
                    isUnlocked
                        ? Icons.arrow_forward_ios_rounded
                        : Icons.lock_rounded,
                    color: AppColors.background,
                    size:  12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FEATURED ALBUM CARD
// ══════════════════════════════════════════════════════════════════════════════
class _FeaturedAlbumCard extends StatelessWidget {
  const _FeaturedAlbumCard({required this.album, required this.onTap});

  final AlbumModel   album;
  final VoidCallback onTap;

  bool get _isUnlocked =>
      !album.isPaid || PurchaseService.instance.isUnlocked(album.id);

  @override
  Widget build(BuildContext context) {
    final isUnlocked = _isUnlocked;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width:  130,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color:      Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset:     const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(fit: StackFit.expand, children: [
                    ColorFiltered(
                      colorFilter: !isUnlocked
                          ? const ColorFilter.matrix([
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0,      0,      0,      1, 0,
                            ])
                          : const ColorFilter.mode(
                              Colors.transparent, BlendMode.multiply),
                      child: _Cover(url: album.coverUrl),
                    ),
                    Positioned.fill(child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin:  Alignment.bottomCenter,
                          end:    Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.65),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.6],
                        ),
                      ),
                    )),
                    Positioned(
                      bottom: 6, left: 6,
                      child: _PricePill(
                        isPaid:     album.isPaid,
                        price:      album.price,
                        isUnlocked: isUnlocked && album.isPaid,
                      ),
                    ),
                    Positioned(
                      bottom: 5, right: 5,
                      child: Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                          shape:    BoxShape.circle,
                          gradient: const LinearGradient(
                              colors: [AppColors.accent, AppColors.primary]),
                          boxShadow: [BoxShadow(
                            color:      AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 6,
                          )],
                        ),
                        child: Icon(
                          isUnlocked
                              ? Icons.play_arrow_rounded
                              : Icons.lock_rounded,
                          color: AppColors.background,
                          size:  14,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(album.title,
              style: const TextStyle(
                color:         AppColors.textPrimary,
                fontSize:      11.5,
                fontWeight:    FontWeight.w800,
                letterSpacing: -0.2,
              ),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 1),
            Text('${album.artistName} · ${album.trackCount} tracks',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GENRE CHIP
// ══════════════════════════════════════════════════════════════════════════════
class _GenreChip extends StatelessWidget {
  const _GenreChip({required this.genre});
  final SongGenre genre;

  static const _colors = <SongGenre, Color>{
    SongGenre.autotuneRap: Color(0xFFFF6B00),
    SongGenre.pluggnb:     Color(0xFF9B59B6),
    SongGenre.hipHop:      Color(0xFF27AE60),
    SongGenre.rnb:         Color(0xFF2980B9),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[genre] ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(genre.label,
        style: TextStyle(
          color:      color,
          fontSize:   12,
          fontWeight: FontWeight.w700,
        )),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SONG PAYWALL SHEET — real purchase flow
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
            Expanded(
              child: Text('"${widget.song.title}" unlocked!',
                style: const TextStyle(
                    color:      AppColors.textPrimary,
                    fontSize:   13,
                    fontWeight: FontWeight.w700)),
            ),
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
        setState(() {
          _loading  = false;
          _errorMsg = 'Purchase failed. Please try again.';
        });
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
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
            decoration: BoxDecoration(
                color:        AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 22),

          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _Cover(url: widget.song.coverUrl, size: 90),
          ),
          const SizedBox(height: 14),

          Text(widget.song.title,
            style: const TextStyle(
                color:         AppColors.textPrimary,
                fontSize:      19,
                fontWeight:    FontWeight.w900,
                letterSpacing: -0.4),
            textAlign: TextAlign.center),
          const SizedBox(height: 3),
          Text(widget.song.artistName,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:        AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18)),
            ),
            child: Row(children: [
              Container(width: 38, height: 38,
                decoration: const BoxDecoration(
                  shape:    BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [AppColors.accent, AppColors.primary]),
                ),
                child: const Icon(Icons.lock_rounded,
                    color: AppColors.background, size: 16)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Premium Track',
                    style: TextStyle(
                        color:      AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize:   13)),
                  Text('Unlock for \$${widget.song.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                ])),
            ]),
          ),
          const SizedBox(height: 18),

          if (_errorMsg != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:        Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMsg!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 12))),
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
                  color:      AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset:     const Offset(0, 4))],
              ),
              child: Center(child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(
                    'Buy for \$${widget.song.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color:      AppColors.background,
                        fontWeight: FontWeight.w900,
                        fontSize:   15))))),
          const SizedBox(height: 10),

          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Maybe later',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)))),
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
    this.iconColor,
  });
  final IconData icon;
  final String   text;
  final String?  sub;
  final Color?   iconColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
    child: Row(children: [
      Icon(icon, size: 13, color: iconColor ?? AppColors.primary),
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
        Text(sub!,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 11)),
      ],
    ]),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          Colors.transparent,
          AppColors.surfaceLight.withValues(alpha: 0.7),
          Colors.transparent,
        ]),
      ),
    ),
  );
}

// _PricePill ahora tiene 3 estados: FREE / precio (locked) / OWNED (unlocked paid)
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
          border: Border.all(
              color: const Color(0xFF00C37A).withValues(alpha: 0.35)),
        ),
        child: const Text('FREE',
          style: TextStyle(
            color:         Color(0xFF00C37A),
            fontSize:      8,
            fontWeight:    FontWeight.w900,
            letterSpacing: 0.5,
          )));
    }
    if (isUnlocked) {
      return Container(
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
        style: const TextStyle(
          color:      AppColors.background,
          fontSize:   9,
          fontWeight: FontWeight.w900,
        )));
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
      url,
      width:      size,
      height:     size,
      fit:        BoxFit.cover,
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
    width:  size,
    height: size,
    color:  AppColors.surfaceLight,
    child:  const Center(
      child: Icon(Icons.music_note_rounded,
          color: AppColors.textSecondary, size: 22),
    ),
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
        width:  2.5,
        height: 5 + _c[i].value * 9,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color:        AppColors.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    )),
  );
}

String _formatPlays(int plays) {
  if (plays >= 1000000) return '${(plays / 1000000).toStringAsFixed(1)}M';
  if (plays >= 1000)    return '${(plays / 1000).toStringAsFixed(1)}K';
  return '$plays';
}

PageRoute _slideUp(Widget page) => PageRouteBuilder(
  pageBuilder:        (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) => SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(0, 1),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child,
  ),
  transitionDuration: const Duration(milliseconds: 370),
);