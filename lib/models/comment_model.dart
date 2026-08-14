import 'package:cloud_firestore/cloud_firestore.dart';

enum CommentParentType { album, song }

class CommentModel {
  final String   id;
  final String   parentId;
  final CommentParentType parentType;
  final String   userId;
  final String   userName;
  final String   userAvatar;  // URL o ''
  final String   text;
  final DateTime createdAt;
  final DateTime? editedAt;
  final int      likes;
  final List<String> likedBy; // lista de userIds

  const CommentModel({
    required this.id,
    required this.parentId,
    required this.parentType,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.text,
    required this.createdAt,
    this.editedAt,
    required this.likes,
    required this.likedBy,
  });

  bool get isEdited => editedAt != null;

  factory CommentModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final likedByRaw = data['likedBy'];
    return CommentModel(
      id:          doc.id,
      parentId:    data['parentId']   ?? '',
      parentType:  (data['parentType'] ?? 'song') == 'album'
                       ? CommentParentType.album
                       : CommentParentType.song,
      userId:      data['userId']     ?? '',
      userName:    data['userName']   ?? '',
      userAvatar:  data['userAvatar'] ?? '',
      text:        data['text']       ?? '',
      createdAt:   (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      editedAt:    (data['editedAt']  as Timestamp?)?.toDate(),
      likes:       (data['likes']     ?? 0) as int,
      likedBy:     likedByRaw is List
                       ? likedByRaw.map((e) => e.toString()).toList()
                       : [],
    );
  }

  Map<String, dynamic> toMap() => {
    'parentId':    parentId,
    'parentType':  parentType == CommentParentType.album ? 'album' : 'song',
    'userId':      userId,
    'userName':    userName,
    'userAvatar':  userAvatar,
    'text':        text,
    'createdAt':   FieldValue.serverTimestamp(),
    'editedAt':    null,
    'likes':       0,
    'likedBy':     [],
  };

  CommentModel copyWith({String? text, DateTime? editedAt}) => CommentModel(
    id:          id,
    parentId:    parentId,
    parentType:  parentType,
    userId:      userId,
    userName:    userName,
    userAvatar:  userAvatar,
    text:        text       ?? this.text,
    createdAt:   createdAt,
    editedAt:    editedAt   ?? this.editedAt,
    likes:       likes,
    likedBy:     likedBy,
  );
}