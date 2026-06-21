import 'package:flutter/material.dart';

class LevelInput extends StatelessWidget {
  final String? selectedLevel;
  final ValueChanged<String?> onChanged;

  const LevelInput({
    super.key,
    required this.selectedLevel,
    required this.onChanged,
  });

  static const List<String> levels = [
    'TH3', 'TH4', 'TH5', 'TH6', 'TH7', 'TH8', 'TH9',
    'TH10', 'TH11', 'TH12', 'TH13', 'TH14', 'TH15', 'TH16', 'TH17', 'TH18',
    'BH4', 'BH5', 'BH6', 'BH7', 'BH8', 'BH9', 'BH10',
    'CH1', 'CH2', 'CH3', 'CH4', 'CH5', 'CH6', 'CH7', 'CH8', 'CH9', 'CH10',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose Base Level',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedLevel,
          isExpanded: true,
          dropdownColor: const Color(0xFF1F2937),
          decoration: InputDecoration(
            hintText: 'Required: TH18, BH10, CH10...',
            filled: true,
            fillColor: const Color(0xFF1F2937),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          items: levels.map((level) {
            return DropdownMenuItem(
              value: level,
              child: Text(level),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}