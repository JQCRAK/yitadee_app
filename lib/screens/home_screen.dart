
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import '../models/social_link_model.dart';
import '../services/social_link_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/app_theme.dart';
import '../models/song_model.dart';
import '../models/album_model.dart';
import '../services/song_service.dart';
import '../services/album_service.dart';
import '../services/player_service.dart';
import '../services/favorites_service.dart';
import '../services/purchase_service.dart';
import 'music/full_player_screen.dart';
import 'music/album_detail_screen.dart';

// ─── Feed cache ───────────────────────────────────────────────────────────────
class _FeedCache {
  static final _FeedCache _i = _FeedCache._();
  factory _FeedCache() => _i;
  _FeedCache._();

  final List<AlbumModel> albums = [];
  final List<SongModel>  songs  = [];

  DocumentSnapshot? _albumCursor;
  DocumentSnapshot? _songCursor;
  bool _albumsExhausted = false;
  bool _songsExhausted  = false;
  bool initialized      = false;

  bool get hasMore => !_albumsExhausted || !_songsExhausted;

  Future<void> _refillAlbums() async {
    if (_albumsExhausted) return;
    final (list, last) = await AlbumService.instance.fetchPage(after: _albumCursor);
    albums.addAll(list);
    if (last != null) _albumCursor = last;
    if (list.length < 10) _albumsExhausted = true;
  }

  Future<void> _refillSongs() async {
    if (_songsExhausted) return;
    final (list, last) = await SongService.instance.fetchSinglesPage(after: _songCursor);
    songs.addAll(list);
    if (last != null) _songCursor = last;
    if (list.length < 10) _songsExhausted = true;
  }

  Future<bool> load() async {
    await Future.wait([_refillAlbums(), _refillSongs()]);
    initialized = true;
    return albums.isNotEmpty || songs.isNotEmpty;
  }

  void clear() {
    albums.clear(); songs.clear();
    _albumCursor = null; _songCursor = null;
    _albumsExhausted = false; _songsExhausted = false;
    initialized = false;
  }
}

// ─── HomeScreen ───────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    FavoritesService.instance.loadFavorites();
    PurchaseService.instance.init();
    PurchaseService.instance.addListener(_rebuild);
  }

  void _rebuild() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _tabCtrl.dispose();
    PurchaseService.instance.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _HomeHeader(tabCtrl: _tabCtrl),
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            _AllTab(),
            _SinglesTab(),
            _AlbumsTab(),
          ],
        ),
      ),
    ]);
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.tabCtrl});
  final TabController tabCtrl;
  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.background,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
    child: _SegmentedTabBar(tabCtrl: tabCtrl),
  );
}

class _SegmentedTabBar extends StatefulWidget {
  const _SegmentedTabBar({required this.tabCtrl});
  final TabController tabCtrl;
  @override
  State<_SegmentedTabBar> createState() => _SegmentedTabBarState();
}

class _SegmentedTabBarState extends State<_SegmentedTabBar> {
  int _selected = 0;
  @override
  void initState() { super.initState(); widget.tabCtrl.addListener(_sync); }
  void _sync() { if (mounted && widget.tabCtrl.index != _selected) setState(() => _selected = widget.tabCtrl.index); }
  @override
  void dispose() { widget.tabCtrl.removeListener(_sync); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42, padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.surfaceLight)),
      child: Row(children: [
        _SegTab(label: 'All',     active: _selected == 0, onTap: () { widget.tabCtrl.animateTo(0); setState(() => _selected = 0); }),
        _SegTab(label: 'Singles', active: _selected == 1, onTap: () { widget.tabCtrl.animateTo(1); setState(() => _selected = 1); }),
        _SegTab(label: 'Albums',  active: _selected == 2, onTap: () { widget.tabCtrl.animateTo(2); setState(() => _selected = 2); }),
      ]),
    );
  }
}

class _SegTab extends StatelessWidget {
  const _SegTab({required this.label, required this.active, required this.onTap});
  final String label; final bool active; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.28), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Center(child: Text(label, style: TextStyle(color: active ? AppColors.background : AppColors.textSecondary, fontSize: 12, fontWeight: active ? FontWeight.w800 : FontWeight.w600))),
      ),
    ),
  );
}

// ─── Row label ────────────────────────────────────────────────────────────────
class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.icon, required this.text, this.sub});
  final IconData icon; final String text; final String? sub;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Row(children: [
      Icon(icon, size: 13, color: AppColors.primary),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.1)),
      if (sub != null) ...[
        const SizedBox(width: 5),
        Text(sub!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    ]),
  );
}

// ─── Brand Banner (carrusel: logos + redes sociales) ──────────────────────────
class _BrandBanner extends StatefulWidget {
  const _BrandBanner();
  @override
  State<_BrandBanner> createState() => _BrandBannerState();
}

