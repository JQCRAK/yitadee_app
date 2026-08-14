import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/app_theme.dart';
import '../../models/artist_model.dart';
import '../../models/album_model.dart';
import '../../models/song_model.dart';
import '../../models/social_link_model.dart';
import '../../services/artist_service.dart';
import '../../services/album_service.dart';
import '../../services/song_service.dart';
import '../../services/social_link_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Leer imagen de forma segura en iOS y Android
// ─────────────────────────────────────────────────────────────────────────────

/// Convierte cualquier imagen (HEIC, PNG, WEBP) a bytes JPEG válidos.
/// En iOS ImagePicker puede devolver HEIC — esto lo fuerza a JPEG.
Future<Uint8List?> _pickImageSafe() async {
  final picker = ImagePicker();

  // Primer intento: imageQuality < 100 en iOS SIEMPRE produce JPEG
  XFile? picked = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 88,
    maxWidth: 1000,
    maxHeight: 1000,
    requestFullMetadata: false, // evita rutas iCloud inaccesibles en iOS
  );

  if (picked == null) return null;

  // Leer desde File path (más confiable que picked.readAsBytes() en iOS)
  Uint8List bytes;
  try {
    bytes = await File(picked.path).readAsBytes();
  } catch (_) {
    bytes = await picked.readAsBytes();
  }

  if (bytes.isEmpty) return null;

  // Verificar que sean bytes válidos (JPEG o PNG)
  final isJpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
  final isPng  = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;

  if (!isJpeg && !isPng) {
    // Es HEIC u otro formato no soportado — reintentar con compresión forzada
    debugPrint('[ImagePick] Formato no JPEG/PNG detectado, reintentando...');
    picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1000,
      maxHeight: 1000,
      requestFullMetadata: false,
    );
    if (picked == null) return null;
    try {
      bytes = await File(picked.path).readAsBytes();
    } catch (_) {
      bytes = await picked.readAsBytes();
    }
  }

  if (bytes.isEmpty) {
    debugPrint('[ImagePick] ERROR: bytes vacíos después de pick');
    return null;
  }

  debugPrint('[ImagePick] OK: ${bytes.length} bytes');
  return bytes;
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN SHELL
// ─────────────────────────────────────────────────────────────────────────────

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _tab = 0;
  GlobalKey _singlesKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    ArtistService.instance.seedDefaultIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(colors: [AppColors.accent, AppColors.primary]).createShader(b),
            child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 8),
          const Text('Admin Panel', style: TextStyle(color: AppColors.primary, fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
      ),
      body: IndexedStack(index: _tab, children: [
        const _ArtistsTab(),
        const _AlbumsTab(),
        _SinglesTab(key: _singlesKey),
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.surfaceLight)),
        ),
        child: SafeArea(
          child: Row(children: [
            _NavItem(icon: Icons.person_rounded, label: 'Artists', index: 0, current: _tab, onTap: (i) => setState(() => _tab = i)),
            _NavItem(icon: Icons.album_rounded, label: 'Albums', index: 1, current: _tab, onTap: (i) => setState(() => _tab = i)),
            _NavItem(icon: Icons.music_note_rounded, label: 'Singles', index: 2, current: _tab, onTap: (i) => setState(() {
              _tab = i;
              _singlesKey = GlobalKey();
            })),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.index, required this.current, required this.onTap});
  final IconData icon;
  final String label;
  final int index, current;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: active ? 26 : 22, color: active ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? AppColors.primary : AppColors.textSecondary,
            )),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — ARTISTS
// ─────────────────────────────────────────────────────────────────────────────

class _ArtistsTab extends StatefulWidget {
  const _ArtistsTab();
  @override
  State<_ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends State<_ArtistsTab> {
  List<ArtistModel> _artists = [];
  DocumentSnapshot? _lastDoc;
  bool _loadingArtists = false;
  bool _hasMore = true;
  List<SocialLinkModel> _links = [];
  bool _loadingLinks = false;

  @override
  void initState() {
    super.initState();
    _loadArtists();
    _loadLinks();
  }

  Future<void> _loadArtists({bool reset = false}) async {
    if (_loadingArtists) return;
    setState(() => _loadingArtists = true);
    if (reset) { _artists = []; _lastDoc = null; _hasMore = true; }
    final (list, last) = await ArtistService.instance.fetchPage(after: _lastDoc);
    setState(() {
      _artists.addAll(list);
      _lastDoc = last;
      _hasMore = list.length == 10;
      _loadingArtists = false;
    });
  }

  Future<void> _loadLinks() async {
    setState(() => _loadingLinks = true);
    final list = await SocialLinkService.instance.fetchAll();
    setState(() { _links = list; _loadingLinks = false; });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: EdgeInsets.zero, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('ARTISTS', style: TextStyle(color: AppColors.background, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
          const Spacer(),
          _GradientButton(label: '+ Add', onTap: () async {
            await showDialog(context: context, builder: (_) => const _ArtistDialog());
            _loadArtists(reset: true);
          }),
        ]),
      ),
      const SizedBox(height: 12),
      if (_artists.isEmpty && !_loadingArtists)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: _EmptyState(icon: Icons.person_outline_rounded, message: 'No artists yet.'),
        )
      else
        ..._artists.map((a) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _ArtistTile(artist: a, onChanged: () => _loadArtists(reset: true)),
        )),
      if (_hasMore)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _LoadMoreButton(onTap: _loadArtists, loading: _loadingArtists),
        ),
      const SizedBox(height: 28),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider(color: AppColors.surfaceLight)),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: const Text('SOCIAL LINKS', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
          const Spacer(),
          _GradientButton(label: '+ Add Link', onTap: () async {
            await showDialog(context: context, builder: (_) => const _SocialLinkDialog());
            _loadLinks();
          }),
        ]),
      ),
      const SizedBox(height: 8),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Text('Store social media URLs here. Update anytime without changing code.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ),
      const SizedBox(height: 12),
      if (_loadingLinks)
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
      else if (_links.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: _EmptyState(icon: Icons.link_off_rounded, message: 'No social links yet.'))
      else
        ..._links.map((l) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _SocialLinkTile(link: l, onChanged: _loadLinks),
        )),
      const SizedBox(height: 32),
    ]);
  }
}

class _ArtistTile extends StatelessWidget {
  const _ArtistTile({required this.artist, required this.onChanged});
  final ArtistModel artist;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 42, height: 42,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [AppColors.accent, AppColors.primary]),
          ),
          child: Center(child: Text(
            artist.name.isNotEmpty ? artist.name[0].toUpperCase() : '?',
            style: const TextStyle(color: AppColors.background, fontWeight: FontWeight.bold, fontSize: 18),
          )),
        ),
        title: Text(artist.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        subtitle: artist.isDefault
            ? const Text('Default artist', style: TextStyle(color: AppColors.primary, fontSize: 11))
            : null,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: AppColors.textSecondary, size: 18),
            onPressed: () async {
              await showDialog(context: context, builder: (_) => _ArtistDialog(existing: artist));
              onChanged();
            },
          ),
          if (!artist.isDefault)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => _ConfirmDialog(
                  title: 'Delete artist?',
                  message: 'Remove "${artist.name}" permanently.',
                  onConfirm: () async {
                    final err = await ArtistService.instance.delete(artist.id);
                    if (err != null && ctx.mounted) {
                      _showSnack(ctx, err, isError: true);
                    } else {
                      onChanged();
                    }
                  },
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ArtistDialog extends StatefulWidget {
  const _ArtistDialog({this.existing});
  final ArtistModel? existing;
  @override
  State<_ArtistDialog> createState() => _ArtistDialogState();
}

class _ArtistDialogState extends State<_ArtistDialog> {
  late final TextEditingController _ctrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.existing?.name ?? '');
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    final err = widget.existing == null
        ? await ArtistService.instance.create(_ctrl.text)
        : await ArtistService.instance.updateName(widget.existing!.id, _ctrl.text);
    if (!mounted) return;
    setState(() { _saving = false; _error = err; });
    if (err == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isEdit ? 'Edit Artist' : 'New Artist', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _AdminField(controller: _ctrl, hint: 'Artist name', icon: Icons.person_rounded),
          if (_error != null) ...[const SizedBox(height: 8), _ErrorText(_error!)],
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(context))),
            const SizedBox(width: 12),
            Expanded(child: _GradientButton(label: isEdit ? 'Save' : 'Add', isLoading: _saving, onTap: _save)),
          ]),
        ],
      )),
    );
  }
}

class _SocialLinkTile extends StatelessWidget {
  const _SocialLinkTile({required this.link, required this.onChanged});
  final SocialLinkModel link;
  final VoidCallback onChanged;

