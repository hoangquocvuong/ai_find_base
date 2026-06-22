import 'package:flutter/material.dart';

class UsageCard extends StatelessWidget {
  final int freeSearchLeft;
  final VoidCallback onWatchAd;

  const UsageCard({
    super.key,
    required this.freeSearchLeft,
    required this.onWatchAd,
  });

  @override
  Widget build(BuildContext context) {
    final int progress = freeSearchLeft.clamp(0, 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                freeSearchLeft > 0
                    ? 'Free searches left: $freeSearchLeft'
                    : '⚠ No free searches left',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(
              width: 168,
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onWatchAd,
                child: const Text(
                  '▶ Watch Ad\n+2 Free',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: progress / 10,
            backgroundColor: const Color(0xFF374151),
            valueColor: const AlwaysStoppedAnimation<Color>(
              Color(0xFFFACC15),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Watch Ad = +2 free searches\n Premium = Unlimited',
          style: TextStyle(
            color: Color(0xFFD1D5DB),
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}