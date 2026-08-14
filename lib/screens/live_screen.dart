import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_theme.dart';
import '../models/social_link_model.dart';
import '../services/social_link_service.dart';
import '../services/merch_banner_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// LIVE PLATFORM — which platform is currently shown in the player
// ══════════════════════════════════════════════════════════════════════════════
enum _LivePlatform { none, twitch, youtube }

// ══════════════════════════════════════════════════════════════════════════════
// LIVE SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});
  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen>
    with AutomaticKeepAliveClientMixin {

  SocialLinkModel? _twitch;
  SocialLinkModel? _youtube;
  SocialLinkModel? _instagram;
  SocialLinkModel? _paypal;

  bool _loading = true;

  WebViewController? _webCtrl;
  _LivePlatform      _activePlatform = _LivePlatform.none;
  bool               _isLive         = false;
  bool               _checkingLive   = false;
  String             _activeUrl      = '';

  // ── Merch banner ──────────────────────────────────────────────────────────
  String? _shopifyUrl;
  bool    _bannerLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadLinks();
    _loadBannerUrl();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOAD BANNER
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _loadBannerUrl() async {
    final url = await MerchBannerService.instance.fetchShopifyUrl();
    if (mounted) setState(() { _shopifyUrl = url ?? ''; _bannerLoaded = true; });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOAD DATA
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _loadLinks() async {
    setState(() { _loading = true; _webCtrl = null; _isLive = false; });
    try {
      final links = await SocialLinkService.instance.fetchAll();
      _twitch = _youtube = _instagram = _paypal = null;
      for (final l in links) {
        switch (l.platform) {
          case SocialPlatform.twitch:    _twitch    = l; break;
          case SocialPlatform.youtube:   _youtube   = l; break;
          case SocialPlatform.instagram: _instagram = l; break;
          case SocialPlatform.paypal:    _paypal    = l; break;
          default: break;
        }
      }
      await _resolvePlayer();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Priority: Twitch first → YouTube fallback ─────────────────────────────
  Future<void> _resolvePlayer() async {
    if (_twitch != null) {
      _activePlatform = _LivePlatform.twitch;
      _activeUrl      = _twitch!.url;
      _initWebView(_buildTwitchEmbed(_twitch!.url));
    } else if (_youtube != null) {
      _activePlatform = _LivePlatform.youtube;
      _activeUrl      = _youtube!.url;
      _initWebView(_buildYouTubeEmbed(_youtube!.url));
    } else {
      _activePlatform = _LivePlatform.none;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EMBED BUILDERS
  // ══════════════════════════════════════════════════════════════════════════
  String _buildTwitchEmbed(String url) {
    final channel = _extractTwitchChannel(url);
    if (channel == null) return url;
    return 'https://player.twitch.tv/?channel=$channel'
        '&parent=localhost&autoplay=true&muted=false';
  }

  String? _extractTwitchChannel(String url) {
    try {
      final uri   = Uri.parse(url.trim());
      final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      return parts.isNotEmpty ? parts.first : null;
    } catch (_) { return null; }
  }

  String _buildYouTubeEmbed(String url) {
    try {
      final uri = Uri.parse(url.trim());

      if (uri.queryParameters.containsKey('v')) {
        return 'https://www.youtube.com/embed/${uri.queryParameters['v']}'
            '?autoplay=1&rel=0';
      }

      final chId = RegExp(r'youtube\.com/channel/(UC[\w-]+)')
          .firstMatch(url)?.group(1);
      if (chId != null) {
        return 'https://www.youtube.com/embed/live_stream'
            '?channel=$chId&autoplay=1&rel=0';
      }

      final clean = url.trim().replaceAll(RegExp(r'/$'), '');
      return '$clean/live';
    } catch (_) { return url; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WEBVIEW
  // ══════════════════════════════════════════════════════════════════════════
  void _initWebView(String embedUrl) {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _checkingLive = true);
        },
        onPageFinished: (loadedUrl) {
          if (mounted) {
            final live = _activePlatform == _LivePlatform.twitch
                ? true
                : (loadedUrl.contains('/watch') ||
                   loadedUrl.contains('/live_stream') ||
                   loadedUrl.contains('embed/live'));
            setState(() { _isLive = live; _checkingLive = false; });
          }
        },
        onWebResourceError: (_) {
          if (mounted) setState(() => _checkingLive = false);
        },
      ))
      ..loadRequest(Uri.parse(embedUrl));
    setState(() => _webCtrl = ctrl);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EXTERNAL LAUNCHER
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(uri);
    }
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _webCtrl = null; _isLive = false; });
    await _loadLinks();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hasPlayer = _activePlatform != _LivePlatform.none;

    return Column(children: [
      _LiveHeader(
        isLive:    _isLive,
        platform:  _activePlatform,
        onRefresh: _refresh,
      ),
      Expanded(
        child: _loading
            ? const _LoadingState()
            : !hasPlayer
                ? _NoStreamState(onRefresh: _refresh)
                : RefreshIndicator(
                    color:           AppColors.primary,
                    backgroundColor: AppColors.surface,
                    onRefresh:       _refresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 140),
                      child: Column(children: [

                        // Player
                        _StreamPlayer(
                          ctrl:          _webCtrl,
                          isLive:        _isLive,
                          checking:      _checkingLive,
                          platform:      _activePlatform,
                          externalUrl:   _activeUrl,
                          onOpenBrowser: () => _launch(_activeUrl),
                        ),

                        const SizedBox(height: 20),

                        // Status
                        _StatusCard(
                          isLive:   _isLive,
                          checking: _checkingLive,
                          platform: _activePlatform,
                        ),

                        const SizedBox(height: 24),

                        // Social buttons
                        if (_instagram != null || _paypal != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(children: [
                              const _SectionLabel(
                                icon: Icons.link_rounded,
                                text: 'Connect & Support',
                              ),
                              const SizedBox(height: 12),
                              Row(children: [
                                if (_instagram != null)
                                  Expanded(child: _SocialBtn(
                                    label: 'Instagram',
                                    icon:  Icons.camera_alt_rounded,
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFE1306C),
                                        Color(0xFFF77737),
                                        Color(0xFF833AB4),
                                      ],
                                      begin: Alignment.topLeft,
                                      end:   Alignment.bottomRight,
                                    ),
                                    onTap: () => _launch(_instagram!.url),
                                  )),
                                if (_instagram != null && _paypal != null)
                                  const SizedBox(width: 12),
                                if (_paypal != null)
                                  Expanded(child: _SocialBtn(
                                    label: 'Donate',
                                    icon:  Icons.volunteer_activism_rounded,
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF009CDE),
                                        Color(0xFF003087),
                                      ],
                                      begin: Alignment.topLeft,
                                      end:   Alignment.bottomRight,
                                    ),
                                    onTap: () => _launch(_paypal!.url),
                                  )),
                              ]),
                            ]),
                          ),

                        // ── Merch Banner ──────────────────────────────────
                        if (_bannerLoaded) ...[
                          const SizedBox(height: 20),
                          _LiveMerchBanner(
                            shopifyUrl: _shopifyUrl,
                            onLaunch:   _launch,
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Other links — excluye Shopify y TikTok ya manejados
                        _OtherLinksSection(onLaunch: _launch),
                      ]),
                    ),
                  ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MERCH BANNER — live screen version con carrusel automático