  static const _icons = <SocialPlatform, IconData>{
    SocialPlatform.shopify: Icons.storefront_rounded,
    SocialPlatform.twitch: Icons.live_tv_rounded,
    SocialPlatform.youtube: Icons.play_circle_rounded,
    SocialPlatform.instagram: Icons.camera_alt_rounded,
    SocialPlatform.tiktok: Icons.music_video_rounded,
    SocialPlatform.paypal: Icons.payment_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _icons[link.platform] ?? Icons.link_rounded;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 42, height: 42,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [AppColors.accent, AppColors.primary]),
          ),
          child: Icon(icon, color: AppColors.background, size: 20),
        ),
        title: Text(link.displayLabel, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(link.url, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: AppColors.textSecondary, size: 18),
            onPressed: () async {
              await showDialog(context: context, builder: (_) => _SocialLinkDialog(existing: link));
              onChanged();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => _ConfirmDialog(
                title: 'Delete link?',
                message: 'Remove "${link.displayLabel}" permanently.',
                onConfirm: () async {
                  await SocialLinkService.instance.delete(link.id);
                  onChanged();
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SocialLinkDialog extends StatefulWidget {
  const _SocialLinkDialog({this.existing});
  final SocialLinkModel? existing;
  @override
  State<_SocialLinkDialog> createState() => _SocialLinkDialogState();
}

class _SocialLinkDialogState extends State<_SocialLinkDialog> {
  SocialPlatform _platform = SocialPlatform.instagram;
  final _urlCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _platform = widget.existing!.platform;
      _urlCtrl.text = widget.existing!.url;
    }
  }

  @override
  void dispose() { _urlCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    final err = widget.existing == null
        ? await SocialLinkService.instance.create(platform: _platform, url: _urlCtrl.text)
        : await SocialLinkService.instance.update(id: widget.existing!.id, platform: _platform, url: _urlCtrl.text);
    if (!mounted) return;
    setState(() { _saving = false; _error = err; });
    if (err == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isEdit ? 'Edit Social Link' : 'Add Social Link', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _SectionLabel('Platform'),
          const SizedBox(height: 8),
          DropdownButtonFormField<SocialPlatform>(
            initialValue: _platform,
            dropdownColor: AppColors.surfaceLight,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              filled: true, fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.share_rounded, color: AppColors.textSecondary, size: 20),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            items: SocialPlatform.values.map((p) => DropdownMenuItem(value: p, child: Text(p.label))).toList(),
            onChanged: (p) => setState(() => _platform = p ?? SocialPlatform.instagram),
          ),
          const SizedBox(height: 16),
          _SectionLabel('URL'),
          const SizedBox(height: 8),
          _AdminField(controller: _urlCtrl, hint: 'https://...', icon: Icons.link_rounded),
          if (_error != null) ...[const SizedBox(height: 8), _ErrorText(_error!)],
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(context))),
            const SizedBox(width: 12),
            Expanded(child: _GradientButton(label: isEdit ? 'Save' : 'Add Link', isLoading: _saving, onTap: _save)),
          ]),
        ],
      ))),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — ALBUMS
// ─────────────────────────────────────────────────────────────────────────────

