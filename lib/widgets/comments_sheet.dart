import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/app_theme.dart';
import '../../models/comment_model.dart';
import '../../services/comment_service.dart';
import '../../services/user_service.dart';

// ─── Función helper para abrir el sheet ──────────────────────────────────────
Future<void> showCommentsSheet(
  BuildContext context, {
  required String            parentId,
  required CommentParentType parentType,
  required bool              isPaid,      // si true → solo lectura, no puede comentar
}) {
  return showModalBottomSheet(
    context:          context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CommentsSheet(
      parentId:   parentId,
      parentType: parentType,
      isPaid:     isPaid,
    ),
  );
}

// ─── Botón de comentarios con contador ───────────────────────────────────────
class CommentCountButton extends StatefulWidget {
  const CommentCountButton({
    super.key,
    required this.parentId,
    required this.parentType,
    required this.isPaid,
    this.iconColor,
    this.size = 20,
  });

  final String            parentId;
  final CommentParentType parentType;
  final bool              isPaid;
  final Color?            iconColor;
  final double            size;

  @override
  State<CommentCountButton> createState() => _CommentCountButtonState();
}

class _CommentCountButtonState extends State<CommentCountButton> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final c = await CommentService.instance.countComments(widget.parentId);
    if (mounted) setState(() => _count = c);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await showCommentsSheet(
          context,
          parentId:   widget.parentId,
          parentType: widget.parentType,
          isPaid:     widget.isPaid,
        );
        // refrescar contador al cerrar
        _loadCount();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            color: widget.iconColor ?? AppColors.textSecondary,
            size:  widget.size,
          ),
          if (_count > 0) ...[
            const SizedBox(width: 4),
            Text(
              _count > 999 ? '999+' : '$_count',
              style: TextStyle(
                color:      widget.iconColor ?? AppColors.textSecondary,
                fontSize:   widget.size * 0.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── CommentsSheet ────────────────────────────────────────────────────────────
class CommentsSheet extends StatefulWidget {
  const CommentsSheet({
    super.key,
    required this.parentId,
    required this.parentType,
    required this.isPaid,
  });

  final String            parentId;
  final CommentParentType parentType;
  final bool              isPaid;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _textController  = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode       = FocusNode();

  List<CommentModel>  _comments   = [];
  DocumentSnapshot?   _lastDoc;
  bool                _loading    = true;
  bool                _loadingMore = false;
  bool                _hasMore    = true;
  bool                _submitting  = false;
  String?             _error;

  // Si el usuario ya tiene un comentario aquí → modo edición
  CommentModel?       _myComment;
  bool                _isEditing  = false;
  String?             _editingId;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  bool   get _isLoggedIn => _uid != null;
  bool   get _canComment => _isLoggedIn && !widget.isPaid;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ─── Carga inicial ───────────────────────────────────────────────────────
  Future<void> _loadInitial() async {
    setState(() { _loading = true; _error = null; });

    final (list, last) = await CommentService.instance.fetchComments(
      widget.parentId,
    );

    // Detectar si el usuario ya comentó
    if (_uid != null) {
      _myComment = await CommentService.instance.fetchMyComment(widget.parentId);
      if (_myComment != null) {
        // Poner su comentario al frente si no está ya
        final alreadyIn = list.any((c) => c.id == _myComment!.id);
        if (!alreadyIn) list.insert(0, _myComment!);
      }
    }

    if (!mounted) return;
    setState(() {
      _comments = list;
      _lastDoc  = last;
      _hasMore  = list.length >= CommentService.pageSize;
      _loading  = false;
    });
  }

  // ─── Scroll infinito ─────────────────────────────────────────────────────
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _loadingMore = true);

    final (list, last) = await CommentService.instance.fetchComments(
      widget.parentId,
      after: _lastDoc,
    );

    if (!mounted) return;
    setState(() {
      // Evitar duplicados
      final existingIds = _comments.map((c) => c.id).toSet();
      final newItems    = list.where((c) => !existingIds.contains(c.id)).toList();
      _comments.addAll(newItems);
      _lastDoc      = last ?? _lastDoc;
      _hasMore      = list.length >= CommentService.pageSize;
      _loadingMore  = false;
    });
  }

  // ─── Enviar / editar ─────────────────────────────────────────────────────
  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() { _submitting = true; _error = null; });
    _focusNode.unfocus();

    String? err;

    if (_isEditing && _editingId != null) {
      // Modo edición
      err = await CommentService.instance.editComment(
        commentId: _editingId!,
        newText:   text,
      );
      if (err == null) {
        setState(() {
          final idx = _comments.indexWhere((c) => c.id == _editingId);
          if (idx != -1) {
            _comments[idx] = _comments[idx].copyWith(
              text:     text,
              editedAt: DateTime.now(),
            );
          }
          _myComment  = _comments.firstWhere(
            (c) => c.userId == _uid,
            orElse: () => _comments[idx < 0 ? 0 : idx],
          );
          _isEditing  = false;
          _editingId  = null;
        });
        _textController.clear();
      }
    } else {
      // Nuevo comentario
      err = await CommentService.instance.addComment(
        parentId:   widget.parentId,
        parentType: widget.parentType,
        text:       text,
      );
      if (err == null) {
        _textController.clear();
        await _loadInitial(); // recarga para obtener el doc con ID real
      }
    }

    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (err != null) _error = err;
    });
  }

  // ─── Like ─────────────────────────────────────────────────────────────────
  Future<void> _toggleLike(int index) async {
    if (!_isLoggedIn) {
      _showLoginSnack();
      return;
    }
    final comment = _comments[index];
    final uid     = _uid!;
    final hasLiked = comment.likedBy.contains(uid);

    // Optimistic update
    final updated = CommentModel(
      id:          comment.id,
      parentId:    comment.parentId,
      parentType:  comment.parentType,
      userId:      comment.userId,
      userName:    comment.userName,
      userAvatar:  comment.userAvatar,
      text:        comment.text,
      createdAt:   comment.createdAt,
      editedAt:    comment.editedAt,
      likes:       hasLiked ? comment.likes - 1 : comment.likes + 1,
      likedBy:     hasLiked
          ? (List<String>.from(comment.likedBy)..remove(uid))
          : (List<String>.from(comment.likedBy)..add(uid)),
    );

    setState(() => _comments[index] = updated);
    await CommentService.instance.toggleLike(comment.id);
  }

  // ─── Eliminar ─────────────────────────────────────────────────────────────
  Future<void> _delete(CommentModel comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete comment',
            style: TextStyle(color: AppColors.textPrimary,
                fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to delete your comment?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final err = await CommentService.instance.deleteComment(comment.id);
    if (err == null && mounted) {
      setState(() {
        _comments.removeWhere((c) => c.id == comment.id);
        _myComment = null;
      });
    }
  }

  // ─── Iniciar edición ──────────────────────────────────────────────────────
  void _startEdit(CommentModel comment) {
    setState(() {
      _isEditing = true;
      _editingId = comment.id;
    });
    _textController.text = comment.text;
    _focusNode.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _editingId = null;
    });
    _textController.clear();
    _focusNode.unfocus();
  }

  void _showLoginSnack() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Sign in to interact with comments.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─── Tiempo relativo ──────────────────────────────────────────────────────
  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60)  return 'just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)    return '${diff.inHours}h ago';
    if (diff.inDays < 7)      return '${diff.inDays}d ago';
    if (diff.inDays < 30)     return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365)    return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenH     = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.80,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Handle ──────────────────────────────────────────────────────
          _Handle(),

          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Comments${_comments.isNotEmpty ? ' (${_comments.length})' : ''}',
                  style: const TextStyle(
                    color:      AppColors.textPrimary,
                    fontSize:   16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color:        AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary, size: 16),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.surfaceLight),

          // ── Lista ────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2))
                : _comments.isEmpty
                    ? _EmptyState(isPaid: widget.isPaid)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount: _comments.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == _comments.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                    strokeWidth: 2),
                              ),
                            );
                          }
                          final comment  = _comments[i];
                          final isOwner  = comment.userId == _uid;
                          final hasLiked = comment.likedBy.contains(_uid);

                          return _CommentTile(
                            comment:   comment,
                            isOwner:   isOwner,
                            hasLiked:  hasLiked,
                            timeAgo:   _timeAgo(comment.createdAt),
                            onLike:    () => _toggleLike(i),
                            onEdit:    isOwner ? () => _startEdit(comment) : null,
                            onDelete:  isOwner ? () => _delete(comment)   : null,
                          );
                        },
                      ),
          ),

          // ── Input area ───────────────────────────────────────────────────
          AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            padding:  EdgeInsets.only(bottom: bottomInset),
            child: _InputArea(
              controller:   _textController,
              focusNode:    _focusNode,
              canComment:   _canComment,
              isPaid:       widget.isPaid,
              isLoggedIn:   _isLoggedIn,
              isEditing:    _isEditing,
              submitting:   _submitting,
              error:        _error,
              hasMyComment: _myComment != null && !_isEditing,
              onSubmit:     _submit,
              onCancel:     _isEditing ? _cancelEdit : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Handle ───────────────────────────────────────────────────────────────────
class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin:     const EdgeInsets.only(top: 12, bottom: 8),
        width:      40, height: 4,
        decoration: BoxDecoration(
          color:        AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isPaid});
  final bool isPaid;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPaid
                  ? Icons.lock_outline_rounded
                  : Icons.chat_bubble_outline_rounded,
              color: AppColors.surfaceLight,
              size:  52,
            ),
            const SizedBox(height: 14),
            Text(
              isPaid ? 'Premium content' : 'No comments yet',
              style: const TextStyle(
                color:      AppColors.textPrimary,
                fontSize:   16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isPaid
                  ? 'Comments are available for free content only.'
                  : 'Be the first to leave a comment!',
              style: const TextStyle(
                color:    AppColors.textSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Comment Tile ─────────────────────────────────────────────────────────────
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.isOwner,
    required this.hasLiked,
    required this.timeAgo,
    required this.onLike,
    this.onEdit,
    this.onDelete,
  });

  final CommentModel  comment;
  final bool          isOwner;
  final bool          hasLiked;
  final String        timeAgo;
  final VoidCallback  onLike;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:  const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:  AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOwner
              ? AppColors.primary.withValues(alpha: 0.25)
              : AppColors.surfaceLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: avatar + nombre + tiempo + menú ──────────────────
          Row(
            children: [
              _Avatar(url: comment.userAvatar, initial: comment.userName),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            comment.userName,
                            style: TextStyle(
                              color:      isOwner
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontSize:   13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines:  1,
                            overflow:  TextOverflow.ellipsis,
                          ),
                        ),
                        if (isOwner) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color:        AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text('you',
                              style: TextStyle(
                                color:      AppColors.primary,
                                fontSize:   9,
                                fontWeight: FontWeight.w800,
                              )),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          timeAgo,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                        if (comment.isEdited) ...[
                          const SizedBox(width: 4),
                          const Text('· edited',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                  fontStyle: FontStyle.italic)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Menú dueño
              if (isOwner)
                _OwnerMenu(onEdit: onEdit, onDelete: onDelete),
            ],
          ),
          const SizedBox(height: 8),

          // ── Texto ────────────────────────────────────────────────────
          Text(
            comment.text,
            style: const TextStyle(
              color:   AppColors.textPrimary,
              fontSize: 14,
              height:   1.45,
            ),
          ),
          const SizedBox(height: 8),

          // ── Like ─────────────────────────────────────────────────────
          GestureDetector(
            onTap:     onLike,
            behavior:  HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    hasLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    key:   ValueKey(hasLiked),
                    color: hasLiked ? AppColors.primary : AppColors.textSecondary,
                    size:  16,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  comment.likes > 0 ? '${comment.likes}' : '',
                  style: TextStyle(
                    color:      hasLiked ? AppColors.primary : AppColors.textSecondary,
                    fontSize:   12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Avatar ───────────────────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.initial});
  final String url;
  final String initial;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.surfaceLight,
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      child: url.isEmpty
          ? Text(
              initial.isNotEmpty ? initial[0].toUpperCase() : '?',
              style: const TextStyle(
                color:      AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize:   14,
              ),
            )
          : null,
    );
  }
}