// ══════════════════════════════════════════════════════════════════════════════
class _LiveMerchBanner extends StatefulWidget {
  const _LiveMerchBanner({required this.shopifyUrl, required this.onLaunch});
  final String?                shopifyUrl;
  final void Function(String)  onLaunch;

  @override
  State<_LiveMerchBanner> createState() => _LiveMerchBannerState();
}

class _LiveMerchBannerState extends State<_LiveMerchBanner>
    with SingleTickerProviderStateMixin {

  static const _images = [
    'assets/images/merch_banner.png',
    'assets/images/merch_banner_2.png',
    'assets/images/merch_banner_3.png',
  ];

  late final AnimationController _ctrl;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;

  int  _current   = 0;
  int  _next      = 1;
  bool _animating = false;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

    _slide = Tween<Offset>(
      begin: const Offset(0.08, 0),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _current   = _next;
          _next      = (_next + 1) % _images.length;
          _animating = false;
        });
        _ctrl.reset();
        _startTimer();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _startTimer());
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      _triggerTransition();
    });
  }

  void _triggerTransition() {
    if (!mounted || _animating) return;
    setState(() => _animating = true);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap(BuildContext ctx) async {
    final url = widget.shopifyUrl;

    // Si no hay URL configurada → mostrar mensaje "coming soon"
    if (url == null || url.trim().isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
          ),
          content: Row(children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                  colors: [AppColors.accent, AppColors.primary]).createShader(b),
              child: const Icon(Icons.rocket_launch_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text(
              'Merch store coming soon! Stay tuned.',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            )),
          ]),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Si hay URL → abrir en browser externo directamente
    widget.onLaunch(url.trim());
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = widget.shopifyUrl != null && widget.shopifyUrl!.trim().isNotEmpty;

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AspectRatio(
          aspectRatio: 16 / 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Imagen actual ─────────────────────────────────────────
              _BannerImage(
                path:   _images[_current],
                hasUrl: hasUrl,
              ),

              // ── Imagen siguiente con fade + slide ─────────────────────
              if (_animating)
                FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: _BannerImage(
                      path:   _images[_next],
                      hasUrl: hasUrl,
                    ),
                  ),
                ),

              // ── Indicadores de punto ──────────────────────────────────
              Positioned(
                bottom: 8, left: 0, right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_images.length, (i) {
                    final active = i == (_animating ? _next : _current);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width:  active ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widget auxiliar para cada imagen del banner ───────────────────────────────
class _BannerImage extends StatelessWidget {
  const _BannerImage({required this.path, required this.hasUrl});
  final String path;
  final bool   hasUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
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
            child: Image.asset(path, fit: BoxFit.cover),
          ),
        ),
        // Badge: "Coming Soon" si no hay URL, "Shop Now" si hay URL
        Positioned(
          top: 10, right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: hasUrl
                  ? AppColors.primary.withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hasUrl
                    ? AppColors.primary.withValues(alpha: 0.6)
                    : AppColors.surfaceLight.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasUrl) ...[
                  const Icon(Icons.shopping_bag_rounded,
                      color: Colors.white, size: 9),
                  const SizedBox(width: 4),
                ],
                Text(
                  hasUrl ? 'Shop Now' : 'Coming Soon',
                  style: TextStyle(
                    color:         hasUrl ? Colors.white : AppColors.textSecondary,
                    fontSize:      9,
                    fontWeight:    FontWeight.w700,
                    letterSpacing: 0.5,
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

// ══════════════════════════════════════════════════════════════════════════════
// HEADER
// ══════════════════════════════════════════════════════════════════════════════
class _LiveHeader extends StatelessWidget {
  const _LiveHeader({
    required this.isLive,
    required this.platform,
    required this.onRefresh,
  });
  final bool          isLive;
  final _LivePlatform platform;
  final VoidCallback  onRefresh;

  @override
  Widget build(BuildContext context) => Container(
    color:   AppColors.background,
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
    child: Row(children: [
      if (isLive)
        _PulseDot()
      else
        ShaderMask(
          shaderCallback: (b) => const LinearGradient(
              colors: [AppColors.accent, AppColors.primary]).createShader(b),
          child: const Icon(Icons.live_tv_rounded,
              color: Colors.white, size: 22),
        ),
      const SizedBox(width: 8),
      Text(
        isLive ? 'LIVE NOW' : 'LIVE',
        style: TextStyle(
          color:         isLive ? AppColors.primary : AppColors.textPrimary,
          fontSize:      20,
          fontWeight:    FontWeight.w900,
          letterSpacing: -0.5,
        ),
      ),
      if (platform != _LivePlatform.none) ...[
        const SizedBox(width: 8),
        _PlatformBadge(platform: platform),
      ],
      const Spacer(),
      GestureDetector(
        onTap: onRefresh,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color:        AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: AppColors.surfaceLight),
          ),
          child: const Icon(Icons.refresh_rounded,
              color: AppColors.textSecondary, size: 18),
        ),
      ),
    ]),
  );
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.platform});
  final _LivePlatform platform;

  @override
  Widget build(BuildContext context) {
    final isTwitch = platform == _LivePlatform.twitch;
    final color    = isTwitch ? const Color(0xFF9147FF) : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        isTwitch ? 'Twitch' : 'YouTube',
        style: TextStyle(
          color:      color,
          fontSize:   10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STREAM PLAYER
// ══════════════════════════════════════════════════════════════════════════════
class _StreamPlayer extends StatelessWidget {
  const _StreamPlayer({
    required this.ctrl,
    required this.isLive,
    required this.checking,
    required this.platform,
    required this.externalUrl,
    required this.onOpenBrowser,
  });

  final WebViewController? ctrl;
  final bool               isLive;
  final bool               checking;
  final _LivePlatform      platform;
  final String             externalUrl;
  final VoidCallback       onOpenBrowser;

  Color get _glowColor => platform == _LivePlatform.twitch
      ? const Color(0xFF9147FF)
      : AppColors.primary;

  String get _browserLabel => platform == _LivePlatform.twitch
      ? 'Open in Twitch'
      : 'Open in YouTube';

  @override
  Widget build(BuildContext context) {
    final w       = MediaQuery.of(context).size.width;
    final playerH = (w - 32) * 9 / 16;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        Container(
          width:  w - 32,
          height: playerH,
          decoration: BoxDecoration(
            color:        AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLive
                  ? _glowColor.withValues(alpha: 0.5)
                  : AppColors.surfaceLight,
              width: isLive ? 1.5 : 1,
            ),
            boxShadow: isLive
                ? [BoxShadow(
                    color:        _glowColor.withValues(alpha: 0.22),
                    blurRadius:   22,
                    spreadRadius: 2)]
                : [BoxShadow(
                    color:      Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset:     const Offset(0, 4))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(fit: StackFit.expand, children: [
              if (ctrl != null)
                WebViewWidget(controller: ctrl!)
              else
                const _PlayerPlaceholder(),
              if (checking)
                Container(
                  color: AppColors.background.withValues(alpha: 0.65),
                  child: const Center(child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2)),
                ),
              if (isLive)
                Positioned(top: 10, left: 10, child: _LiveBadge()),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onOpenBrowser,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.open_in_new_rounded,
                color: AppColors.textSecondary, size: 12),
            const SizedBox(width: 4),
            Text(_browserLabel,
              style: const TextStyle(
                color:      AppColors.textSecondary,
                fontSize:   11,
                fontWeight: FontWeight.w600,
              )),
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STATUS CARD
// ══════════════════════════════════════════════════════════════════════════════
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isLive,
    required this.checking,
    required this.platform,
  });
  final bool          isLive;
  final bool          checking;
  final _LivePlatform platform;

  @override
  Widget build(BuildContext context) {
    if (checking) return const SizedBox.shrink();
    final name = platform == _LivePlatform.twitch ? 'Twitch' : 'YouTube';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isLive
              ? AppColors.primary.withValues(alpha: 0.07)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLive
                ? AppColors.primary.withValues(alpha: 0.3)
                : AppColors.surfaceLight,
          ),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isLive
                    ? [AppColors.accent, AppColors.primary]
                    : [AppColors.surfaceLight, AppColors.surface],
              ),
            ),
            child: Icon(
              isLive ? Icons.sensors_rounded : Icons.sensors_off_rounded,
              color: isLive ? AppColors.background : AppColors.textSecondary,
              size:  20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isLive
                    ? '🔴 Live Now · $name'
                    : 'No active stream',
                style: TextStyle(
                  color:      isLive
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize:   13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isLive
                    ? 'The channel is streaming right now.'
                    : 'When a live stream starts, it will appear here automatically.',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SOCIAL BUTTON
// ══════════════════════════════════════════════════════════════════════════════
class _SocialBtn extends StatelessWidget {
  const _SocialBtn({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });
  final String       label;
  final IconData     icon;
  final Gradient     gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 52,
      decoration: BoxDecoration(
        gradient:     gradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color:      Colors.black.withValues(alpha: 0.25),
          blurRadius: 10,
          offset:     const Offset(0, 4),
        )],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(label,
          style: const TextStyle(
            color:      Colors.white,
            fontSize:   13,
            fontWeight: FontWeight.w800,
          )),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// OTHER LINKS SECTION
// ══════════════════════════════════════════════════════════════════════════════
class _OtherLinksSection extends StatelessWidget {
  const _OtherLinksSection({required this.onLaunch});
  final void Function(String) onLaunch;

  // ── FIX: Shopify y TikTok excluidos porque ya tienen su propio lugar ───────
  static const _excluded = {
    SocialPlatform.youtube,
    SocialPlatform.twitch,
    SocialPlatform.instagram,
    SocialPlatform.paypal,
    SocialPlatform.shopify,  // ← FIXED: excluido para no duplicar con el banner
    SocialPlatform.tiktok,   // ← excluido si ya tiene tratamiento aparte
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SocialLinkModel>>(
      future: SocialLinkService.instance.fetchAll(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final others = snap.data!
            .where((l) => !_excluded.contains(l.platform))
            .toList();
        if (others.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel(
                  icon: Icons.public_rounded, text: 'More Links'),
              const SizedBox(height: 12),
              ...others.map((l) => _OtherLinkRow(
                link:  l,
                onTap: () => onLaunch(l.url),
              )),
            ],
          ),
        );
      },
    );
  }
}

class _OtherLinkRow extends StatelessWidget {
  const _OtherLinkRow({required this.link, required this.onTap});
  final SocialLinkModel link;
  final VoidCallback    onTap;

  IconData _icon() => switch (link.platform) {
    SocialPlatform.shopify => Icons.store_rounded,
    SocialPlatform.tiktok  => Icons.music_video_rounded,
    _                      => Icons.link_rounded,
  };

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin:  const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border:       Border.all(color: AppColors.surfaceLight),
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color:        AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(_icon(), color: AppColors.primary, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(link.displayLabel,
              style: const TextStyle(
                color:      AppColors.textPrimary,
                fontSize:   13,
                fontWeight: FontWeight.w700,
              )),
            Text(link.url,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        )),
        const Icon(Icons.open_in_new_rounded,
            color: AppColors.textSecondary, size: 16),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED SMALL WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.text});
  final IconData icon;
  final String   text;

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: AppColors.primary, size: 13),
    const SizedBox(width: 6),
    Text(text,
      style: const TextStyle(
        color:      AppColors.textPrimary,
        fontSize:   13,
        fontWeight: FontWeight.w800,
      )),
  ]);
}

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double>   _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _a = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (_, __) => Container(
      width: 10, height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: _a.value),
        boxShadow: [BoxShadow(
          color:        AppColors.primary.withValues(alpha: _a.value * 0.5),
          blurRadius:   6,
          spreadRadius: 1,
        )],
      ),
    ),
  );
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color:        Colors.red,
      borderRadius: BorderRadius.circular(6),
      boxShadow: [BoxShadow(
          color: Colors.red.withValues(alpha: 0.5), blurRadius: 8)],
    ),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.circle, color: Colors.white, size: 6),
      SizedBox(width: 4),
      Text('LIVE',
        style: TextStyle(
          color:         Colors.white,
          fontSize:      10,
          fontWeight:    FontWeight.w900,
          letterSpacing: 1,
        )),
    ]),
  );
}