class _AlbumsTab extends StatefulWidget {
  const _AlbumsTab();
  @override
  State<_AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends State<_AlbumsTab> {
  List<AlbumModel> _albums = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false, _hasMore = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    if (reset) { _albums = []; _lastDoc = null; _hasMore = true; }
    final (list, last) = await AlbumService.instance.fetchPage(after: _lastDoc);
    setState(() {
      _albums.addAll(list);
      _lastDoc = last;
      _hasMore = list.length == 10;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(children: [
          Text('${_albums.length} album${_albums.length == 1 ? "" : "s"}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const Spacer(),
          _GradientButton(label: '+ New Album', onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const _AlbumFormScreen()));
            _load(reset: true);
          }),
        ]),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: _albums.isEmpty && !_loading
            ? const _EmptyState(icon: Icons.album_outlined, message: 'No albums yet.')
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _albums.length + (_hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  if (i == _albums.length) return _LoadMoreButton(onTap: _load, loading: _loading);
                  return _AlbumTile(album: _albums[i], onChanged: () => _load(reset: true));
                },
              ),
      ),
    ]);
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.album, required this.onChanged});
  final AlbumModel album;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => _AlbumDetailScreen(album: album)));
        onChanged();
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceLight),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)),
            child: album.coverUrl.isNotEmpty
                ? Image.network(album.coverUrl, width: 72, height: 72, fit: BoxFit.cover)
                : Container(width: 72, height: 72, color: AppColors.surfaceLight, child: const Icon(Icons.album_rounded, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(album.title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(album.artistName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Row(children: [
              _Chip(label: '${album.trackCount} tracks'),
              const SizedBox(width: 6),
              _Chip(label: album.isPaid ? '\$${album.price.toStringAsFixed(0)}' : 'Free', isPaid: album.isPaid),
            ]),
          ])),
          const Padding(padding: EdgeInsets.only(right: 12), child: Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

class _AlbumFormScreen extends StatefulWidget {
  const _AlbumFormScreen({this.existing});
  final AlbumModel? existing;
  @override
  State<_AlbumFormScreen> createState() => _AlbumFormScreenState();
}

class _AlbumFormScreenState extends State<_AlbumFormScreen> {
  final _titleCtrl = TextEditingController();
  ArtistModel? _selectedArtist;
  List<ArtistModel> _artists = [];
  Uint8List? _newCoverBytes;
  String? _coverPreviewUrl;
  bool _isPaid = false;
  double _price = 5.0;  
  DateTime? _releaseDate;
  bool _saving = false;
  String? _error;
  bool _pickingCover = false;

  @override
  void initState() {
    super.initState();
    _loadArtists();
    if (widget.existing != null) {
      final e = widget.existing!;
      _titleCtrl.text = e.title;
      _isPaid = e.isPaid;
      _price = e.price > 0 ? e.price : 5.0;
      _coverPreviewUrl = e.coverUrl;
      _releaseDate = e.releaseDate;
    }
  }

  Future<void> _loadArtists() async {
    final list = await ArtistService.instance.fetchAll();
    if (!mounted) return;
    setState(() {
      _artists = list;
      _selectedArtist = widget.existing != null
          ? list.firstWhere((a) => a.id == widget.existing!.artistId, orElse: () => list.first)
          : list.firstWhere((a) => a.isDefault, orElse: () => list.isNotEmpty ? list.first : const ArtistModel(id: '', name: '', slug: ''));
    });
  }

  // ── FIX iOS: usar _pickImageSafe() que garantiza bytes JPEG válidos ────────
  Future<void> _pickCover() async {
    if (_pickingCover) return;
    _pickingCover = true;
    try {
      if (_coverPreviewUrl != null && _coverPreviewUrl!.isNotEmpty || _newCoverBytes != null) {
        final ok = await _confirmCoverReplace();
        if (!ok) return;
      }
      final bytes = await _pickImageSafe();
      if (bytes == null || bytes.isEmpty) return;
      if (mounted) setState(() { _newCoverBytes = bytes; _coverPreviewUrl = null; });
    } catch (e) {
      debugPrint('Cover pick error: $e');
    } finally {
      _pickingCover = false;
    }
  }
  Future<void> _pickReleaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _releaseDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary:   AppColors.primary,
            onPrimary: AppColors.background,
            surface:   AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _releaseDate = picked);
  }

  Future<bool> _confirmCoverReplace() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(padding: const EdgeInsets.all(24), child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_rounded, color: AppColors.primary, size: 48),
            const SizedBox(height: 16),
            const Text('Replace cover?', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('The current cover will be replaced.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: _OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(ctx, false))),
              const SizedBox(width: 12),
              Expanded(child: _GradientButton(label: 'Replace', onTap: () => Navigator.pop(ctx, true))),
            ]),
          ],
        )),
      ),
    ) ?? false;
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) { setState(() => _error = 'Please enter an album title.'); return; }
    if (_selectedArtist == null || _selectedArtist!.id.isEmpty) { setState(() => _error = 'Please select an artist.'); return; }
    if (widget.existing == null && _newCoverBytes == null) { setState(() => _error = 'Please select a cover image.'); return; }
    // Guard extra: verificar bytes no vacíos antes de subir
    if (_newCoverBytes != null && _newCoverBytes!.isEmpty) {
      setState(() => _error = 'Cover image is invalid. Please select again.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    if (widget.existing == null) {
      final (_, err) = await AlbumService.instance.create(
        title: _titleCtrl.text.trim(), artistId: _selectedArtist!.id,
        artistName: _selectedArtist!.name, coverBytes: _newCoverBytes!,
        isPaid: _isPaid, price: _isPaid ? _price : 0.0,
        releaseDate: _releaseDate,
      );
      if (!mounted) return;
      if (err != null) { setState(() { _saving = false; _error = err; }); return; }
    } else {
      final err = await AlbumService.instance.update(
        albumId: widget.existing!.id, title: _titleCtrl.text.trim(),
        artistId: _selectedArtist!.id, artistName: _selectedArtist!.name,
        isPaid: _isPaid, price: _isPaid ? _price : 0.0,
        releaseDate: _releaseDate,
      );
      if (!mounted) return;
      if (err != null) { setState(() { _saving = false; _error = err; }); return; }
      if (_newCoverBytes != null && _newCoverBytes!.isNotEmpty) {
        final ce = await AlbumService.instance.updateCover(widget.existing!.id, _newCoverBytes!);
        if (!mounted) return;
        if (ce != null) { setState(() { _saving = false; _error = ce; }); return; }
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() { _titleCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(isEdit ? 'Edit Album' : 'New Album', style: const TextStyle(color: AppColors.primary, fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: GestureDetector(
            onTap: _pickCover,
            child: Container(
              width: 150, height: 150,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 2),
              ),
              child: _newCoverBytes != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(_newCoverBytes!, fit: BoxFit.cover))
                  : _coverPreviewUrl != null && _coverPreviewUrl!.isNotEmpty
                      ? Stack(children: [
                          ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(_coverPreviewUrl!, fit: BoxFit.cover, width: 150, height: 150)),
                          Positioned(bottom: 8, right: 8, child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.edit_rounded, color: AppColors.background, size: 14),
                          )),
                        ])
                      : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary, size: 36),
                          SizedBox(height: 8),
                          Text('Album Cover', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ]),
            ),
          )),
          const SizedBox(height: 8),
          const Center(child: Text('Tap to select cover image', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
          const SizedBox(height: 24),
          _SectionLabel('Album Title'),
          const SizedBox(height: 8),
          _AdminField(controller: _titleCtrl, hint: 'e.g. Drip Season Vol. 1', icon: Icons.title_rounded),
          const SizedBox(height: 20),
          _SectionLabel('Artist'),
          const SizedBox(height: 8),
          _ArtistDropdown(
            artists: _artists, selected: _selectedArtist,
            onChanged: (a) => setState(() => _selectedArtist = a),
            onAddNew: () async { await showDialog(context: context, builder: (_) => const _ArtistDialog()); _loadArtists(); },
          ),
          const SizedBox(height: 20),
          _SectionLabel('Access'),
          const SizedBox(height: 8),
          _ToggleRow(label: _isPaid ? 'Paid' : 'Free', value: _isPaid, onChanged: (v) => setState(() { _isPaid = v; if (!v) _price = 0.0; })),
          if (_isPaid) ...[
            const SizedBox(height: 10),
            _AlbumPriceSelector(value: _price, onChanged: (v) => setState(() => _price = v)),
            const SizedBox(height: 6),
            const Text('Rule: all tracks in a paid album will be set to Free automatically.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
          const SizedBox(height: 20),
          _SectionLabel('Release Date  (optional)'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickReleaseDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_rounded,
                    color: AppColors.textSecondary, size: 20),
                const SizedBox(width: 10),
                Text(
                  _releaseDate != null
                      ? '${_releaseDate!.day}/${_releaseDate!.month}/${_releaseDate!.year}'
                      : 'Select release date',
                  style: TextStyle(
                    color: _releaseDate != null
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                if (_releaseDate != null)
                  GestureDetector(
                    onTap: () => setState(() => _releaseDate = null),
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary, size: 16),
                  ),
              ]),
            ),
          ),
          if (_error != null) ...[const SizedBox(height: 16), _ErrorText(_error!)],
          const SizedBox(height: 32),
          _GradientButton(label: isEdit ? 'Save Changes' : 'Create Album', isLoading: _saving, onTap: _save, fullWidth: true),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

class _AlbumDetailScreen extends StatefulWidget {
  const _AlbumDetailScreen({required this.album});
  final AlbumModel album;
  @override
  State<_AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<_AlbumDetailScreen> {
  List<SongModel> _tracks = [];
  bool _loading = false;
  late AlbumModel _album;

  // ── Reorder mode ──────────────────────────────────────────────────────────
  bool _reorderMode = false;
  List<SongModel> _reorderList = []; // copia local mientras se edita
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _album = widget.album;
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    setState(() => _loading = true);
    final list = await SongService.instance.fetchAlbumTracks(_album.id);
    setState(() {
      _tracks = list;
      _reorderList = List.from(list);
      _loading = false;
    });
  }

  Future<void> _reloadAlbum() async {
    final r = await AlbumService.instance.fetchById(_album.id);
    if (r != null && mounted) setState(() => _album = r);
  }

  // ── Reorder helpers ───────────────────────────────────────────────────────
  void _enterReorderMode() {
    setState(() {
      _reorderList = List.from(_tracks);
      _reorderMode = true;
    });
  }

  void _cancelReorder() {
    setState(() {
      _reorderList = List.from(_tracks);
      _reorderMode = false;
    });
  }

  void _moveTrack(int from, int to) {
    if (to < 0 || to >= _reorderList.length) return;
    setState(() {
      final song = _reorderList.removeAt(from);
      _reorderList.insert(to, song);
    });
  }

  void _moveToFirst(int index) {
    if (index == 0) return;
    setState(() {
      final song = _reorderList.removeAt(index);
      _reorderList.insert(0, song);
    });
  }

  void _moveToLast(int index) {
    if (index == _reorderList.length - 1) return;
    setState(() {
      final song = _reorderList.removeAt(index);
      _reorderList.add(song);
    });
  }

  Future<void> _saveReorder() async {
    setState(() => _saving = true);
    final err = await SongService.instance.reorderAlbumTracks(_reorderList);
    if (!mounted) return;
    if (err != null) {
      _showSnack(context, err, isError: true);
      setState(() => _saving = false);
    } else {
      await _loadTracks();
      setState(() {
        _reorderMode = false;
        _saving = false;
      });
    }
  }

  Future<void> _deleteAlbum() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.orangeAccent, size: 40),
              const SizedBox(height: 12),
              const Text('Delete album?',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Remove all tracks first. This cannot be undone.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                    child: _OutlineButton(
                        label: 'Cancel',
                        onTap: () => Navigator.pop(ctx, false))),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, true),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.5)),
                      ),
                      child: const Center(
                          child: Text('Delete',
                              style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    ) ??
        false;

    if (!confirmed || !mounted) return;
    final err = await AlbumService.instance.delete(_album.id);
    if (!mounted) return;
    if (err != null) {
      _showSnack(context, err, isError: true);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary, size: 20),
          onPressed: _reorderMode ? _cancelReorder : () => Navigator.pop(context),
        ),
        title: Text(
          _reorderMode ? 'Reorder Tracks' : _album.title,
          style: const TextStyle(
              color: AppColors.primary,
              fontSize: 17,
              fontWeight: FontWeight.bold),
        ),
        actions: _reorderMode
            ? [
                // Cancelar
                TextButton(
                  onPressed: _saving ? null : _cancelReorder,
                  child: const Text('Cancel',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ),
                // Guardar
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _saving
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary)),
                        )
                      : TextButton(
                          onPressed: _saveReorder,
                          child: const Text('Save',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                        ),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.edit_rounded,
                      color: AppColors.primary, size: 20),
                  onPressed: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                _AlbumFormScreen(existing: _album)));
                    await _reloadAlbum();
                    await _loadTracks();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 20),
                  onPressed: _deleteAlbum,
                ),
              ],
      ),
      body: Column(
        children: [
          // ── Header del álbum (se oculta en modo reorder) ──────────────
          if (!_reorderMode) ...[
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _album.coverUrl.isNotEmpty
                      ? Image.network(_album.coverUrl,
                          width: 90, height: 90, fit: BoxFit.cover)
                      : Container(
                          width: 90,
                          height: 90,
                          color: AppColors.surface,
                          child: const Icon(Icons.album_rounded,
                              color: AppColors.textSecondary, size: 36)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_album.artistName,
                            style: const TextStyle(
                                color: AppColors.primary, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                            '${_album.trackCount} track${_album.trackCount == 1 ? "" : "s"}',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                        const SizedBox(height: 6),
                        _Chip(
                            label: _album.isPaid
                                ? 'Paid · \$${_album.price.toStringAsFixed(0)}'
                                : 'Free',
                            isPaid: _album.isPaid),
                      ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(
                  child: _GradientButton(
                    label: '+ Add Song',
                    fullWidth: true,
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => _SongUploadScreen(
                                    type: SongType.albumTrack,
                                    albumId: _album.id,
                                    albumTitle: _album.title,
                                    albumIsPaid: _album.isPaid,
                                  )));
                      await _reloadAlbum();
                      await _loadTracks();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                // Botón reorder
                if (_tracks.length > 1)
                  GestureDetector(
                    onTap: _enterReorderMode,
                    child: Container(
                      height: 46,
                      width: 46,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.swap_vert_rounded,
                          color: AppColors.primary, size: 22),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            const Divider(color: AppColors.surfaceLight, height: 1),
          ],

          // ── Hint modo reorder ─────────────────────────────────────────
          if (_reorderMode)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded,
                    color: AppColors.primary, size: 15),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Use the arrows to reorder. Press Save when done.',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12),
                  ),
                ),
              ]),
            ),

          // ── Lista ─────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary))
                : (_reorderMode ? _reorderList : _tracks).isEmpty
                    ? const _EmptyState(
                        icon: Icons.music_off_rounded,
                        message: 'No tracks yet.')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: (_reorderMode ? _reorderList : _tracks)
                            .length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final song = (_reorderMode
                              ? _reorderList
                              : _tracks)[i];

                          if (_reorderMode) {
                            return _ReorderTrackRow(
                              song: song,
                              position: i,
                              total: _reorderList.length,
                              onMoveUp: () => _moveTrack(i, i - 1),
                              onMoveDown: () => _moveTrack(i, i + 1),
                              onMoveFirst: () => _moveToFirst(i),
                              onMoveLast: () => _moveToLast(i),
                            );
                          }

                          return _SongTile(
                            song: song,
                            showAlbumActions: true,
                            albumIsPaid: _album.isPaid,
                            onChanged: () async {
                              await _reloadAlbum();
                              await _loadTracks();
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3 — SINGLES
// ─────────────────────────────────────────────────────────────────────────────

class _SinglesTab extends StatefulWidget {
  const _SinglesTab({super.key});
  @override
  State<_SinglesTab> createState() => _SinglesTabState();
}

class _SinglesTabState extends State<_SinglesTab> {
  List<SongModel> _singles = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false, _hasMore = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    if (reset) { _singles = []; _lastDoc = null; _hasMore = true; }
    final (list, last) = await SongService.instance.fetchSinglesPage(after: _lastDoc);
    setState(() { _singles.addAll(list); _lastDoc = last; _hasMore = list.length == 10; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(children: [
          Text('${_singles.length} single${_singles.length == 1 ? "" : "s"}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const Spacer(),
          _GradientButton(label: '+ Upload Single', onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const _SongUploadScreen(type: SongType.single)));
            _load(reset: true);
          }),
        ]),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: _singles.isEmpty && !_loading
            ? const _EmptyState(icon: Icons.music_note_rounded, message: 'No singles yet.')
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _singles.length + (_hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  if (i == _singles.length) return _LoadMoreButton(onTap: _load, loading: _loading);
                  return _SongTile(song: _singles[i], onChanged: () => _load(reset: true));
                },
              ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SONG TILE
// ─────────────────────────────────────────────────────────────────────────────

class _SongTile extends StatelessWidget {
  const _SongTile({required this.song, required this.onChanged, this.showAlbumActions = false, this.albumIsPaid});
  final SongModel song;
  final VoidCallback onChanged;
  final bool showAlbumActions;
  final bool? albumIsPaid;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: song.coverUrl.isNotEmpty
              ? Image.network(song.coverUrl, width: 48, height: 48, fit: BoxFit.cover)
              : Container(width: 48, height: 48, color: AppColors.surfaceLight, child: const Icon(Icons.music_note_rounded, color: AppColors.textSecondary)),
        ),
        title: Text(song.title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            song.featuring.isNotEmpty ? '${song.artistName}  ft. ${song.featuring}' : song.artistName,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(children: [
            _Chip(label: song.durationDisplay),
            const SizedBox(width: 6),
            _Chip(label: song.genreDisplay),
            const SizedBox(width: 6),
            _Chip(label: song.isPaid ? '\$${song.price.toStringAsFixed(0)}' : 'Free', isPaid: song.isPaid),
          ]),
        ]),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary, size: 20),
          color: AppColors.surface,
          itemBuilder: (_) => [
            if (!showAlbumActions)
              const PopupMenuItem(value: 'move', child: Row(children: [Icon(Icons.drive_file_move_outlined, color: AppColors.primary, size: 18), SizedBox(width: 10), Text('Move to Album', style: TextStyle(color: AppColors.textPrimary))])),
            if (showAlbumActions)
              const PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.remove_circle_outline_rounded, color: Colors.orangeAccent, size: 18), SizedBox(width: 10), Text('Remove from Album', style: TextStyle(color: AppColors.textPrimary))])),
            const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, color: AppColors.primary, size: 18), SizedBox(width: 10), Text('Edit', style: TextStyle(color: AppColors.textPrimary))])),
            const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18), SizedBox(width: 10), Text('Delete', style: TextStyle(color: Colors.redAccent))])),
          ],
          onSelected: (action) {
            if (action == 'move') _showMoveToAlbum(context);
            if (action == 'remove') _confirmRemoveFromAlbum(context);
            if (action == 'edit') _openEdit(context);
            if (action == 'delete') _confirmDelete(context);
          },
        ),
      ),
    );
  }

  void _showMoveToAlbum(BuildContext context) => showDialog(context: context, builder: (_) => _MoveToAlbumDialog(song: song, onMoved: onChanged));

  void _openEdit(BuildContext context) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => _SongUploadScreen(
      type: song.type,
      albumId: song.albumId.isNotEmpty ? song.albumId : null,
      albumTitle: song.albumTitle.isNotEmpty ? song.albumTitle : null,
      albumIsPaid: albumIsPaid,
      existing: song,
    )));
    onChanged();
  }

  void _confirmRemoveFromAlbum(BuildContext context) => showDialog(
    context: context,
    builder: (ctx) => _ConfirmDialog(
      title: 'Remove from album?',
      message: '"${song.title}" will become a free single.',
      onConfirm: () async { await SongService.instance.removeFromAlbum(song.id, song.albumId); onChanged(); },
    ),
  );

  void _confirmDelete(BuildContext context) => showDialog(
    context: context,
    builder: (ctx) => _ConfirmDialog(
      title: 'Delete song?',
      message: 'Permanently deletes "${song.title}" from Firebase and storage.',
      onConfirm: () async {
        final err = await SongService.instance.delete(song);
        if (err != null && ctx.mounted) { _showSnack(ctx, err, isError: true); } else { onChanged(); }
      },
    ),
  );
}
// ─── Reorder Track Row ────────────────────────────────────────────────────────
class _ReorderTrackRow extends StatelessWidget {
  const _ReorderTrackRow({
    required this.song,
    required this.position,
    required this.total,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onMoveFirst,
    required this.onMoveLast,
  });