class _BrandBannerState extends State<_BrandBanner> {
  final _pageCtrl = PageController();
  Timer? _timer;
  List<SocialLinkModel> _links = [];
  int _page = 0;

  static const _icons = <SocialPlatform, IconData>{
    SocialPlatform.shopify: Icons.storefront_rounded,
    SocialPlatform.twitch: Icons.live_tv_rounded,
    SocialPlatform.youtube: Icons.play_circle_rounded,
    SocialPlatform.instagram: Icons.camera_alt_rounded,
    SocialPlatform.tiktok: Icons.music_video_rounded,
    SocialPlatform.paypal: Icons.payment_rounded,
    SocialPlatform.facebook: Icons.facebook_rounded,
    SocialPlatform.twitter: Icons.alternate_email_rounded,
    SocialPlatform.spotify: Icons.graphic_eq_rounded,
    SocialPlatform.soundcloud: Icons.cloud_queue_rounded,
    SocialPlatform.appleMusic: Icons.apple_rounded,
    SocialPlatform.discord: Icons.forum_rounded,
    SocialPlatform.whatsapp: Icons.chat_rounded,
    SocialPlatform.website: Icons.language_rounded,
  };

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  Future<void> _loadLinks() async {
    final list = await SocialLinkService.instance.fetchAll();
    if (!mounted) return;
    setState(() => _links = list);
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _timer?.cancel();
    final totalPages = 2 + _links.length;
    if (totalPages <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_pageCtrl.hasClients) return;
      final next = (_page + 1) % totalPages;
      _pageCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
    });
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = 2 + _links.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(children: [
        SizedBox(
          height: 100,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: totalPages,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (ctx, i) {
              if (i == 0) return const _YitadeeLogoCard();
              if (i == 1) return const _GotItMadeLogoCard();
              final link = _links[i - 2];
              return _SocialCarouselCard(
                link: link,
                icon: _icons[link.platform] ?? Icons.link_rounded,
                onTap: () => _openLink(link.url),
              );
            },
          ),
        ),
        if (totalPages > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(totalPages, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _page ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _page ? AppColors.primary : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(3),
              ),
            )),
          ),
        ],
      ]),
    );
  }
}

// ─── Tarjeta de logos (YITADEE a la izquierda y chico,

BoxDecoration _brandCardDecoration() => BoxDecoration(
  borderRadius: BorderRadius.circular(18),
  color: Colors.black,
  border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
);