// ─── Owner Menu ───────────────────────────────────────────────────────────────
class _OwnerMenu extends StatelessWidget {
  const _OwnerMenu({this.onEdit, this.onDelete});
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == 'edit')   onEdit?.call();
        if (val == 'delete') onDelete?.call();
      },
      color:         AppColors.surface,
      elevation:     4,
      shape:         RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      icon: const Icon(Icons.more_horiz_rounded,
          color: AppColors.textSecondary, size: 18),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, color: AppColors.textPrimary, size: 16),
            SizedBox(width: 8),
            Text('Edit', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          ]),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
            SizedBox(width: 8),
            Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
          ]),
        ),
      ],
    );
  }
}

// ─── Input Area ───────────────────────────────────────────────────────────────
class _InputArea extends StatelessWidget {
  const _InputArea({
    required this.controller,
    required this.focusNode,
    required this.canComment,
    required this.isPaid,
    required this.isLoggedIn,
    required this.isEditing,
    required this.submitting,
    required this.hasMyComment,
    required this.onSubmit,
    this.error,
    this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode             focusNode;
  final bool                  canComment;
  final bool                  isPaid;
  final bool                  isLoggedIn;
  final bool                  isEditing;
  final bool                  submitting;
  final bool                  hasMyComment;
  final String?               error;
  final VoidCallback          onSubmit;
  final VoidCallback?         onCancel;

  @override
  Widget build(BuildContext context) {
    // ── Casos donde NO se puede comentar ──────────────────────────────
    if (isPaid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.surfaceLight)),
        ),
        child: Row(children: const [
          Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 14),
          SizedBox(width: 8),
          Text('Comments available for free content only.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ]),
      );
    }

    if (!isLoggedIn) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.surfaceLight)),
        ),
        child: Row(children: const [
          Icon(Icons.person_outline_rounded,
              color: AppColors.textSecondary, size: 14),
          SizedBox(width: 8),
          Text('Sign in to leave a comment.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ]),
      );
    }

    // Usuario ya comentó y no está editando → solo aviso
    if (hasMyComment) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.surfaceLight)),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: AppColors.primary, size: 14),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'You already commented. Tap ··· on your comment to edit it.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ]),
      );
    }

    // ── Input normal / edición ─────────────────────────────────────────
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceLight)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner modo edición
          if (isEditing)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined,
                      color: AppColors.primary, size: 13),
                  const SizedBox(width: 6),
                  const Text('Editing your comment',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: onCancel,
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Error
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(error!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 11)),
            ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar del usuario actual
              _Avatar(
                url:     UserService.instance.photoUrl,
                initial: UserService.instance.username,
              ),
              const SizedBox(width: 10),

              // Campo de texto
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  decoration: BoxDecoration(
                    color:        AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceLight),
                  ),
                  child: TextField(
                    controller:  controller,
                    focusNode:   focusNode,
                    maxLines:    null,
                    maxLength:   500,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText:       'Write a comment…',
                      hintStyle:      TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                      border:         InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      counterText:    '',
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted:     (_) => onSubmit(),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Botón enviar
              GestureDetector(
                onTap: submitting ? null : onSubmit,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: submitting
                        ? null
                        : const LinearGradient(
                            colors: [AppColors.accent, AppColors.primary]),
                    color: submitting ? AppColors.surfaceLight : null,
                  ),
                  child: Center(
                    child: submitting
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textSecondary))
                        : Icon(
                            isEditing
                                ? Icons.check_rounded
                                : Icons.send_rounded,
                            color: AppColors.background,
                            size:  18,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}