  final SongModel  song;
  final int        position;
  final int        total;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onMoveFirst;
  final VoidCallback onMoveLast;

  bool get _isFirst => position == 0;
  bool get _isLast  => position == total - 1;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          // ── Número de posición ─────────────────────────────────────────
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${position + 1}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // ── Cover ──────────────────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: song.coverUrl.isNotEmpty
                ? Image.network(song.coverUrl,
                    width: 40, height: 40, fit: BoxFit.cover)
                : Container(
                    width: 40,
                    height: 40,
                    color: AppColors.surfaceLight,
                    child: const Icon(Icons.music_note_rounded,
                        color: AppColors.textSecondary, size: 18)),
          ),
          const SizedBox(width: 10),

          // ── Info ───────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  song.durationDisplay,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),

          // ── Botones de control ─────────────────────────────────────────
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Primero
              _ReorderBtn(
                icon: Icons.keyboard_double_arrow_up_rounded,
                enabled: !_isFirst,
                onTap: onMoveFirst,
                tooltip: 'Move to first',
              ),
              // Arriba
              _ReorderBtn(
                icon: Icons.keyboard_arrow_up_rounded,
                enabled: !_isFirst,
                onTap: onMoveUp,
                tooltip: 'Move up',
              ),
              // Abajo
              _ReorderBtn(
                icon: Icons.keyboard_arrow_down_rounded,
                enabled: !_isLast,
                onTap: onMoveDown,
                tooltip: 'Move down',
              ),
              // Último
              _ReorderBtn(
                icon: Icons.keyboard_double_arrow_down_rounded,
                enabled: !_isLast,
                onTap: onMoveLast,
                tooltip: 'Move to last',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReorderBtn extends StatelessWidget {
  const _ReorderBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.tooltip,
  });
  final IconData     icon;
  final bool         enabled;
  final VoidCallback onTap;
  final String       tooltip;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(
          icon,
          size: 22,
          color: enabled
              ? AppColors.primary
              : AppColors.surfaceLight,
        ),
      ),
    );
  }
}

