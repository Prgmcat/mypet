import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/session.dart';

class PetAvatar extends ConsumerWidget {
  const PetAvatar({super.key, required this.pet, this.radius = 30});

  final Pet pet;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emoji = pet.species == 'cat'
        ? '🐱'
        : pet.species == 'dog'
            ? '🐶'
            : '🐾';
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFF1E4D8),
      child: Text(
        emoji,
        style: TextStyle(fontSize: radius * 0.93),
      ),
    );
    if (pet.avatarPath.isEmpty) return fallback;
    final api = ref.read(apiClientProvider);
    return ClipOval(
      child: Image.network(
        api.avatarUrl(pet.id, pet.version),
        headers: api.authHeaders,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}