// ─── Tarjeta 1: logo YITADEE ────────────────────────────────────────────────
// ─── Tarjeta 1: logo YITADEE ────────────────────────────────────────────────
class _YitadeeLogoCard extends StatelessWidget {
  const _YitadeeLogoCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
      decoration: _brandCardDecoration(),
      child: Center(
        child: SizedBox(
          height: 80,
          child: Image.asset('assets/images/yitadee_logo.png', fit: BoxFit.contain),
        ),
      ),
    );
  }
}
// ─── Tarjeta 2: logo GOT IT MADE RECORDS ───────────────────────────────────
class _GotItMadeLogoCard extends StatelessWidget {
  const _GotItMadeLogoCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: _brandCardDecoration(),
      child: Center(
        child: SizedBox(
          height: 120,
          child: Image.asset('assets/images/got_it_made_logo.png', fit: BoxFit.contain),
        ),
      ),
    );
  }
}
// ─── Tarjeta de red social dentro del carrusel ────────────────────────────────
class _SocialCarouselCard extends StatelessWidget {
  const _SocialCarouselCard({required this.link, required this.icon, required this.onTap});
  final SocialLinkModel link;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: _brandCardDecoration(),
        child: Row(children: [
          Container(
            width: 46, height: 46,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black,
              border: Border.fromBorderSide(BorderSide(color: AppColors.primary, width: 1.4))),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Follow us on ${link.displayLabel}',
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 4),
            Text(link.url, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          const Icon(Icons.open_in_new_rounded, color: AppColors.primary, size: 18),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ALL TAB
// ══════════════════════════════════════════════════════════════════════════════
class _AllTab extends StatefulWidget {
  const _AllTab();
  @override
  State<_AllTab> createState() => _AllTabState();
}

class _AllTabState extends State<_AllTab> with AutomaticKeepAliveClientMixin {
  final _cache      = _FeedCache();
  final _scrollCtrl = ScrollController();
  bool _loading     = true;
  bool _fetching    = false;

  static const int _albumsPerBlock = 3;
  static const int _songsPerBlock  = 5;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    PlayerService.instance.addListener(_rebuild);
    FavoritesService.instance.addListener(_rebuild);
    PurchaseService.instance.addListener(_rebuild);
    if (_cache.initialized) { _loading = false; } else { _loadInitial(); }
  }

  void _rebuild() { if (mounted) setState(() {}); }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if ((pos.pixels >= pos.maxScrollExtent - 500 || pos.maxScrollExtent < 300) && !_fetching && _cache.hasMore) _loadMore();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll); _scrollCtrl.dispose();
    PlayerService.instance.removeListener(_rebuild);
    FavoritesService.instance.removeListener(_rebuild);
    PurchaseService.instance.removeListener(_rebuild);
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _fetching = true);
    await _cache.load();
    if (!mounted) return;
    setState(() { _loading = false; _fetching = false; });
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  Future<void> _loadMore() async {
    if (_fetching || !_cache.hasMore) return;
    setState(() => _fetching = true);
    await _cache.load();
    if (!mounted) return;
    setState(() => _fetching = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  Future<void> _refresh() async {
    _cache.clear();
    setState(() => _loading = true);
    await _loadInitial();
  }

  List<Widget> _buildFeedWidgets() {
    final widgets = <Widget>[];

    widgets.add(const _BrandBanner());

    int albumIdx = 0;
    int songIdx  = 0;
    int blockNum = 0;

    while (albumIdx < _cache.albums.length || songIdx < _cache.songs.length) {
      final albumSlice = _cache.albums.skip(albumIdx).take(_albumsPerBlock).toList();
      final songSlice  = _cache.songs.skip(songIdx).take(_songsPerBlock).toList();

      if (albumSlice.isEmpty && songSlice.isEmpty) break;

      if (albumSlice.isNotEmpty) {
        widgets.add(_RowLabel(icon: Icons.album_rounded, text: blockNum == 0 ? 'New Releases' : 'More Albums', sub: '· ${albumSlice.length} albums'));
        widgets.add(_AlbumMiniRow(albums: albumSlice));
      }

      if (songSlice.isNotEmpty) {
        widgets.add(_RowLabel(icon: Icons.music_note_rounded, text: blockNum == 0 ? 'Fresh Tracks' : 'More Singles', sub: '· ${songSlice.length} tracks'));
        for (int si = 0; si < songSlice.length; si++) {
          widgets.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: _FeedSongRow(song: songSlice[si], allSongs: _cache.songs),
          ));
        }
      }

      widgets.add(const _BlockDivider());
      albumIdx += albumSlice.length;
      songIdx  += songSlice.length;
      blockNum++;
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2));
    final feedWidgets = _buildFeedWidgets();
    return RefreshIndicator(
      color: AppColors.primary, backgroundColor: AppColors.surface, onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollCtrl, physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 140),
        itemCount: feedWidgets.length + (_cache.hasMore || _fetching ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == feedWidgets.length) {
            return Padding(padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(child: _fetching
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const SizedBox.shrink()));
          }
          return feedWidgets[i];
        },
      ),
    );
  }
}

// ─── Album Mini Row ───────────────────────────────────────────────────────────
class _AlbumMiniRow extends StatelessWidget {
  const _AlbumMiniRow({required this.albums});
  final List<AlbumModel> albums;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: List.generate(albums.length, (i) {
        final isLast = i == albums.length - 1;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: isLast ? 0 : 8),
          child: _AlbumMiniCard(album: albums[i])));
      })),
    );
  }
}

// ─── Album Mini Card ──────────────────────────────────────────────────────────
class _AlbumMiniCard extends StatelessWidget {
  const _AlbumMiniCard({required this.album});
  final AlbumModel album;

  bool get _isEffectivelyFree =>
      !album.isPaid || PurchaseService.instance.isUnlocked(album.id);

  @override
  Widget build(BuildContext context) {
    final isUnlocked = _isEffectivelyFree;
    return GestureDetector(
      onTap: () => Navigator.push(context, _slideUp(AlbumDetailScreen(album: album))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(fit: StackFit.expand, children: [
                ColorFiltered(
                  colorFilter: (!isUnlocked && album.isPaid)
                      ? const ColorFilter.matrix([
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0,      0,      0,      1, 0,
                        ])
                      : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                  child: _CachedCover(url: album.coverUrl),
                ),
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent], stops: const [0.0, 0.6])))),
                Positioned(bottom: 6, left: 6,
                  child: _PricePill(isPaid: album.isPaid, price: album.price, isUnlocked: isUnlocked)),
                if (!isUnlocked && album.isPaid)
                  Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(10),
                    child: Container(color: Colors.black.withValues(alpha: 0.35),
                      child: const Align(alignment: Alignment.center,
                        child: Icon(Icons.lock_rounded, color: Colors.white54, size: 22))))),
                Positioned(bottom: 5, right: 5, child: Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 6)]),
                  child: Icon(isUnlocked ? Icons.play_arrow_rounded : Icons.lock_rounded,
                    color: AppColors.background, size: 14))),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(album.title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: -0.2),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 1),
        Text('${album.artistName} · ${album.trackCount} tracks',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        if (album.uploadDateDisplay.isNotEmpty) ...[
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.calendar_today_rounded, color: AppColors.textSecondary, size: 9),
            const SizedBox(width: 3),
            Text(album.uploadDateDisplay,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
          ]),
        ],
        const SizedBox(height: 10),
      ]),
    );
  }
}