// ─── Move to Album Dialog ─────────────────────────────────────────────────────

class _MoveToAlbumDialog extends StatefulWidget {
  const _MoveToAlbumDialog({required this.song, required this.onMoved});
  final SongModel song;
  final VoidCallback onMoved;
  @override
  State<_MoveToAlbumDialog> createState() => _MoveToAlbumDialogState();
}

class _MoveToAlbumDialogState extends State<_MoveToAlbumDialog> {
  List<AlbumModel> _albums = [];
  AlbumModel? _selected;
  bool _loading = true, _moving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AlbumService.instance.fetchAll().then((list) {
      if (mounted) setState(() { _albums = list; _loading = false; });
    });
  }

  Future<void> _move() async {
    if (_selected == null) { setState(() => _error = 'Select an album.'); return; }
    setState(() { _moving = true; _error = null; });
    final err = await SongService.instance.moveToAlbum(
      songId: widget.song.id, albumId: _selected!.id,
      albumTitle: _selected!.title, albumIsPaid: _selected!.isPaid,
      trackNumber: _selected!.trackCount + 1,
    );
    if (!mounted) return;
    setState(() { _moving = false; _error = err; });
    if (err == null) { Navigator.pop(context); widget.onMoved(); }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Move to Album', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('"${widget.song.title}"', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 16),
        _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : DropdownButtonFormField<AlbumModel>(
                hint: const Text('Select album', style: TextStyle(color: AppColors.textSecondary)),
                dropdownColor: AppColors.surfaceLight,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  filled: true, fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: _albums.map((a) => DropdownMenuItem(value: a, child: Row(children: [
                  Text(a.title),
                  const SizedBox(width: 8),
                  _Chip(label: a.isPaid ? 'Paid' : 'Free', isPaid: a.isPaid),
                ]))).toList(),
                onChanged: (a) => setState(() => _selected = a),
              ),
        if (_selected?.isPaid == true)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('Paid album — song will be set to Free.', style: TextStyle(color: Colors.orangeAccent, fontSize: 11))),
        if (_error != null) ...[const SizedBox(height: 8), _ErrorText(_error!)],
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(context))),
          const SizedBox(width: 12),
          Expanded(child: _GradientButton(label: 'Move', isLoading: _moving, onTap: _move)),
        ]),
      ],
    )),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SONG UPLOAD / EDIT SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class _SongUploadScreen extends StatefulWidget {
  const _SongUploadScreen({required this.type, this.albumId, this.albumTitle, this.albumIsPaid, this.existing});
  final SongType type;
  final String? albumId, albumTitle;
  final bool? albumIsPaid;
  final SongModel? existing;
  @override
  State<_SongUploadScreen> createState() => _SongUploadScreenState();
}

class _SongUploadScreenState extends State<_SongUploadScreen> with WidgetsBindingObserver {
  final _titleCtrl = TextEditingController();
  final _featuringCtrl = TextEditingController();
  final _customGenreCtrl = TextEditingController();
  final _lyricsCtrl = TextEditingController();

  List<ArtistModel> _artists = [];
  ArtistModel? _selectedArtist;
  SongGenre _selectedGenre = SongGenre.autotuneRap;

  Uint8List? _coverBytes;
  String? _existingCoverUrl;
  Uint8List? _audioBytes;
  String? _audioFileName;
  String? _existingAudioUrl;
  String _audioExtension = 'mp3';
  int _audioDuration = 0;

  AudioPlayer? _player;
  bool _playerPlaying = false;
  bool _playerLoading = false;

  File? _currentTmpFile;

  bool _isPaid = false;
  double _price = 2.0;
  DateTime? _releaseDate;
  int _trackOrder = 0;
  bool _uploading = false;
  double _progress = 0.0;
  String? _error;

  bool _pickingAudio = false;
  bool _pickingCover = false;
  bool _loadingAudio = false;

  bool get _isEdit => widget.existing != null;

  String _toTitleCase(String input) {
    return input
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  String _cleanAudioTitle(String input) {
    String clean = input;
    clean = clean.replaceAllMapped(
      RegExp(r'\(([^)]*(?:mp3|mp4|wav|flac|aac|ogg|kbps|kbit|192|128|160|320|256|44k|48k)[^)]*)\)', caseSensitive: false),
      (_) => '',
    );
    clean = clean.replaceAllMapped(
      RegExp(r'\[([^\]]*(?:mp3|mp4|wav|flac|aac|ogg|kbps|kbit|192|128|160|320|256|44k|48k)[^\]]*)\]', caseSensitive: false),
      (_) => '',
    );
    clean = clean.replaceAll(RegExp(r'\s+(320|256|192|160|128|96)\s*$'), '');
    return clean.trim();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isPaid = widget.albumIsPaid == true ? false : (widget.existing?.isPaid ?? false);
    _price = widget.existing?.price ?? 2.0;
    if (_isEdit) {
      final s = widget.existing!;
      _titleCtrl.text = s.title;
      _featuringCtrl.text = s.featuring;
      _lyricsCtrl.text = s.lyrics;
      _existingCoverUrl = s.coverUrl;
      _existingAudioUrl = s.audioUrl;
      _audioDuration = s.duration;
      _selectedGenre = SongGenre.fromValue(s.genre);
      if (s.genre == 'other') _customGenreCtrl.text = s.customGenre;
      _releaseDate = s.releaseDate;
      _trackOrder  = s.trackOrder;
    }
    _loadArtists();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player?.stop();
    _player?.release();
    _player?.dispose();
    _currentTmpFile?.delete().catchError((e) => File(''));
    _titleCtrl.dispose();
    _featuringCtrl.dispose();
    _customGenreCtrl.dispose();
    _lyricsCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      if (_playerPlaying) { _player?.pause(); if (mounted) setState(() => _playerPlaying = false); }
    }
  }

  Future<void> _loadArtists() async {
    final list = await ArtistService.instance.fetchAll();
    if (!mounted) return;
    setState(() {
      _artists = list;
      _selectedArtist = _isEdit
          ? list.firstWhere((a) => a.id == widget.existing!.artistId, orElse: () => list.first)
          : list.firstWhere((a) => a.isDefault, orElse: () => list.isNotEmpty ? list.first : const ArtistModel(id: '', name: '', slug: ''));
    });
  }

