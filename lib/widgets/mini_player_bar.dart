import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/player_service.dart';
import '../screens/music/full_player_screen.dart';

class MiniPlayerBar extends StatefulWidget {
  const MiniPlayerBar({super.key});

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic),
    );

    PlayerService.instance.addListener(_onPlayerChanged);
    if (PlayerService.instance.hasTrack) _slideCtrl.forward();
  }

  void _onPlayerChanged() {
    if (!mounted) return;
    setState(() {});
    if (PlayerService.instance.hasTrack) {
      _slideCtrl.forward();
    } else {
      _slideCtrl.reverse();
    }
  }

  @override
  void dispose() {
    PlayerService.instance.removeListener(_onPlayerChanged);
    _slideCtrl.dispose();
    super.dispose();
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
    final player = PlayerService.instance;
    if (!player.hasTrack) return const SizedBox.shrink();
    final song = player.currentSong!;

    return SlideTransition(
      position: _slideAnim,
      child: GestureDetector(
        onTap: _openPlayer,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          height: 66,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 22,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(
                      value: player.progress,
                      minHeight: 2,
                      backgroundColor: AppColors.surfaceLight,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: song.coverUrl.isNotEmpty
                            ? Image.network(
                                song.coverUrl,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _CoverFall(),
                              )
                            : _CoverFall(),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              song.featuring.isNotEmpty
                                  ? '${song.artistName} ft. ${song.featuring}'
                                  : song.artistName,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _MiniBtn(
                        icon: Icons.skip_previous_rounded,
                        enabled: player.hasPrevious,
                        onTap: () => player.skipPrevious(),
                      ),
                      const SizedBox(width: 2),
                      GestureDetector(
                        onTap: player.togglePlay,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [AppColors.accent, AppColors.primary],
                            ),
                          ),
                          child: player.isLoading
                              ? const Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.background,
                                    ),
                                  ),
                                )
                              : Icon(
                                  player.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: AppColors.background,
                                  size: 20,
                                ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      _MiniBtn(
                        icon: Icons.skip_next_rounded,
                        enabled: player.hasNext,
                        onTap: () => player.skipNext(),
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

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({required this.icon, required this.onTap, required this.enabled});
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? AppColors.textPrimary : AppColors.surfaceLight,
        ),
      ),
    );
  }
}

class _CoverFall extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    color: AppColors.surfaceLight,
    child: const Icon(Icons.music_note_rounded, color: AppColors.textSecondary, size: 20),
  );
}