// ─── Block Divider ────────────────────────────────────────────────────────────
class _BlockDivider extends StatelessWidget {
  const _BlockDivider();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
    child: Container(height: 1, decoration: BoxDecoration(
      gradient: LinearGradient(colors: [Colors.transparent, AppColors.surfaceLight.withValues(alpha: 0.7), Colors.transparent]))));
}

// ─── Feed Song Row ────────────────────────────────────────────────────────────
class _FeedSongRow extends StatelessWidget {
  const _FeedSongRow({required this.song, required this.allSongs});
  final SongModel song;
  final List<SongModel> allSongs;

  bool get _isActive   => PlayerService.instance.currentSong?.id == song.id;
  bool get _isPlaying  => _isActive && PlayerService.instance.isPlaying;
  bool get _isFav      => FavoritesService.instance.isFavorite(song.id);
  bool get _isLocked   => song.isPaid && !PurchaseService.instance.isUnlocked(song.id);

  void _handleTap(BuildContext ctx) {
    if (_isLocked) {
      showModalBottomSheet(
        context: ctx, backgroundColor: Colors.transparent, isScrollControlled: true,
        builder: (_) => _PaywallSheet(
          contentId:   song.id,
          contentType: 'single',
          title:       song.title,
          artistName:  song.artistName,
          coverUrl:    song.coverUrl,
          price:       song.price,
        ),
      );
      return;
    }
    if (_isActive) {
      Navigator.of(ctx).push(_slideUp(const FullPlayerScreen()));
      return;
    }
    final playable = allSongs.where((s) => !s.isPaid || PurchaseService.instance.isUnlocked(s.id)).toList();
    final idx      = playable.indexWhere((s) => s.id == song.id);
    PlayerService.instance.playSong(song, queue: playable, index: idx < 0 ? 0 : idx);
    Navigator.of(ctx).push(_slideUp(const FullPlayerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isActive  = _isActive;
    final isPlaying = _isPlaying;
    final isFav     = _isFav;
    final isLocked  = _isLocked;

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isLocked
              ? AppColors.surfaceLight.withValues(alpha: 0.5)
              : isActive
                  ? AppColors.primary.withValues(alpha: 0.07)
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLocked
                ? AppColors.primary.withValues(alpha: 0.15)
                : isActive
                    ? AppColors.primary.withValues(alpha: 0.38)
                    : AppColors.surfaceLight,
            width: isActive ? 1.2 : 1),
        ),
        child: Row(children: [
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
                    : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                child: _CachedCover(url: song.coverUrl, size: 46),
              ),
            ),
            if (isLocked)
              Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(8),
                child: Container(color: Colors.black.withValues(alpha: 0.45),
                  child: const Center(child: Icon(Icons.lock_rounded, color: Colors.white, size: 16))))),
            if (isActive && !isLocked)
              Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(8),
                child: Container(color: Colors.black.withValues(alpha: 0.45),
                  child: Center(child: isPlaying
                    ? const _MiniWave()
                    : const Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 18))))),
            Positioned(top: -4, right: -4,
              child: isLocked
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 4)]),
                    child: Text('\$${song.price.toStringAsFixed(0)}',
                      style: const TextStyle(color: AppColors.background, fontSize: 8, fontWeight: FontWeight.w900)))
                : const SizedBox.shrink()),
          ]),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(song.title,
              style: TextStyle(
                color: isLocked ? AppColors.textSecondary : isActive ? AppColors.primary : AppColors.textPrimary,
                fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.2),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(children: [
              Flexible(child: Text(
                song.featuring.isNotEmpty ? '${song.artistName} · ft. ${song.featuring}' : song.artistName,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 5),
              Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(3)),
                child: Text(song.genreDisplay,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            _PricePill(isPaid: song.isPaid, price: song.price, isUnlocked: !isLocked),
            const SizedBox(height: 5),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(song.durationDisplay,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              if (!isLocked)
                GestureDetector(
                  onTap: () => FavoritesService.instance.toggleFavorite(song.id),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(padding: const EdgeInsets.all(4),
                    child: AnimatedSwitcher(duration: const Duration(milliseconds: 180),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        key: ValueKey(isFav),
                        color: isFav ? AppColors.primary : AppColors.textSecondary, size: 15)))),
              const SizedBox(width: 2),
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isLocked
                      ? const LinearGradient(colors: [Color(0xFF555555), Color(0xFF333333)])
                      : isActive
                          ? const LinearGradient(colors: [AppColors.accent, AppColors.primary])
                          : null,
                  color: (!isLocked && !isActive) ? AppColors.surfaceLight : null),
                child: Icon(
                  isLocked ? Icons.lock_rounded : isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: isLocked ? Colors.white54 : isActive ? AppColors.background : AppColors.textSecondary,
                  size: 12)),
            ]),
          ]),
        ]),
      ),
    );
  }
}