  // ── FIX iOS: usar _pickImageSafe() que garantiza bytes JPEG válidos ─────────
  Future<void> _pickCover() async {
    if (_pickingCover || _pickingAudio) return;
    _pickingCover = true;
    try {
      final bytes = await _pickImageSafe();
      if (bytes == null || bytes.isEmpty) return;
      if (mounted) setState(() { _coverBytes = bytes; });
    } catch (e) {
      debugPrint('Cover pick error: $e');
    } finally {
      _pickingCover = false;
    }
  }
  Future<void> _pickReleaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _releaseDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary:   AppColors.primary,
            onPrimary: AppColors.background,
            surface:   AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _releaseDate = picked);
  }

  Future<bool> _requestAudioPermission() async {
    if (Platform.isIOS) return true;
    PermissionStatus status = await Permission.audio.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      if (mounted) _showPermissionDenied(context, 'Audio Access Required', 'Enable audio/storage access in Settings.');
      return false;
    }
    status = await Permission.audio.request();
    if (status.isGranted) return true;
    if (status.isDenied || status.isRestricted) {
      status = await Permission.storage.request();
      if (status.isGranted) return true;
    }
    if (status.isPermanentlyDenied && mounted) {
      _showPermissionDenied(context, 'Audio Access Required', 'Enable audio/storage access in Settings.');
      return false;
    }
    return status.isGranted;
  }

  Future<void> _pickAudio() async {
    if (_pickingAudio || _pickingCover) return;
    _pickingAudio = true;

    try {
      if (!await _requestAudioPermission()) return;
      if (mounted) setState(() => _loadingAudio = true);

      FilePickerResult? result;
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'flac'],
          allowMultiple: false,
          withData: Platform.isAndroid,
          withReadStream: false,
        );
      } on Exception catch (e) {
        debugPrint('FilePicker error: $e');
        if (mounted) setState(() => _loadingAudio = false);
        return;
      }

      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _loadingAudio = false);
        return;
      }

      final file = result.files.first;

      Uint8List? bytes;
      if (file.path != null && file.path!.isNotEmpty) {
        try {
          bytes = await File(file.path!).readAsBytes();
        } catch (e) {
          debugPrint('Failed to read file from path: $e');
        }
      }
      bytes ??= file.bytes;

      if (bytes == null || bytes.isEmpty) {
        if (mounted) setState(() => _loadingAudio = false);
        return;
      }

      final ext = (file.extension ?? 'mp3').toLowerCase();

      await _player?.stop();
      await _player?.release();
      await _player?.dispose();
      _player = null;

      final nameWithoutExt = file.name.contains('.')
          ? file.name.substring(0, file.name.lastIndexOf('.'))
          : file.name;

      if (mounted) {
        setState(() {
          _audioBytes = bytes;
          _audioFileName = file.name;
          _audioExtension = ext == 'wav' ? 'wav' : 'mp3';
          _playerPlaying = false;
          _playerLoading = false;
          _titleCtrl.text = _toTitleCase(_cleanAudioTitle(nameWithoutExt));
          _existingCoverUrl = null;
          _coverBytes = null;
          _audioDuration = 0;
          _loadingAudio = true;
        });
      }

      await _extractDuration(bytes);
      await _tryExtractCover(bytes);

    } finally {
      _pickingAudio = false;
      if (mounted) setState(() => _loadingAudio = false);
    }
  }

  Future<void> _tryExtractCover(Uint8List audioBytes) async {
    try {
      final cover = await _extractEmbeddedCover(audioBytes);
      if (cover != null && mounted) setState(() => _coverBytes = cover);
    } catch (_) {}
  }

  Future<Uint8List?> _extractEmbeddedCover(Uint8List bytes) async {
    try {
      if (bytes.length < 10) return null;
      if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) return null;

      final version = bytes[3];
      final flags = bytes[5];
      final tagSize = ((bytes[6] & 0x7F) << 21) | ((bytes[7] & 0x7F) << 14) | ((bytes[8] & 0x7F) << 7) | (bytes[9] & 0x7F);
      if (tagSize <= 0 || tagSize > bytes.length) return null;

      int offset = 10;

      if ((flags & 0x40) != 0 && version >= 3) {
        if (offset + 4 > bytes.length) return null;
        int extSize;
        if (version == 4) {
          extSize = ((bytes[offset] & 0x7F) << 21) | ((bytes[offset+1] & 0x7F) << 14) | ((bytes[offset+2] & 0x7F) << 7) | (bytes[offset+3] & 0x7F);
        } else {
          extSize = (bytes[offset] << 24) | (bytes[offset+1] << 16) | (bytes[offset+2] << 8) | bytes[offset+3];
        }
        offset += extSize;
        if (offset >= bytes.length) return null;
      }

      final tagEnd = 10 + tagSize;

      while (offset < tagEnd && offset < bytes.length) {
        if (version == 2) {
          if (offset + 6 > bytes.length) break;
          final id = String.fromCharCodes(bytes.sublist(offset, offset + 3));
          final sz = (bytes[offset+3] << 16) | (bytes[offset+4] << 8) | bytes[offset+5];
          if (sz <= 0) break;
          if (id == 'PIC') {
            final img = _parsePicFrame(bytes, offset + 6, sz, isV22: true);
            if (img != null) return img;
          }
          offset += 6 + sz;
        } else {
          if (offset + 10 > bytes.length) break;
          final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
          if (bytes[offset] == 0) break;
          int sz;
          if (version == 4) {
            sz = ((bytes[offset+4] & 0x7F) << 21) | ((bytes[offset+5] & 0x7F) << 14) | ((bytes[offset+6] & 0x7F) << 7) | (bytes[offset+7] & 0x7F);
          } else {
            sz = (bytes[offset+4] << 24) | (bytes[offset+5] << 16) | (bytes[offset+6] << 8) | bytes[offset+7];
          }
          if (sz <= 0 || sz > 20 * 1024 * 1024) break;
          if (id == 'APIC') {
            final img = _parsePicFrame(bytes, offset + 10, sz, isV22: false);
            if (img != null) return img;
          }
          offset += 10 + sz;
        }
      }
    } catch (_) {}
    return null;
  }

  Uint8List? _parsePicFrame(Uint8List bytes, int start, int size, {required bool isV22}) {
    try {
      final end = start + size;
      if (end > bytes.length) return null;
      int i = start;
      if (i >= end) return null;
      final encoding = bytes[i++];
      if (isV22) {
        if (i + 3 > end) return null;
        i += 3;
      } else {
        while (i < end && bytes[i] != 0) { i++; }
        if (i >= end) return null;
        i++;
      }
      if (i >= end) return null;
      i++;
      if (encoding == 1 || encoding == 2) {
        while (i + 1 < end) {
          if (bytes[i] == 0 && bytes[i+1] == 0) { i += 2; break; }
          i += 2;
        }
      } else {
        while (i < end && bytes[i] != 0) { i++; }
        if (i < end) i++;
      }
      if (i >= end) return null;
      final imgBytes = Uint8List.fromList(bytes.sublist(i, end));
      if (imgBytes.length < 4) return null;
      final isJpeg = imgBytes[0] == 0xFF && imgBytes[1] == 0xD8;
      final isPng  = imgBytes[0] == 0x89 && imgBytes[1] == 0x50 && imgBytes[2] == 0x4E && imgBytes[3] == 0x47;
      if (!isJpeg && !isPng) return null;
      return imgBytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _extractDuration(Uint8List bytes) async {
    AudioPlayer? tempPlayer;
    File? tmpFile;
    try {
      tempPlayer = AudioPlayer();
      tmpFile = File('${Directory.systemTemp.path}/tmp_dur_${DateTime.now().millisecondsSinceEpoch}.$_audioExtension');
      await tmpFile.writeAsBytes(bytes);
      await tempPlayer.setSourceDeviceFile(tmpFile.path);
      await Future.delayed(const Duration(milliseconds: 1000));
      final dur = await tempPlayer.getDuration();
      if (dur != null && dur.inSeconds > 0 && mounted) {
        setState(() => _audioDuration = dur.inSeconds);
      }
    } catch (e) {
      debugPrint('Duration extraction failed: $e');
    } finally {
      await tempPlayer?.stop();
      await tempPlayer?.dispose();
      try { await tmpFile?.delete(); } catch (_) {}
    }
  }

  Future<void> _togglePlay() async {
    if (_audioBytes == null && _existingAudioUrl == null) return;
    try {
      if (_player == null) {
        _player = AudioPlayer();
        _player!.onPlayerComplete.listen((_) { if (mounted) setState(() => _playerPlaying = false); });
        _player!.onPlayerStateChanged.listen((s) { if (mounted) setState(() => _playerPlaying = s == PlayerState.playing); });
      }
      if (_playerPlaying) {
        await _player!.pause();
        if (mounted) setState(() => _playerPlaying = false);
      } else if (_audioBytes != null) {
        if (mounted) setState(() => _playerLoading = true);
        _currentTmpFile ??= File('${Directory.systemTemp.path}/preview_audio.$_audioExtension');
        await _currentTmpFile!.writeAsBytes(_audioBytes!);
        await _player!.play(DeviceFileSource(_currentTmpFile!.path));
        if (mounted) setState(() => _playerLoading = false);
      } else if (_existingAudioUrl != null) {
        if (mounted) setState(() => _playerLoading = true);
        await _player!.play(UrlSource(_existingAudioUrl!));
        if (mounted) setState(() => _playerLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Cannot preview this audio file.'; _playerLoading = false; });
    }
  }

  String _fmt(int s) {
    if (s <= 0) return '--:--';
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) { setState(() => _error = 'Please enter a song title.'); return; }
    if (_selectedArtist == null || _selectedArtist!.id.isEmpty) { setState(() => _error = 'Please select an artist.'); return; }
    if (!_isEdit && _audioBytes == null) { setState(() => _error = 'Please select an audio file.'); return; }
    if (_selectedGenre == SongGenre.other && _customGenreCtrl.text.trim().isEmpty) { setState(() => _error = 'Please enter a custom genre.'); return; }
    // Guard extra: verificar bytes no vacíos antes de subir
    if (_coverBytes != null && _coverBytes!.isEmpty) {
      setState(() => _error = 'Cover image is invalid. Please select again.');
      return;
    }
    if (_audioBytes != null && _audioBytes!.isEmpty) {
      setState(() => _error = 'Audio file is invalid. Please select again.');
      return;
    }

    await _player?.stop();
    setState(() { _uploading = true; _error = null; _progress = 0.0; });

    if (_isEdit) {
      // 1. Actualizar cover si se seleccionó uno nuevo
      if (_coverBytes != null && _coverBytes!.isNotEmpty) {
        final ce = await SongService.instance.updateCover(
          songId:      widget.existing!.id,
          oldCoverUrl: _existingCoverUrl ?? '',
          coverBytes:  _coverBytes!,
        );
        if (!mounted) return;
        if (ce != null) { setState(() { _uploading = false; _error = ce; }); return; }
      }

      // 2. Actualizar audio si se seleccionó uno nuevo
      if (_audioBytes != null && _audioBytes!.isNotEmpty) {
        final ae = await SongService.instance.updateAudio(
          songId: widget.existing!.id, audioUrl: _existingAudioUrl ?? '',
          audioBytes: _audioBytes!, audioExtension: _audioExtension, duration: _audioDuration,
        );
        if (!mounted) return;
        if (ae != null) { setState(() { _uploading = false; _error = ae; }); return; }
      }

      // 3. Actualizar metadata
      final err = await SongService.instance.updateMeta(
        songId: widget.existing!.id, title: _titleCtrl.text.trim(),
        artistId: _selectedArtist!.id, artistName: _selectedArtist!.name,
        featuring: _featuringCtrl.text.trim(), genre: _selectedGenre.value,
        customGenre: _customGenreCtrl.text.trim(), lyrics: _lyricsCtrl.text.trim(),
        isPaid: widget.albumIsPaid == true ? false : _isPaid,
        price: _isPaid ? _price : 0.0, albumIsPaidCheck: widget.albumId,
        releaseDate: _releaseDate,
        trackOrder:  _trackOrder,
      );
      if (!mounted) return;
      if (err != null) { setState(() { _uploading = false; _error = err; }); return; }
    } else {
      final err = await SongService.instance.uploadSong(
        title: _titleCtrl.text.trim(), artistId: _selectedArtist!.id,
        artistName: _selectedArtist!.name, featuring: _featuringCtrl.text.trim(),
        genre: _selectedGenre.value, customGenre: _customGenreCtrl.text.trim(),
        lyrics: _lyricsCtrl.text.trim(),
        coverBytes: _coverBytes ?? Uint8List(0),
        audioBytes: _audioBytes!, audioExtension: _audioExtension,
        isPaid: widget.albumIsPaid == true ? false : _isPaid,
        price: _isPaid ? _price : 0.0, duration: _audioDuration,
        type: widget.type, albumId: widget.albumId, albumTitle: widget.albumTitle,
        albumIsPaid: widget.albumIsPaid,
        releaseDate: _releaseDate,
        trackOrder:  _trackOrder,
        onProgress: (p) { if (mounted) setState(() => _progress = p); },
      );
      if (!mounted) return;
      if (err != null) { setState(() { _uploading = false; _error = err; }); return; }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isSingle = widget.type == SongType.single;
    final hasAudio = _audioBytes != null || (_isEdit && _existingAudioUrl != null);
    final hasCover = _coverBytes != null;
    final hasExistingCover = _isEdit && _existingCoverUrl != null && _existingCoverUrl!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary, size: 20),
          onPressed: _uploading ? null : () => Navigator.pop(context),
        ),
        title: Text(
          _isEdit ? 'Edit Song' : (isSingle ? 'Upload Single' : 'Add Track'),
          style: const TextStyle(color: AppColors.primary, fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: _uploading
          ? _UploadingOverlay(progress: _progress)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                if (!isSingle) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.album_rounded, color: AppColors.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Album: ${widget.albumTitle ?? ""}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                        if (widget.albumIsPaid == true)
                          const Text('Paid album — songs will be Free automatically', style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                      ])),
                    ]),
                  ),
                ],

                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: (!_isEdit && !hasAudio) ? null : _pickCover,
                    child: Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: hasCover
                              ? AppColors.primary.withValues(alpha: 0.7)
                              : hasExistingCover
                                  ? AppColors.primary.withValues(alpha: 0.5)
                                  : (!_isEdit && !hasAudio)
                                      ? AppColors.surfaceLight.withValues(alpha: 0.4)
                                      : AppColors.surfaceLight,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildCoverContent(hasCover, hasExistingCover, hasAudio),
                      ),
                    ),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: GestureDetector(
                    onTap: (_pickingAudio || _loadingAudio) ? null : _pickAudio,
                    child: Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _loadingAudio
                              ? AppColors.primary.withValues(alpha: 0.8)
                              : hasAudio
                                  ? AppColors.primary.withValues(alpha: 0.5)
                                  : AppColors.surfaceLight,
                          width: 2,
                        ),
                      ),
                      child: _loadingAudio
                          ? Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                              SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary)),
                              SizedBox(height: 8),
                              Text('Preparing...', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                            ])
                          : hasAudio
                              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  const Icon(Icons.audio_file_rounded, color: AppColors.primary, size: 28),
                                  const SizedBox(height: 4),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      _audioFileName ?? (_isEdit ? 'Current audio' : ''),
                                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 10),
                                      maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  _audioDuration > 0
                                      ? Text(_fmt(_audioDuration), style: const TextStyle(color: AppColors.primary, fontSize: 11))
                                      : const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                                ])
                              : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(Icons.upload_file_rounded, color: AppColors.textSecondary, size: 28),
                                  SizedBox(height: 6),
                                  Text('Audio\n.mp3 / .wav', style: TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center),
                                ]),
                    ),
                  )),
                ]),

                if (hasAudio) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      GestureDetector(
                        onTap: _playerLoading ? null : _togglePlay,
                        child: Container(
                          width: 40, height: 40,
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [AppColors.accent, AppColors.primary])),
                          child: Center(child: _playerLoading
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
                              : Icon(_playerPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: AppColors.background, size: 22)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_audioFileName ?? 'Preview audio', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(_playerPlaying ? 'Playing...' : 'Tap to preview', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ])),
                      Text(_fmt(_audioDuration), style: const TextStyle(color: AppColors.primary, fontSize: 12)),
                    ]),
                  ),
                ],

                const SizedBox(height: 24),
                _SectionLabel('Song Title'),
                const SizedBox(height: 8),
                _AdminField(controller: _titleCtrl, hint: 'e.g. On Top', icon: Icons.title_rounded),
                const SizedBox(height: 20),

                _SectionLabel('Artist'),
                const SizedBox(height: 8),
                _ArtistDropdown(
                  artists: _artists, selected: _selectedArtist,
                  onChanged: (a) => setState(() => _selectedArtist = a),
                  onAddNew: () async { await showDialog(context: context, builder: (_) => const _ArtistDialog()); _loadArtists(); },
                ),
                const SizedBox(height: 20),

                _SectionLabel('Featuring  (optional)'),
                const SizedBox(height: 8),
                _AdminField(controller: _featuringCtrl, hint: 'e.g. Lil Baby', icon: Icons.people_outline_rounded),
                const SizedBox(height: 20),

                _SectionLabel('Genre'),
                const SizedBox(height: 8),
                DropdownButtonFormField<SongGenre>(
                  initialValue: _selectedGenre,
                  dropdownColor: AppColors.surfaceLight,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    filled: true, fillColor: AppColors.surfaceLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.queue_music_rounded, color: AppColors.textSecondary, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                  items: SongGenre.values.map((g) => DropdownMenuItem(value: g, child: Text(g.label))).toList(),
                  onChanged: (g) => setState(() => _selectedGenre = g ?? SongGenre.autotuneRap),
                ),
                if (_selectedGenre == SongGenre.other) ...[
                  const SizedBox(height: 10),
                  _AdminField(controller: _customGenreCtrl, hint: 'Enter custom genre', icon: Icons.edit_rounded),
                ],
                const SizedBox(height: 20),
                _SectionLabel('Release Date  (optional)'),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickReleaseDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_rounded,
                          color: AppColors.textSecondary, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _releaseDate != null
                            ? '${_releaseDate!.day}/${_releaseDate!.month}/${_releaseDate!.year}'
                            : 'Select release date',
                        style: TextStyle(
                          color: _releaseDate != null
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      if (_releaseDate != null)
                        GestureDetector(
                          onTap: () => setState(() => _releaseDate = null),
                          child: const Icon(Icons.close_rounded,
                              color: AppColors.textSecondary, size: 16),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                if (widget.type == SongType.albumTrack) ...[
                  _SectionLabel('Track Order'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.format_list_numbered_rounded,
                          color: AppColors.textSecondary, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Position in album',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 14))),
                      IconButton(
                        icon: const Icon(Icons.remove_rounded,
                            color: AppColors.textSecondary, size: 20),
                        onPressed: () {
                          if (_trackOrder > 0) setState(() => _trackOrder--);
                        },
                      ),
                      Text(
                        '${_trackOrder + 1}',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_rounded,
                            color: AppColors.textSecondary, size: 20),
                        onPressed: () => setState(() => _trackOrder++),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ],

                _SectionLabel('Lyrics  (optional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _lyricsCtrl, maxLines: 8,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Paste lyrics here...',
                    hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    filled: true, fillColor: AppColors.surfaceLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 20),

                if (widget.albumIsPaid == true)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline_rounded, color: Colors.orangeAccent, size: 16),
                      SizedBox(width: 8),
                      Expanded(child: Text('This is a paid album — song is Free automatically.', style: TextStyle(color: Colors.orangeAccent, fontSize: 12))),
                    ]),
                  )
                else ...[
                  _SectionLabel('Access'),
                  const SizedBox(height: 8),
                  _ToggleRow(label: _isPaid ? 'Paid' : 'Free', value: _isPaid, onChanged: (v) => setState(() { _isPaid = v; if (!v) _price = 0.0; })),
                  if (_isPaid) ...[
                    const SizedBox(height: 10),
                    _SongPriceSelector(value: _price, onChanged: (v) => setState(() => _price = v)),
                  ],
                ],

                if (_error != null) ...[const SizedBox(height: 16), _ErrorText(_error!)],
                const SizedBox(height: 32),
                _GradientButton(
                  label: _isEdit ? 'Save Changes' : (isSingle ? 'Upload Single' : 'Add Track'),
                  fullWidth: true,
                  onTap: _save,
                ),
                const SizedBox(height: 24),
              ]),
            ),
    );
  }

  Widget _buildCoverContent(bool hasCover, bool hasExistingCover, bool hasAudio) {
    if (hasCover) {
      return Stack(fit: StackFit.expand, children: [
        Image.memory(_coverBytes!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _CoverErrorPlaceholder()),
        Positioned(bottom: 6, right: 6, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.edit_rounded, color: Colors.white, size: 10),
            SizedBox(width: 3),
            Text('Change', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
          ]),
        )),
      ]);
    }
    if (hasExistingCover) {
      return Stack(fit: StackFit.expand, children: [
        Image.network(_existingCoverUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _CoverErrorPlaceholder()),
        Positioned(bottom: 6, right: 6, child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
          child: const Icon(Icons.edit_rounded, color: AppColors.background, size: 12),
        )),
      ]);
    }
    if (!_isEdit && !hasAudio) {
      return Opacity(
        opacity: 0.4,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
          Icon(Icons.lock_outline_rounded, color: AppColors.textSecondary, size: 24),
          SizedBox(height: 6),
          Text('Select audio\nfirst', style: TextStyle(color: AppColors.textSecondary, fontSize: 10), textAlign: TextAlign.center),
        ]),
      );
    }
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
      Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary, size: 28),
      SizedBox(height: 6),
      Text('Add Cover\n(optional)', style: TextStyle(color: AppColors.textSecondary, fontSize: 10), textAlign: TextAlign.center),
    ]);
  }
}

