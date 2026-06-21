import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/base_result.dart';
import '../widgets/action_buttons.dart';
import '../widgets/app_header.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/image_picker_box.dart';
import '../widgets/level_input.dart';
import '../widgets/search_button.dart';
import '../widgets/usage_card.dart';

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

  @override
  void initState() {
    super.initState();
    initializeApp();
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
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              item.image,
              height: 190,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return Container(
                  height: 190,
                  width: double.infinity,
                  color: const Color(0xFF1F2937),
                  child: const Center(
                    child: Text('Image not available'),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$percent% Match',
            style: const TextStyle(
              color: Color(0xFFFACC15),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${item.level} • ${item.baseType} • ${item.style}',
            style: const TextStyle(
              color: Color(0xFFD1D5DB),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => openBase(item),
                  child: const Text('Open Base'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => saveBase(item),
                icon: const Icon(Icons.bookmark_rounded),
                color: const Color(0xFFFACC15),
              ),
            ],
          ),
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
                  AppHeader(totalBases: totalBases),
                  const SizedBox(height: 18),
                  UsageCard(
                    freeSearchLeft: freeSearchLeft,
                    onWatchAd: watchAdMock,
                  ),
                  const SizedBox(height: 16),
                  ImagePickerBox(image: selectedImage),
                  const SizedBox(height: 12),
                  ActionButtons(
                    onChoose: pickImage,
                    onReset: resetAll,
                  ),
                  const SizedBox(height: 16),
                  LevelInput(
                    selectedLevel: selectedLevel,
                    onChanged: (value) {
                      setState(() {
                        selectedLevel = value;
                      });
                    },
                  ),
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