// ─── Price Pill ───────────────────────────────────────────────────────────────
class _PricePill extends StatelessWidget {
  const _PricePill({required this.isPaid, required this.price, this.isUnlocked = false});
  final bool isPaid; final double price; final bool isUnlocked;

  @override
  Widget build(BuildContext context) {
    if (isPaid && isUnlocked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF00C37A).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF00C37A).withValues(alpha: 0.35))),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_rounded, color: Color(0xFF00C37A), size: 9),
          SizedBox(width: 3),
          Text('OWNED', style: TextStyle(color: Color(0xFF00C37A), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ]));
    }
    if (isPaid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
          borderRadius: BorderRadius.circular(5)),
        child: Text('\$${price.toStringAsFixed(0)}',
          style: const TextStyle(color: AppColors.background, fontSize: 9, fontWeight: FontWeight.w900)));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF00C37A).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF00C37A).withValues(alpha: 0.35))),
      child: const Text('FREE',
        style: TextStyle(color: Color(0xFF00C37A), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SINGLES TAB
// ══════════════════════════════════════════════════════════════════════════════
class _SinglesTab extends StatefulWidget {
  const _SinglesTab();
  @override
  State<_SinglesTab> createState() => _SinglesTabState();
}

class _SinglesTabState extends State<_SinglesTab> with AutomaticKeepAliveClientMixin {
  List<SongModel> _songs = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = true, _hasMore = true, _loadingMore = false;
  final _scrollCtrl = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollCtrl.addListener(_onScroll);
    PlayerService.instance.addListener(_rebuild);
    FavoritesService.instance.addListener(_rebuild);
    PurchaseService.instance.addListener(_rebuild);
  }

  void _rebuild() { if (mounted) setState(() {}); }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 400 && !_loadingMore && _hasMore) _loadMore();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll); _scrollCtrl.dispose();
    PlayerService.instance.removeListener(_rebuild);
    FavoritesService.instance.removeListener(_rebuild);
    PurchaseService.instance.removeListener(_rebuild);
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) setState(() { _songs = []; _lastDoc = null; _hasMore = true; _loading = true; });
    final (list, last) = await SongService.instance.fetchSinglesPage(after: _lastDoc);
    if (!mounted) return;
    setState(() { _songs.addAll(list); _lastDoc = last; _hasMore = list.length == 10; _loading = false; _loadingMore = false; });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2));
    if (_songs.isEmpty) return const _EmptyState(icon: Icons.music_note_rounded, message: 'No singles yet.\nCheck back soon.');
    return RefreshIndicator(
      color: AppColors.primary, backgroundColor: AppColors.surface, onRefresh: () => _load(reset: true),
      child: CustomScrollView(
        controller: _scrollCtrl, physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _RowLabel(icon: Icons.music_note_rounded, text: 'Recent Singles', sub: '· sorted by latest')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
            sliver: SliverList(delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                if (i == _songs.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: _loadingMore
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                      : const SizedBox.shrink()));
                }
                return Padding(padding: const EdgeInsets.only(bottom: 7),
                  child: _SinglesTrackRow(song: _songs[i], index: i, allSongs: _songs));
              },
              childCount: _songs.length + (_hasMore ? 1 : 0),
            )),
          ),
        ],
      ),
    );
  }
}

// ─── Singles Track Row ────────────────────────────────────────────────────────
class _SinglesTrackRow extends StatelessWidget {
  const _SinglesTrackRow({required this.song, required this.index, required this.allSongs});
  final SongModel song; final int index; final List<SongModel> allSongs;

  bool get _isActive  => PlayerService.instance.currentSong?.id == song.id;
  bool get _isPlaying => _isActive && PlayerService.instance.isPlaying;
  bool get _isFav     => FavoritesService.instance.isFavorite(song.id);
  bool get _isLocked  => song.isPaid && !PurchaseService.instance.isUnlocked(song.id);

