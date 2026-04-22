import 'package:flutter/material.dart';
import 'package:accident_app/shared/models/emergency_service.dart';

class FilterChipRow extends StatelessWidget {
  final Set<EmergencyServiceType> activeFilters;
  final ValueChanged<Set<EmergencyServiceType>> onChanged;

  const FilterChipRow({
    super.key,
    required this.activeFilters,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: EmergencyServiceType.values.map((type) {
          final selected = activeFilters.contains(type);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(type.label),
              selected: selected,
              onSelected: (val) {
                final updated = Set<EmergencyServiceType>.from(activeFilters);
                if (val) {
                  updated.add(type);
                } else {
                  updated.remove(type);
                }
                onChanged(updated);
              },
              avatar: Icon(
                _iconForType(type),
                size: 16,
                color: selected ? Colors.white : _colorForType(type),
              ),
              selectedColor: _colorForType(type),
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: selected ? Colors.white : null,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              backgroundColor: Colors.white.withValues(alpha: 0.9),
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _iconForType(EmergencyServiceType type) => switch (type) {
    EmergencyServiceType.hospital    => Icons.local_hospital,
    EmergencyServiceType.police      => Icons.local_police,
    EmergencyServiceType.fireStation => Icons.local_fire_department,
  };

  Color _colorForType(EmergencyServiceType type) => switch (type) {
    EmergencyServiceType.hospital    => const Color(0xFFD32F2F),
    EmergencyServiceType.police      => const Color(0xFF1565C0),
    EmergencyServiceType.fireStation => const Color(0xFFE65100),
  };
}
