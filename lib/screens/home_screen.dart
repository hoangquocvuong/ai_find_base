import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/base_result.dart';
import '../widgets/action_buttons.dart';
import '../widgets/app_header.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/image_picker_box.dart';
import '../widgets/search_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker picker = ImagePicker();

  File? selectedImage;
  String? selectedLevel;

  int totalBases = 2633;
  int freeSearchLeft = 0;
  int totalSearchCount = 0;

  bool loading = false;
  bool isSubscriber = false;

  List<BaseResult> results = [];
  List<BaseResult> savedBases = [];

  BannerAd? bannerAd;
  bool bannerReady = false;

  static const String iosBannerAdUnitId =
      'ca-app-pub-9371341402256787/4621781605';

  @override
  void initState() {
    super.initState();
    initializeApp();
    loadBannerAd();
  }

  Future<void> initializeApp() async {
    final prefs = await SharedPreferences.getInstance();

    totalSearchCount = prefs.getInt('total_search_count') ?? 0;
    freeSearchLeft = prefs.getInt('free_search_left') ?? 0;
    isSubscriber = prefs.getBool('is_subscriber') ?? false;

    await loadSavedBases(prefs);
    await loadTotalBases();

    final welcomeShown = prefs.getBool('welcome_bonus_shown') ?? false;

    if (!welcomeShown) {
      freeSearchLeft += 5;

      await prefs.setBool('welcome_bonus_shown', true);
      await prefs.setInt('free_search_left', freeSearchLeft);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        showDialog(
          context: context,
          builder: (_) {
            return AlertDialog(
              title: const Text('🎉 Welcome to AI Find Base'),
              content: const Text(
                'Congratulations!\n\n'
                    'You received 5 FREE AI searches without ads.\n\n'
                    'Find similar Clash of Clans bases instantly.\n\n'
                    'Have a great day!',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Let’s Go 🚀'),
                ),
              ],
            );
          },
        );
      });
    }

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastBonus = prefs.getString('daily_bonus_day') ?? '';

    if (lastBonus != today) {
      freeSearchLeft += 2;

      await prefs.setString('daily_bonus_day', today);
      await prefs.setInt('free_search_left', freeSearchLeft);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> loadTotalBases() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.cocbasepro.com/ai/'),
      );

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      totalBases = data['total'] ?? totalBases;
    } catch (_) {}
  }

  Future<void> saveUsage() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('free_search_left', freeSearchLeft);
    await prefs.setInt('total_search_count', totalSearchCount);
  }

  Future<void> pickImage() async {
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );

    if (file == null) return;

    setState(() {
      selectedImage = File(file.path);
      results.clear();
    });
  }

  void resetAll() {
    setState(() {
      selectedImage = null;
      selectedLevel = null;
      results.clear();
      loading = false;
    });
  }

  Future<void> handleSearchLogic() async {
    if (isSubscriber) {
      await searchSimilarBases();
      return;
    }

    totalSearchCount++;

    if (freeSearchLeft > 0) {
      freeSearchLeft--;
      await saveUsage();

      if (mounted) {
        setState(() {});
      }

      await searchSimilarBases();
      return;
    }

    await saveUsage();

    if (totalSearchCount >= 11) {
      await maybeShowPremiumPopup();
    }

    if (totalSearchCount % 2 == 0) {
      showRewardAdMock();
    } else {
      await searchSimilarBases();
    }
  }

  void watchAdMock() {
    showRewardAdMock();
  }

  void showRewardAdMock() {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('▶ Watch Ad'),
          content: const Text(
            'Rewarded Ad will be connected later.\n\n'
                'For now, this simulates a successful ad reward.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await rewardSuccess();
              },
              child: const Text('Simulate Reward'),
            ),
          ],
        );
      },
    );
  }

  Future<void> rewardSuccess() async {
    freeSearchLeft += 2;

    await saveUsage();

    if (!mounted) return;

    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎉 You received +2 free searches without ads'),
      ),
    );
  }

  Future<void> maybeShowPremiumPopup() async {
    final prefs = await SharedPreferences.getInstance();

    final count = prefs.getInt('premium_popup_count') ?? 0;
    final lastTime = prefs.getInt('premium_popup_time') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const twoDays = 2 * 24 * 60 * 60 * 1000;

    if (count >= 3) return;
    if (now - lastTime < twoDays) return;

    await prefs.setInt('premium_popup_count', count + 1);
    await prefs.setInt('premium_popup_time', now);

    if (!mounted) return;

    showPremiumPopup();
  }

  void showPremiumPopup() {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('👑 AI Find Base Premium'),
          content: const Text(
            'Unlock unlimited AI searches.\n\n'
                '✓ Unlimited AI searches\n'
                '✓ No ads\n'
                '✓ Faster experience',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Maybe later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Premium purchase will be connected later'),
                  ),
                );
              },
              child: const Text('Upgrade'),
            ),
          ],
        );
      },
    );
  }

  Future<void> searchSimilarBases() async {
    if (selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an image first')),
      );
      return;
    }

    if (selectedLevel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose TH/BH/CH level for best accuracy'),
        ),
      );
      return;
    }

    setState(() {
      loading = true;
      results.clear();
    });

    try {
      final uri = Uri.parse(
        'https://api.cocbasepro.com/ai/search',
      ).replace(
        queryParameters: {
          'level': selectedLevel!,
        },
      );

      final request = http.MultipartRequest('POST', uri);

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          selectedImage!.path,
        ),
      );

      final streamedResponse = await request.send();
      final body = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode != 200) {
        throw Exception('Server error ${streamedResponse.statusCode}');
      }

      final data = jsonDecode(body);
      final list = data['results'] as List<dynamic>? ?? [];

      results = list
          .map(
            (item) => BaseResult.fromJson(
          item as Map<String, dynamic>,
        ),
      )
          .toList();

      if (results.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No similar base found')),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI Finder error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> openBase(BaseResult item) async {
    final link = item.accessLink.isNotEmpty ? item.accessLink : item.postUrl;

    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Base link not available')),
      );
      return;
    }

    final uri = Uri.parse(link);

    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> saveBase(BaseResult item) async {
    final exists = savedBases.any(
          (base) => base.postUrl == item.postUrl,
    );

    if (!exists) {
      savedBases.add(item);

      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        'saved_bases',
        jsonEncode(
          savedBases.map((base) => base.toJson()).toList(),
        ),
      );
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Base saved')),
    );
  }

  Future<void> loadSavedBases(SharedPreferences prefs) async {
    final raw = prefs.getString('saved_bases');

    if (raw == null || raw.isEmpty) return;

    final list = jsonDecode(raw) as List<dynamic>;

    savedBases = list
        .map(
          (item) => BaseResult.fromJson(
        item as Map<String, dynamic>,
      ),
    )
        .toList();
  }

  Widget buildResultCard(BaseResult item) {
    final percent =
    item.score <= 1 ? (item.score * 100).round() : item.score.round();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader(totalBases: totalBases),

          const SizedBox(height: 18),

          buildStatsPanel(),

          const SizedBox(height: 12),

          buildAdBanner(),

          const SizedBox(height: 12),

          buildFeatureBanner(),

          const SizedBox(height: 16),

          ImagePickerBox(image: selectedImage),

          const SizedBox(height: 12),

          ActionButtons(
            onChoose: pickImage,
            onReset: resetAll,
          ),

          const SizedBox(height: 16),

          buildLevelSelector(),

          const SizedBox(height: 16),

          SearchButton(
            loading: loading,
            onPressed: handleSearchLogic,
          ),

          const SizedBox(height: 16),

          buildLoadingBox(),

          const SizedBox(height: 18),

          const Text(
            'AI Results',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          ...results.map(buildResultCard),
        ],
      ),
    );
  }

  void openSavedDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111827),
      builder: (_) {
        if (savedBases.isEmpty) {
          return const SizedBox(
            height: 180,
            child: Center(
              child: Text('No saved bases yet'),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Saved Bases',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      savedBases.clear();

                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('saved_bases');

                      if (!mounted) return;

                      setState(() {});
                      Navigator.pop(context);
                    },
                    child: const Text('Clear All'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: GridView.builder(
                  itemCount: savedBases.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (_, index) {
                    final item = savedBases[index];

                    return GestureDetector(
                      onTap: () => openBase(item),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          item.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return Container(
                              color: const Color(0xFF1F2937),
                              child: const Icon(Icons.image_not_supported),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void openMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111827),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.star_rounded),
                title: const Text('Rate App'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.favorite_rounded),
                title: const Text('Donate'),
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(
                    Uri.parse('https://buymeacoffee.com/cocbase'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.email_rounded),
                title: const Text('Contact'),
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(
                    Uri.parse('mailto:contact@cocbasepro.com'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_rounded),
                title: const Text('About'),
                onTap: () {
                  Navigator.pop(context);

                  showAboutDialog(
                    context: context,
                    applicationName: 'AI Find Base',
                    applicationVersion: '1.0.0',
                    children: const [
                      Text(
                        'Google Lens for Clash of Clans bases.\n\n'
                            'Find similar bases instantly with AI.',
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildLoadingBox() {
    if (!loading) return const SizedBox.shrink();

    return const Center(
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 10),
          Text('Analyzing image...'),
        ],
      ),
    );
  }

  @override
  void dispose() {
    bannerAd?.dispose();
    super.dispose();
  }
  void loadBannerAd() {
    bannerAd = BannerAd(
      adUnitId: iosBannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() {
            bannerReady = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdMob banner failed: ${error.message}');
          ad.dispose();

          if (!mounted) return;

          setState(() {
            bannerReady = false;
          });
        },
      ),
    )..load();
  }

  Widget buildStatsPanel() {
    final safeLeft = freeSearchLeft < 0 ? 0 : freeSearchLeft;
    final maxCredit = safeLeft > 10 ? safeLeft : 10;
    final percent = maxCredit == 0 ? 0.0 : (safeLeft / maxCredit).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _statBlock(
                  title: 'Search Credits',
                  value: isSubscriber ? '∞' : '$safeLeft',
                  subtitle: isSubscriber ? 'unlimited' : 'searches left',
                  color: const Color(0xFFFACC15),
                ),
              ),
              _divider(),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      isSubscriber ? '100%' : '${(percent * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Remaining',
                      style: TextStyle(
                        color: Color(0xFFD1D5DB),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: isSubscriber ? 1 : percent,
                        backgroundColor: Colors.white.withOpacity(0.12),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFFACC15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _divider(),
              Expanded(
                child: _premiumStatBlock(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '▶ Watch Ad = +2 free searches\n👑 Premium = Unlimited',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    height: 1.35,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: watchAdMock,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Watch Ad (+2)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBlock({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFFD1D5DB),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFFCBD5E1),
          ),
        ),
      ],
    );
  }
  Widget _premiumStatBlock() {
    return InkWell(
      onTap: showPremiumPopup,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          children: [
            const Text(
              'Premium',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFFD1D5DB),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                isSubscriber ? 'ACTIVE' : 'UNLIMITED',
                maxLines: 1,
                style: TextStyle(
                  fontSize: isSubscriber ? 22 : 20,
                  fontWeight: FontWeight.w900,
                  color: isSubscriber
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFFACC15),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isSubscriber ? 'enabled' : 'tap to upgrade',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFCBD5E1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 72,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: Colors.white.withOpacity(0.12),
    );
  }

  Widget buildFeatureBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF581C87).withOpacity(0.72),
            const Color(0xFF0F172A).withOpacity(0.92),
            const Color(0xFF075985).withOpacity(0.62),
          ],
        ),
        border: Border.all(
          color: const Color(0xFFA855F7).withOpacity(0.55),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.35),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFE9D5FF),
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Search Engine 2026',
                  style: TextStyle(
                    color: Color(0xFFC084FC),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$totalBases+ verified bases • TH/BH/CH supported',
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAdBanner() {
    if (!bannerReady || bannerAd == null) {
      return const SizedBox(
        height: 0,
      );
    }

    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      margin: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        width: bannerAd!.size.width.toDouble(),
        height: bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: bannerAd!),
      ),
    );
  }

  List<String> levelsForType(String type) {
    if (type == 'BH') {
      return List.generate(8, (i) => 'BH${i + 3}');
    }

    if (type == 'CH') {
      return List.generate(8, (i) => 'CH${i + 3}');
    }

    return List.generate(16, (i) => 'TH${i + 3}');
  }

  String currentLevelType() {
    if (selectedLevel == null) return 'TH';

    if (selectedLevel!.startsWith('BH')) return 'BH';
    if (selectedLevel!.startsWith('CH')) return 'CH';

    return 'TH';
  }

  Future<void> openLevelPicker() async {
    String type = currentLevelType();
    String tempLevel = selectedLevel ?? levelsForType(type).last;

    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final levels = levelsForType(type);
            final initialIndex = levels.indexOf(tempLevel);
            final safeIndex = initialIndex < 0 ? levels.length - 1 : initialIndex;

            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.10),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Choose Base Level',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.10),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: ['TH', 'BH', 'CH'].map((item) {
                        final active = type == item;

                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: FilledButton(
                              onPressed: () {
                                setModalState(() {
                                  type = item;
                                  tempLevel = levelsForType(item).last;
                                });
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: active
                                    ? const Color(0xFFFACC15)
                                    : const Color(0xFF1F2937),
                                foregroundColor:
                                active ? Colors.black : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                item,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    Container(
                      height: 220,
                      decoration: BoxDecoration(
                        color: const Color(0xFF020617).withOpacity(0.45),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: ListWheelScrollView.useDelegate(
                        key: ValueKey(type),
                        controller: FixedExtentScrollController(
                          initialItem: safeIndex,
                        ),
                        itemExtent: 54,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (index) {
                          tempLevel = levels[index];
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: levels.length,
                          builder: (_, index) {
                            final level = levels[index];
                            final active = level == tempLevel;

                            return Center(
                              child: Text(
                                level,
                                style: TextStyle(
                                  fontSize: active ? 28 : 22,
                                  fontWeight: FontWeight.w900,
                                  color: active
                                      ? const Color(0xFFFACC15)
                                      : Colors.white.withOpacity(0.75),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Close'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.18),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(context, tempLevel),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Select'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFACC15),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (value == null) return;

    setState(() {
      selectedLevel = value;
    });
  }

  Widget buildLevelSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose Base Level',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: openLevelPicker,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF111827).withOpacity(0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selectedLevel == null
                    ? const Color(0xFFA78BFA)
                    : const Color(0xFFFACC15),
                width: 1.3,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedLevel ?? 'Required: TH18, BH10, CH10...',
                    style: TextStyle(
                      color: selectedLevel == null
                          ? const Color(0xFFCBD5E1)
                          : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/bg_ai_finder.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return Container(color: const Color(0xFF020617));
              },
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.72)),
          ),
          SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [


                    const SizedBox(height: 18),

                buildStatsPanel(),

                const SizedBox(height: 12),

                buildAdBanner(),

                const SizedBox(height: 12),

                buildFeatureBanner(),

                const SizedBox(height: 16),

                ImagePickerBox(image: selectedImage),

                const SizedBox(height: 12),

                ActionButtons(
                  onChoose: pickImage,
                  onReset: resetAll,
                ),

                const SizedBox(height: 16),

                buildLevelSelector(),

                const SizedBox(height: 16),

                      SearchButton(
                        loading: loading,
                        onPressed: handleSearchLogic,
                      ),
              const SizedBox(height: 16),
              buildLoadingBox(),
              const SizedBox(height: 18),
              const Text(
                'AI Results',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              ...results.map(buildResultCard),
        ],
      ),
    ),
    ),
    ],
    ),
    bottomNavigationBar: BottomNav(
    onHome: () {},
    onSaved: openSavedDialog,
    onPremium: showPremiumPopup,
    onMore: openMoreMenu,
    ),
    );
  }
}