  void _handleTap(BuildContext ctx) {
    if (_isLocked) {
      showModalBottomSheet(
        context: ctx, backgroundColor: Colors.transparent, isScrollControlled: true,
        builder: (_) => _PaywallSheet(
          contentId:   song.id,
          contentType: 'single',
          title:       song.title,
          artistName:  song.artistName,
          coverUrl:    song.coverUrl,
          price:       song.price,
        ),
      );
      return;
    }
    if (_isActive) {
      Navigator.of(ctx).push(_slideUp(const FullPlayerScreen()));
      return;
    }
    final playable = allSongs.where((s) => !s.isPaid || PurchaseService.instance.isUnlocked(s.id)).toList();
    final idx      = playable.indexWhere((s) => s.id == song.id);
    PlayerService.instance.playSong(song, queue: playable, index: idx < 0 ? 0 : idx);
    Navigator.of(ctx).push(_slideUp(const FullPlayerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isActive  = _isActive;
    final isPlaying = _isPlaying;
    final isFav     = _isFav;
    final isLocked  = _isLocked;

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isLocked ? AppColors.surfaceLight.withValues(alpha: 0.5) : isActive ? AppColors.primary.withValues(alpha: 0.06) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLocked ? AppColors.primary.withValues(alpha: 0.12) : isActive ? AppColors.primary.withValues(alpha: 0.38) : AppColors.surfaceLight,
            width: isActive ? 1.2 : 1)),
        child: Row(children: [
          SizedBox(width: 26,
            child: isLocked
              ? const Icon(Icons.lock_rounded, color: AppColors.textSecondary, size: 16)
              : isActive
                  ? (isPlaying ? const _MiniWave() : const Icon(Icons.pause_rounded, color: AppColors.primary, size: 15))
                  : Text((index + 1).toString().padLeft(2, '0'),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Stack(clipBehavior: Clip.none, children: [
            ClipRRect(borderRadius: BorderRadius.circular(8),
              child: ColorFiltered(
                colorFilter: isLocked
                    ? const ColorFilter.matrix([0.2126,0.7152,0.0722,0,0, 0.2126,0.7152,0.0722,0,0, 0.2126,0.7152,0.0722,0,0, 0,0,0,1,0])
                    : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                child: _CachedCover(url: song.coverUrl, size: 44))),
            if (isLocked)
              Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(8),
                child: Container(color: Colors.black.withValues(alpha: 0.4),
                  child: const Center(child: Icon(Icons.lock_rounded, color: Colors.white, size: 14))))),
          ]),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(song.title,
              style: TextStyle(
                color: isLocked ? AppColors.textSecondary : isActive ? AppColors.primary : AppColors.textPrimary,
                fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.2),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(children: [
              Flexible(child: Text(
                song.featuring.isNotEmpty ? '${song.artistName} · ft. ${song.featuring}' : song.artistName,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 5),
              Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(3)),
                child: Text(song.genreDisplay,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            if (song.uploadDateDisplay.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.calendar_today_rounded, color: AppColors.textSecondary, size: 9),
                const SizedBox(width: 3),
                Text(song.uploadDateDisplay,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
              ]),
            ],
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            _PricePill(isPaid: song.isPaid, price: song.price, isUnlocked: !isLocked),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (!isLocked)
                GestureDetector(
                  onTap: () => FavoritesService.instance.toggleFavorite(song.id),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(padding: const EdgeInsets.all(3),
                    child: AnimatedSwitcher(duration: const Duration(milliseconds: 180),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        key: ValueKey(isFav),
                        color: isFav ? AppColors.primary : AppColors.textSecondary, size: 14)))),
              const SizedBox(width: 2),
              Text(song.durationDisplay,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ALBUMS TAB
// ══════════════════════════════════════════════════════════════════════════════
class _AlbumsTab extends StatefulWidget {
  const _AlbumsTab();
  @override
  State<_AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends State<_AlbumsTab> with AutomaticKeepAliveClientMixin {
  List<AlbumModel> _albums = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = true, _hasMore = true, _loadingMore = false;
  final _scrollCtrl = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollCtrl.addListener(_onScroll);
    PurchaseService.instance.addListener(_rebuild);
  }

  void _rebuild() { if (mounted) setState(() {}); }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 400 && !_loadingMore && _hasMore) _loadMore();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll); _scrollCtrl.dispose();
    PurchaseService.instance.removeListener(_rebuild);
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) setState(() { _albums = []; _lastDoc = null; _hasMore = true; _loading = true; });
    final (list, last) = await AlbumService.instance.fetchPage(after: _lastDoc);
    if (!mounted) return;
    setState(() { _albums.addAll(list); _lastDoc = last; _hasMore = list.length == 10; _loading = false; _loadingMore = false; });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2));
    if (_albums.isEmpty) return const _EmptyState(icon: Icons.album_rounded, message: 'No albums yet.\nCheck back soon.');

    return RefreshIndicator(
      color: AppColors.primary, backgroundColor: AppColors.surface, onRefresh: () => _load(reset: true),
      child: CustomScrollView(
        controller: _scrollCtrl, physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _RowLabel(icon: Icons.album_rounded, text: 'All Albums', sub: '· latest first')),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _FeaturedAlbumCard(album: _albums.first))),
          if (_albums.length > 1)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.72),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final ri = i + 1;
                    if (ri >= _albums.length) {
                      return _hasMore
                          ? Center(child: _loadingMore ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)) : const SizedBox.shrink())
                          : const SizedBox.shrink();
                    }
                    return _GridAlbumCard(album: _albums[ri]);
                  },
                  childCount: (_albums.length - 1) + (_hasMore ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Featured Album Card ──────────────────────────────────────────────────────
class _FeaturedAlbumCard extends StatelessWidget {
  const _FeaturedAlbumCard({required this.album});
  final AlbumModel album;

  bool get _isUnlocked => !album.isPaid || PurchaseService.instance.isUnlocked(album.id);

  void _handleTap(BuildContext ctx) {
    if (!_isUnlocked) {
      showModalBottomSheet(
        context: ctx, backgroundColor: Colors.transparent, isScrollControlled: true,
        builder: (_) => _PaywallSheet(
          contentId:   album.id,
          contentType: 'album',
          title:       album.title,
          artistName:  album.artistName,
          coverUrl:    album.coverUrl,
          price:       album.price,
        ),
      );
      return;
    }
    Navigator.push(ctx, _slideUp(AlbumDetailScreen(album: album)));
  }

  @override
  Widget build(BuildContext context) {
    final isUnlocked = _isUnlocked;
    final double w = MediaQuery.of(context).size.width - 32;
    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Container(
        width: w, height: w * 0.48,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 6)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4))]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(fit: StackFit.expand, children: [
            ColorFiltered(
              colorFilter: !isUnlocked
                  ? const ColorFilter.matrix([0.2126,0.7152,0.0722,0,0, 0.2126,0.7152,0.0722,0,0, 0.2126,0.7152,0.0722,0,0, 0,0,0,1,0])
                  : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
              child: _CachedCover(url: album.coverUrl)),
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)], stops: const [0.25, 1.0])))),
            Positioned(top: 12, left: 12, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]), borderRadius: BorderRadius.circular(6)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.star_rounded, color: AppColors.background, size: 9),
                SizedBox(width: 4),
                Text('FEATURED', style: TextStyle(color: AppColors.background, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
              ]))),
            if (!isUnlocked)
              Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.3),
                child: const Center(child: Icon(Icons.lock_rounded, color: Colors.white54, size: 32)))),
            Positioned(left: 14, right: 14, bottom: 14, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(album.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.6, height: 1.1), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(album.artistName, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                const SizedBox(height: 6),
                Row(children: [
                  Text('${album.trackCount} tracks', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                  const SizedBox(width: 8),
                  _PricePill(isPaid: album.isPaid, price: album.price, isUnlocked: isUnlocked),
                ]),
              ])),
              Container(width: 44, height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: LinearGradient(colors: isUnlocked
                    ? [AppColors.accent, AppColors.primary]
                    : [const Color(0xFF555555), const Color(0xFF333333)]),
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 12)]),
                child: Icon(isUnlocked ? Icons.play_arrow_rounded : Icons.lock_rounded,
                  color: AppColors.background, size: 22)),
            ])),
          ]),
        ),
      ),
    );
  }
}

