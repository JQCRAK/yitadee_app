import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import '../models/song_model.dart';
import 'song_service.dart';
import 'purchase_service.dart';

enum PlayerRepeatMode { none, one, all }

class PlayerService extends ChangeNotifier {
  PlayerService._() { _init(); }
  static final PlayerService instance = PlayerService._();

  final AudioPlayer _player = AudioPlayer();

  // ── Única fuente de verdad: el orden SIEMPRE viene de just_audio ───────────
  List<SongModel>  _masterQueue  = []; // orden original, nunca cambia
  List<SongModel>  _displayQueue = []; // orden que ve la UI (puede ser shuffled)
  SongModel?       _currentSong;
  int              _queueIndex   = 0;

  bool             _isPlaying    = false;
  bool             _isLoading    = false;
  Duration         _position     = Duration.zero;
  Duration         _duration     = Duration.zero;
  PlayerRepeatMode _repeatMode   = PlayerRepeatMode.none;
  bool             _shuffle      = false;
  bool             _disposed     = false;

  // ── Control para no contar el mismo play dos veces por canción ─────────────
  String?          _lastCountedSongId;

  // ── Getters ────────────────────────────────────────────────────────────────
  SongModel?       get currentSong  => _currentSong;
  List<SongModel>  get queue        => _displayQueue;
  int              get queueIndex   => _queueIndex;
  bool             get isPlaying    => _isPlaying;
  bool             get isLoading    => _isLoading;
  bool             get hasTrack     => _currentSong != null;
  Duration         get position     => _position;
  Duration         get duration     => _duration;
  PlayerRepeatMode get repeatMode   => _repeatMode;
  bool             get shuffle      => _shuffle;
  bool             get hasPrevious  => _queueIndex > 0;
  bool             get hasNext      => _queueIndex < _displayQueue.length - 1;

  double get progress {
    if (_duration.inMilliseconds == 0) return 0.0;
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
  }

  // ── Helper: una canción está bloqueada si es paid Y NO está en el locker ───
  bool _isLocked(SongModel song) {
    if (!song.isPaid) return false;
    return !PurchaseService.instance.isUnlocked(song.id);
  }

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Estado play/pause/loading
    _player.playerStateStream.listen((state) {
      if (_disposed) return;

      final wasPlaying = _isPlaying;
      _isPlaying = state.playing;
      _isLoading = state.processingState == ProcessingState.loading ||
                   state.processingState == ProcessingState.buffering;

      // Registrar play solo cuando pasa de no-playing → playing y está listo
      if (!wasPlaying &&
          _isPlaying &&
          state.processingState == ProcessingState.ready &&
          _currentSong != null &&
          _currentSong!.id != _lastCountedSongId) {
        _lastCountedSongId = _currentSong!.id;
        SongService.instance.incrementPlays(_currentSong!.id);
      }

      _notify();
    });

    // Posición
    _player.positionStream.listen((pos) {
      if (_disposed) return;
      _position = pos;
      _notify();
    });

    // Duración
    _player.durationStream.listen((dur) {
      if (_disposed) return;
      _duration = dur ?? Duration.zero;
      _notify();
    });

    // just_audio avanzó de canción automáticamente
    _player.currentIndexStream.listen((index) {
      if (_disposed || index == null) return;
      _syncCurrentFromPlayerIndex(index);
    });