class _CoverErrorPlaceholder extends StatelessWidget {
  const _CoverErrorPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surfaceLight,
    child: const Center(child: Icon(Icons.broken_image_rounded, color: AppColors.textSecondary, size: 32)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS & HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _UploadingOverlay extends StatelessWidget {
  const _UploadingOverlay({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      ShaderMask(
        shaderCallback: (b) => const LinearGradient(colors: [AppColors.accent, AppColors.primary]).createShader(b),
        child: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 64),
      ),
      const SizedBox(height: 24),
      const Text('Uploading...', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('${(progress * 100).toInt()}%', style: const TextStyle(color: AppColors.primary, fontSize: 14)),
      const SizedBox(height: 20),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: progress, minHeight: 8,
          backgroundColor: AppColors.surfaceLight,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
      const SizedBox(height: 12),
      const Text("Please don't close this screen", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    ]),
  ));
}

class _AlbumPriceSelector extends StatelessWidget {
  const _AlbumPriceSelector({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;
  static const _prices = [5.0, 10.0, 25.0, 50.0, 100.0];

  @override
  Widget build(BuildContext context) {
    final safe = _prices.contains(value) ? value : 5.0;
    return Row(children: [
      const Text('Price:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      const SizedBox(width: 12),
      Expanded(child: DropdownButtonFormField<double>(
        initialValue: safe,
        dropdownColor: AppColors.surfaceLight,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          filled: true, fillColor: AppColors.surfaceLight,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        items: _prices.map((p) => DropdownMenuItem(value: p, child: Text('\$${p.toStringAsFixed(0)}'))).toList(),
        onChanged: (v) => onChanged(v ?? 5.0),
      )),
    ]);
  }
}

class _SongPriceSelector extends StatelessWidget {
  const _SongPriceSelector({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;
  static const _prices = [2.0, 5.0];

  @override
  Widget build(BuildContext context) {
    final safe = _prices.contains(value) ? value : 2.0;
    return Row(children: [
      const Text('Price:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      const SizedBox(width: 12),
      Expanded(child: DropdownButtonFormField<double>(
        initialValue: safe,
        dropdownColor: AppColors.surfaceLight,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          filled: true, fillColor: AppColors.surfaceLight,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        items: _prices.map((p) => DropdownMenuItem(value: p, child: Text('\$${p.toStringAsFixed(0)}'))).toList(),
        onChanged: (v) => onChanged(v ?? 2.0),
      )),
    ]);
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.onTap, required this.loading});
  final Future<void> Function() onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Center(child: GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10)),
        child: loading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
            : const Text('Load more', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    )),
  );
}

class _ArtistDropdown extends StatelessWidget {
  const _ArtistDropdown({required this.artists, required this.selected, required this.onChanged, required this.onAddNew});
  final List<ArtistModel> artists;
  final ArtistModel? selected;
  final ValueChanged<ArtistModel?> onChanged;
  final VoidCallback onAddNew;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: InputDecorator(
      decoration: InputDecoration(
        filled: true, fillColor: AppColors.surfaceLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        prefixIcon: const Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(child: DropdownButton<ArtistModel>(
        value: artists.contains(selected) ? selected : null,
        hint: const Text('Select artist', style: TextStyle(color: AppColors.textSecondary)),
        dropdownColor: AppColors.surfaceLight,
        style: const TextStyle(color: AppColors.textPrimary),
        isExpanded: true,
        items: artists.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
        onChanged: onChanged,
      )),
    )),
    const SizedBox(width: 10),
    GestureDetector(
      onTap: onAddNew,
      child: Container(
        height: 50, width: 50,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.person_add_rounded, color: AppColors.background, size: 20),
      ),
    ),
  ]);
}