// ─── Grid Album Card ──────────────────────────────────────────────────────────
class _GridAlbumCard extends StatelessWidget {
  const _GridAlbumCard({required this.album});
  final AlbumModel album;

  bool get _isUnlocked => !album.isPaid || PurchaseService.instance.isUnlocked(album.id);

  void _handleTap(BuildContext ctx) {
    if (!_isUnlocked) {
      showModalBottomSheet(
        context: ctx, backgroundColor: Colors.transparent, isScrollControlled: true,
        builder: (_) => _PaywallSheet(
          contentId:   album.id,
          contentType: 'album',
          title:       album.title,
          artistName:  album.artistName,
          coverUrl:    album.coverUrl,
          price:       album.price,
        ),
      );
      return;
    }
    Navigator.push(ctx, _slideUp(AlbumDetailScreen(album: album)));
  }

  @override
  Widget build(BuildContext context) {
    final isUnlocked = _isUnlocked;
    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.surfaceLight)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Stack(fit: StackFit.expand, children: [
            ClipRRect(borderRadius: const BorderRadius.only(topLeft: Radius.circular(13), topRight: Radius.circular(13)),
              child: ColorFiltered(
                colorFilter: !isUnlocked
                    ? const ColorFilter.matrix([0.2126,0.7152,0.0722,0,0, 0.2126,0.7152,0.0722,0,0, 0.2126,0.7152,0.0722,0,0, 0,0,0,1,0])
                    : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                child: _CachedCover(url: album.coverUrl))),
            Positioned(bottom: 0, left: 0, right: 0, height: 36, child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [AppColors.surface, Colors.transparent])))),
            if (!isUnlocked)
              Positioned.fill(child: ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(13), topRight: Radius.circular(13)),
                child: Container(color: Colors.black.withValues(alpha: 0.4),
                  child: const Center(child: Icon(Icons.lock_rounded, color: Colors.white54, size: 24))))),
            Positioned(top: 8, right: 8,
              child: _PricePill(isPaid: album.isPaid, price: album.price, isUnlocked: isUnlocked)),
          ])),
          Padding(padding: const EdgeInsets.fromLTRB(9, 7, 9, 9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(album.title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: -0.2), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(album.artistName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (album.uploadDateDisplay.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.calendar_today_rounded, color: AppColors.textSecondary, size: 9),
                const SizedBox(width: 3),
                Text(album.uploadDateDisplay,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
              ]),
            ],
            const SizedBox(height: 7),
            Row(children: [
              Text('${album.trackCount} tracks', style: const TextStyle(color: AppColors.textSecondary, fontSize: 9.5, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(width: 22, height: 22,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: LinearGradient(colors: isUnlocked
                    ? [AppColors.accent, AppColors.primary]
                    : [const Color(0xFF555555), const Color(0xFF333333)])),
                child: Icon(isUnlocked ? Icons.arrow_forward_ios_rounded : Icons.lock_rounded,
                  color: AppColors.background, size: 9)),
            ]),
          ])),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAYWALL SHEET — handles both albums and singles