    // just_audio generó nuevo orden de shuffle
    _player.shuffleIndicesStream.listen((indices) {
      if (_disposed || indices == null || indices.isEmpty) return;
      if (!_shuffle) return;
      if (indices.length != _masterQueue.length) return;

      _displayQueue = indices.map((i) => _masterQueue[i]).toList();

      if (_currentSong != null) {
        final newIdx = _displayQueue.indexWhere((s) => s.id == _currentSong!.id);
        if (newIdx >= 0) _queueIndex = newIdx;
      }
      _notify();
    });
  }

  // ── Sincroniza _currentSong y _queueIndex desde el índice real de just_audio
  void _syncCurrentFromPlayerIndex(int playerIndex) {
    if (playerIndex >= _masterQueue.length) return;

    final song = _masterQueue[playerIndex];

    if (_currentSong?.id != song.id) {
      _lastCountedSongId = null;
    }

    final displayIdx = _displayQueue.indexWhere((s) => s.id == song.id);
    if (displayIdx >= 0) {
      _queueIndex  = displayIdx;
      _currentSong = song;
      _position    = Duration.zero;
      _notify();
    }
  }

  // ── playSong — CORREGIDO: permite canciones paid si están desbloqueadas ────
  Future<void> playSong(SongModel song, {List<SongModel>? queue, int? index}) async {
    // Bloquear solo si está locked (paid Y no comprada)
    if (_isLocked(song)) return;

    // Al iniciar una canción nueva, resetear control de plays
    _lastCountedSongId = null;

    // Filtrar la queue: solo canciones reproducibles (free O desbloqueadas)
    final playableQueue = (queue ?? [song])
        .where((s) => !_isLocked(s))
        .toList();

    // Si la queue quedó vacía por algún motivo, usar solo la canción actual
    if (playableQueue.isEmpty) return;

    _masterQueue  = List.from(playableQueue);
    _displayQueue = List.from(_masterQueue);

    // Encontrar el índice correcto en la queue filtrada
    final targetIndex = index != null
        ? playableQueue.indexWhere((s) => s.id == song.id)
        : playableQueue.indexWhere((s) => s.id == song.id);
    final startIndex = targetIndex < 0 ? 0 : targetIndex;

    _currentSong = _masterQueue[startIndex];
    _queueIndex  = startIndex;
    _isLoading   = true;
    _isPlaying   = false;
    _position    = Duration.zero;
    _duration    = Duration.zero;
    _notify();

    try {
      final playlist = ConcatenatingAudioSource(
        children: _masterQueue.map((s) => AudioSource.uri(
          Uri.parse(s.audioUrl),
          tag: MediaItem(
            id:     s.id,
            title:  s.title,
            artist: s.artistName,
            album:  'YITADEE',
            artUri: s.coverUrl.isNotEmpty ? Uri.parse(s.coverUrl) : null,
          ),
        )).toList(),
      );

      await _player.setAudioSource(playlist, initialIndex: startIndex);
      await _applyLoopMode();

      if (_shuffle) {
        await _player.setShuffleModeEnabled(true);
        await _player.shuffle();
      } else {
        await _player.setShuffleModeEnabled(false);
      }

      await _player.play();
    } catch (e) {
      _isLoading = false;
      _notify();
    }
  }

  // ── Navegar a un índice de _displayQueue ───────────────────────────────────
  Future<void> _seekToDisplayIndex(int displayIdx) async {
    if (displayIdx < 0 || displayIdx >= _displayQueue.length) return;

    final song = _displayQueue[displayIdx];
    final masterIdx = _masterQueue.indexWhere((s) => s.id == song.id);
    if (masterIdx < 0) return;

    _lastCountedSongId = null;

    _currentSong = song;
    _queueIndex  = displayIdx;
    _isLoading   = true;
    _isPlaying   = false;
    _position    = Duration.zero;
    _notify();

    try {
      await _player.seek(Duration.zero, index: masterIdx);
      await _player.play();
    } catch (e) {
      _isLoading = false;
      _notify();
    }
  }

  // ── Controles ──────────────────────────────────────────────────────────────
  Future<void> togglePlay() async {
    if (_currentSong == null) return;
    _isPlaying ? await _player.pause() : await _player.play();
  }

  Future<void> skipNext() async {
    if (!hasNext) {
      if (_repeatMode == PlayerRepeatMode.all) {
        await _seekToDisplayIndex(0);
      }
      return;
    }
    await _seekToDisplayIndex(_queueIndex + 1);
  }

  Future<void> skipPrevious() async {
    if (_position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    if (!hasPrevious) return;
    await _seekToDisplayIndex(_queueIndex - 1);
  }

  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
    _position = position;
    _notify();
  }

  Future<void> stop() async {
    await _player.stop();
    _currentSong       = null;
    _isPlaying         = false;
    _isLoading         = false;
    _position          = Duration.zero;
    _duration          = Duration.zero;
    _masterQueue       = [];
    _displayQueue      = [];
    _queueIndex        = 0;
    _lastCountedSongId = null;
    _notify();
  }

  // ── Repeat ─────────────────────────────────────────────────────────────────
  Future<void> toggleRepeat() async {
    switch (_repeatMode) {
      case PlayerRepeatMode.none: _repeatMode = PlayerRepeatMode.all;  break;
      case PlayerRepeatMode.all:  _repeatMode = PlayerRepeatMode.one;  break;
      case PlayerRepeatMode.one:  _repeatMode = PlayerRepeatMode.none; break;
    }
    await _applyLoopMode();
    _notify();
  }

  Future<void> _applyLoopMode() async {
    switch (_repeatMode) {
      case PlayerRepeatMode.none: await _player.setLoopMode(LoopMode.off); break;
      case PlayerRepeatMode.one:  await _player.setLoopMode(LoopMode.one); break;
      case PlayerRepeatMode.all:  await _player.setLoopMode(LoopMode.all); break;
    }
  }

  // ── Shuffle ────────────────────────────────────────────────────────────────
  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;

    if (_shuffle) {
      await _player.setShuffleModeEnabled(true);
      await _player.shuffle();
    } else {
      await _player.setShuffleModeEnabled(false);
      _displayQueue = List.from(_masterQueue);
      if (_currentSong != null) {
        final idx = _displayQueue.indexWhere((s) => s.id == _currentSong!.id);
        _queueIndex = idx >= 0 ? idx : 0;
      }
    }
    _notify();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _notify() { if (!_disposed) notifyListeners(); }

  @override
  void dispose() {
    _disposed = true;
    _player.dispose();
    super.dispose();
  }
}