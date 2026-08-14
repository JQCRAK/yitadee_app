import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/comment_model.dart';
import 'user_service.dart';

class CommentService {
  CommentService._();
  static final CommentService instance = CommentService._();

  final _col = FirebaseFirestore.instance.collection('comments');

  // ─── Constantes ──────────────────────────────────────────────────────────
  static const int pageSize = 20;

  // ─── Helpers internos ────────────────────────────────────────────────────

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  /// Retorna el comentario existente del usuario actual para un parentId, o null.
  Future<CommentModel?> fetchMyComment(String parentId) async {
    final uid = _currentUid;
    if (uid == null) return null;

    final snap = await _col
        .where('parentId', isEqualTo: parentId)
        .where('userId',   isEqualTo: uid)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return CommentModel.fromDoc(snap.docs.first);
  }

  // ─── Contar comentarios de un parentId ───────────────────────────────────
  Future<int> countComments(String parentId) async {
    final snap = await _col
        .where('parentId', isEqualTo: parentId)
        .count()
        .get();
    return snap.count ?? 0;
  }

  // ─── Cargar página de comentarios ────────────────────────────────────────
  /// Devuelve (lista, último DocumentSnapshot para paginar).
  /// Pasar [after] para siguiente página.
  Future<(List<CommentModel>, DocumentSnapshot?)> fetchComments(
    String parentId, {
    DocumentSnapshot? after,
  }) async {
    Query q = _col
        .where('parentId', isEqualTo: parentId)
        .orderBy('createdAt', descending: true)
        .limit(pageSize);

    if (after != null) q = q.startAfterDocument(after);

    final snap = await q.get();
    final docs = snap.docs;
    final last = docs.isNotEmpty ? docs.last : null;
    return (docs.map(CommentModel.fromDoc).toList(), last);
  }

  // ─── Agregar comentario ───────────────────────────────────────────────────
  /// Retorna null si OK, String con error si falla.
  /// Reglas:
  ///   - El usuario solo puede tener 1 comentario por parentId.
  ///   - No se puede comentar en contenido isPaid (validación en UI,
  ///     pero también aquí como segunda línea de defensa no aplica
  ///     porque el service no conoce isPaid — la UI lo controla).
  Future<String?> addComment({
    required String           parentId,
    required CommentParentType parentType,
    required String           text,
  }) async {
    final uid = _currentUid;
    if (uid == null) return 'You must be logged in to comment.';

    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'Comment cannot be empty.';
    if (trimmed.length > 500) return 'Comment is too long (max 500 characters).';

    // Verificar que no tenga ya un comentario en este parent
    final existing = await fetchMyComment(parentId);
    if (existing != null) {
      return 'You already commented here. You can edit your comment instead.';
    }

    final userService = UserService.instance;
    final userName   = userService.username.isNotEmpty
        ? userService.username
        : (FirebaseAuth.instance.currentUser?.displayName ?? 'User');
    final userAvatar = userService.photoUrl;

    await _col.add({
      'parentId':   parentId,
      'parentType': parentType == CommentParentType.album ? 'album' : 'song',
      'userId':     uid,
      'userName':   userName,
      'userAvatar': userAvatar,
      'text':       trimmed,
      'createdAt':  FieldValue.serverTimestamp(),
      'editedAt':   null,
      'likes':      0,
      'likedBy':    [],
    });

    return null;
  }

  // ─── Editar comentario ────────────────────────────────────────────────────
  /// Solo el dueño puede editar. Retorna null si OK.
  Future<String?> editComment({
    required String commentId,
    required String newText,
  }) async {
    final uid = _currentUid;
    if (uid == null) return 'Not logged in.';

    final trimmed = newText.trim();
    if (trimmed.isEmpty) return 'Comment cannot be empty.';
    if (trimmed.length > 500) return 'Comment is too long (max 500 characters).';

    // Verificar propiedad
    final doc = await _col.doc(commentId).get();
    if (!doc.exists) return 'Comment not found.';
    final data = doc.data() as Map<String, dynamic>;
    if (data['userId'] != uid) return 'You can only edit your own comments.';

    await _col.doc(commentId).update({
      'text':      trimmed,
      'editedAt':  FieldValue.serverTimestamp(),
    });

    return null;
  }

  // ─── Eliminar comentario ──────────────────────────────────────────────────
  /// Solo el dueño puede eliminar. Retorna null si OK.
  Future<String?> deleteComment(String commentId) async {
    final uid = _currentUid;
    if (uid == null) return 'Not logged in.';

    final doc = await _col.doc(commentId).get();
    if (!doc.exists) return 'Comment not found.';
    final data = doc.data() as Map<String, dynamic>;
    if (data['userId'] != uid) return 'You can only delete your own comments.';

    await _col.doc(commentId).delete();
    return null;
  }

  // ─── Toggle Like ──────────────────────────────────────────────────────────
  /// Agrega o quita el like del usuario actual. Retorna null si OK.
  Future<String?> toggleLike(String commentId) async {
    final uid = _currentUid;
    if (uid == null) return 'Not logged in.';

    final ref = _col.doc(commentId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data     = snap.data() as Map<String, dynamic>;
      final likedBy  = List<String>.from((data['likedBy'] as List?) ?? []);
      final hasLiked = likedBy.contains(uid);

      if (hasLiked) {
        likedBy.remove(uid);
      } else {
        likedBy.add(uid);
      }

      tx.update(ref, {
        'likedBy': likedBy,
        'likes':   likedBy.length,
      });
    });

    return null;
  }
}