// ══════════════════════════════════════════════════════════════════════════════
class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet({
    required this.contentId,
    required this.contentType,
    required this.title,
    required this.artistName,
    required this.coverUrl,
    required this.price,
  });

  final String contentId;
  final String contentType;
  final String title;
  final String artistName;
  final String coverUrl;
  final double price;

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  bool _loading = false;
  String? _errorMsg;

  Future<void> _handleBuy() async {
    setState(() { _loading = true; _errorMsg = null; });

    final result = widget.contentType == 'album'
        ? await PurchaseService.instance.buyAlbum(albumId: widget.contentId, price: widget.price)
        : await PurchaseService.instance.buySingle(songId: widget.contentId, price: widget.price);

    if (!mounted) return;

    switch (result) {
      case PurchaseResult.success:
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: const Color(0xFF00C37A).withValues(alpha: 0.4))),
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF00C37A), size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text('"${widget.title}" unlocked!',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700))),
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
    final isAlbum = widget.contentType == 'album';

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 22),

          ClipRRect(borderRadius: BorderRadius.circular(14),
            child: _CachedCover(url: widget.coverUrl, size: 90)),
          const SizedBox(height: 14),

          Text(widget.title,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.4),
            textAlign: TextAlign.center),
          const SizedBox(height: 3),
          Text(widget.artistName,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.18))),
            child: Row(children: [
              Container(width: 38, height: 38,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [AppColors.accent, AppColors.primary])),
                child: const Icon(Icons.lock_rounded, color: AppColors.background, size: 16)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isAlbum ? 'Premium Album' : 'Premium Track',
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                Text('Unlock for \$${widget.price.toStringAsFixed(0)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ])),
            ])),
          const SizedBox(height: 18),

          if (_errorMsg != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
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
                  ? [AppColors.primary.withValues(alpha: 0.5), AppColors.accent.withValues(alpha: 0.5)]
                  : [AppColors.accent, AppColors.primary]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: _loading ? null : [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))]),
              child: Center(child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Buy for \$${widget.price.toStringAsFixed(0)}',
                    style: const TextStyle(color: AppColors.background, fontWeight: FontWeight.w900, fontSize: 15))))),
          const SizedBox(height: 10),

          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Maybe later', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)))),
        ]),
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────
class _CachedCover extends StatelessWidget {
  const _CachedCover({required this.url, this.size});
  final String url; final double? size;
  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _Fallback(size: size);
    return Image.network(url, width: size, height: size, fit: BoxFit.cover,
      cacheWidth: size != null ? (size! * MediaQuery.of(context).devicePixelRatio).toInt() : null,
      errorBuilder: (_, __, ___) => _Fallback(size: size));
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({this.size});
  final double? size;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, color: AppColors.surfaceLight,
    child: const Center(child: Icon(Icons.music_note_rounded, color: AppColors.textSecondary, size: 26)));
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
    _c = List.generate(3, (i) => AnimationController(vsync: this, duration: Duration(milliseconds: 350 + i * 100))..repeat(reverse: true));
  }
  @override
  void dispose() { for (final c in _c) { c.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end,
    children: List.generate(3, (i) => AnimatedBuilder(animation: _c[i], builder: (_, __) => Container(
      width: 2.5, height: 5 + _c[i].value * 9, margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))))));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon; final String message;
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 68, height: 68, decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: AppColors.surfaceLight)),
      child: Icon(icon, color: AppColors.surfaceLight, size: 30)),
    const SizedBox(height: 14),
    Text(message, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.6), textAlign: TextAlign.center),
  ]));
}

// ─── Route helper ─────────────────────────────────────────────────────────────
PageRoute _slideUp(Widget page) => PageRouteBuilder(
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) => SlideTransition(
    position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child),
  transitionDuration: const Duration(milliseconds: 370),
);