class _PlayerPlaceholder extends StatelessWidget {
  const _PlayerPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surface,
    child: const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.play_circle_outline_rounded,
            color: AppColors.surfaceLight, size: 48),
        SizedBox(height: 10),
        Text('Loading stream…',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12)),
      ]),
    ),
  );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(
        color: AppColors.primary, strokeWidth: 2),
  );
}

class _NoStreamState extends StatelessWidget {
  const _NoStreamState({required this.onRefresh});
  final VoidCallback onRefresh;

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
        child: const Icon(Icons.live_tv_rounded,
            color: AppColors.surfaceLight, size: 32),
      ),
      const SizedBox(height: 16),
      const Text('No channel configured',
        style: TextStyle(
          color:      AppColors.textPrimary,
          fontSize:   15,
          fontWeight: FontWeight.w700,
        )),
      const SizedBox(height: 6),
      const Text(
        'The administrator has not set up\nTwitch or YouTube yet.',
        style: TextStyle(
            color: AppColors.textSecondary, fontSize: 13, height: 1.6),
        textAlign: TextAlign.center),
      const SizedBox(height: 24),
      GestureDetector(
        onTap: onRefresh,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color:        AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: AppColors.surfaceLight),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.refresh_rounded,
                color: AppColors.primary, size: 16),
            SizedBox(width: 6),
            Text('Retry',
              style: TextStyle(
                color:      AppColors.primary,
                fontSize:   13,
                fontWeight: FontWeight.w700,
              )),
          ]),
        ),
      ),
    ]),
  );
}