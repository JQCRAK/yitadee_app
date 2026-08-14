import 'dart:io';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/user_service.dart';

class UserAvatar extends StatelessWidget {
  final double radius;
  const UserAvatar({super.key, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: UserService.instance.photoNotifier,
      builder: (context, photoPath, _) {
        final svc = UserService.instance;

        ImageProvider? imageProvider;
        if (photoPath.isNotEmpty) {
          imageProvider = photoPath.startsWith('http')
              ? NetworkImage(photoPath)
              : FileImage(File(photoPath)) as ImageProvider;
        }

        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color:  AppColors.primary,
              width:  radius > 30 ? 2.5 : 1.5,
            ),
          ),
          child: CircleAvatar(
            radius:          radius,
            backgroundColor: AppColors.surface,
            backgroundImage: imageProvider,
            child: imageProvider == null
                ? Text(
                    svc.initial,
                    style: TextStyle(
                      color:      AppColors.primary,
                      fontSize:   radius * 0.75,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}