class _AdminField extends StatelessWidget {
  const _AdminField({required this.controller, required this.hint, required this.icon});
  final TextEditingController controller;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      filled: true, fillColor: AppColors.surfaceLight,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap, this.isLoading = false, this.fullWidth = false});
  final String label;
  final VoidCallback onTap;
  final bool isLoading, fullWidth;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: isLoading ? null : onTap,
    child: Container(
      width: fullWidth ? double.infinity : null, height: 46,
      padding: fullWidth ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Center(child: isLoading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
          : Text(label, style: const TextStyle(color: AppColors.background, fontWeight: FontWeight.w800, fontSize: 13))),
    ),
  );
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 46,
      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
      child: Center(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13))),
    ),
  );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14))),
      Switch(value: value, onChanged: onChanged, activeTrackColor: AppColors.primary, inactiveThumbColor: AppColors.textSecondary),
    ]),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5));
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.isPaid});
  final String label;
  final bool? isPaid;

  @override
  Widget build(BuildContext context) {
    Color bg = AppColors.surfaceLight, fg = AppColors.textSecondary;
    if (isPaid == true) { bg = AppColors.primary.withValues(alpha: 0.15); fg = AppColors.primary; }
    else if (isPaid == false) { bg = Colors.greenAccent.withValues(alpha: 0.12); fg = Colors.greenAccent; }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(icon, color: AppColors.surfaceLight, size: 56),
    const SizedBox(height: 16),
    Text(message, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14), textAlign: TextAlign.center),
  ]));
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
    const Icon(Icons.error_outline, color: Colors.redAccent, size: 14),
    const SizedBox(width: 6),
    Expanded(child: Text(text, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
  ]);
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.title, required this.message, required this.onConfirm});
  final String title, message;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 40),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(message, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: _OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(context))),
          const SizedBox(width: 12),
          Expanded(child: GestureDetector(
            onTap: () async { Navigator.pop(context); await onConfirm(); },
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
              ),
              child: const Center(child: Text('Confirm', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13))),
            ),
          )),
        ]),
      ],
    )),
  );
}

void _showSnack(BuildContext context, String msg, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: isError ? Colors.redAccent : AppColors.primary,
    behavior: SnackBarBehavior.floating,
  ));
}

void _showPermissionDenied(BuildContext context, String title, String message) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 48),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(ctx))),
            const SizedBox(width: 12),
            Expanded(child: _GradientButton(label: 'Open Settings', onTap: () { Navigator.pop(ctx); openAppSettings(); })),
          ]),
        ],
      )),
    ),
  );
}