import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';

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
  InterstitialAd? interstitialAd;
  RewardedAd? rewardedAd;

  bool bannerReady = false;
  bool interstitialReady = false;
  bool rewardedReady = false;

  Set<String> likedBases = {};
  Set<String> dislikedBases = {};


  final InAppPurchase iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? purchaseSubscription;

  List<ProductDetails> subscriptionProducts = [];

  static const Set<String> subscriptionIds = {
    'premium_monthly',
    'premium_yearly',
  };

  static const String iosBannerAdUnitId =
      'ca-app-pub-9371341402256787/4621781605';

  static const String iosInterstitialAdUnitId =
      'ca-app-pub-9371341402256787/2615399517';

  static const String iosRewardedAdUnitId =
      'ca-app-pub-9371341402256787/2152365082';

  @override
  void initState() {
    super.initState();

    initializeApp();

    loadBannerAd();
    loadInterstitialAd();
    loadRewardedAd();
    initPurchases();
  }

  @override
  void dispose() {
    bannerAd?.dispose();
    interstitialAd?.dispose();
    rewardedAd?.dispose();
    super.dispose();
    purchaseSubscription?.cancel();
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

    if (totalSearchCount >= 4 && totalSearchCount % 4 == 0) {
      maybeShowInterstitialAd();
    }

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
      showRewardAd();
    } else {
      await searchSimilarBases();
    }
  }

  void watchAdMock() {
    showRewardAd();
  }

  void loadBannerAd() {
    bannerAd?.dispose();

    bannerAd = BannerAd(
      adUnitId: iosBannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          debugPrint('Banner loaded');

          if (!mounted) return;

          setState(() {
            bannerReady = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint(
            'Banner failed: code=${error.code}, domain=${error.domain}, message=${error.message}',
          );

          ad.dispose();

          if (!mounted) return;

          setState(() {
            bannerReady = false;
          });
        },
      ),
    )..load();
  }

  void loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: iosInterstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          interstitialAd = ad;
          interstitialReady = true;
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial failed: ${error.message}');
          interstitialReady = false;
        },
      ),
    );
  }

  void loadRewardedAd() {
    RewardedAd.load(
      adUnitId: iosRewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('Rewarded loaded');
          rewardedAd = ad;
          rewardedReady = true;

          if (mounted) {
            setState(() {});
          }
        },
        onAdFailedToLoad: (error) {
          debugPrint(
            'Rewarded failed: code=${error.code}, domain=${error.domain}, message=${error.message}',
          );

          rewardedAd = null;
          rewardedReady = false;

          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
  }

  void maybeShowInterstitialAd() {
    if (!interstitialReady || interstitialAd == null) {
      loadInterstitialAd();
      return;
    }

    final ad = interstitialAd!;

    interstitialAd = null;
    interstitialReady = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Interstitial show failed: ${error.message}');
        ad.dispose();
        loadInterstitialAd();
      },
    );

    ad.show();
  }

  void showRewardAd() {
    if (!rewardedReady || rewardedAd == null) {
      loadRewardedAd();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ad is still loading. Please try again in a few seconds.'),
        ),
      );

      return;
    }

    final ad = rewardedAd!;

    rewardedAd = null;
    rewardedReady = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('Rewarded ad showed');
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('Rewarded ad dismissed');
        ad.dispose();
        loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Rewarded show failed: ${error.message}');
        ad.dispose();
        loadRewardedAd();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ad failed to show: ${error.message}')),
        );
      },
    );

    ad.show(
      onUserEarnedReward: (ad, reward) async {
        debugPrint('Reward earned: ${reward.amount} ${reward.type}');
        await rewardSuccess();
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
        content: Text('🎉 You received +2 free searches'),
      ),
    );
  }

  Future<void> initPurchases() async {
    final available = await iap.isAvailable();

    if (!available) {
      debugPrint('IAP not available');
      return;
    }

    purchaseSubscription = iap.purchaseStream.listen(
      handlePurchaseUpdates,
      onDone: () {
        purchaseSubscription?.cancel();
      },
      onError: (error) {
        debugPrint('IAP error: $error');
      },
    );

    await loadSubscriptionProducts();
    await iap.restorePurchases();
  }

  Future<void> loadSubscriptionProducts() async {
    final response = await iap.queryProductDetails(subscriptionIds);

    if (response.error != null) {
      debugPrint('IAP product error: ${response.error}');
      return;
    }

    if (response.productDetails.isEmpty) {
      debugPrint('No subscription products found');
      return;
    }

    setState(() {
      subscriptionProducts = response.productDetails;
    });
  }

  Future<void> buySubscription(ProductDetails product) async {
    final purchaseParam = PurchaseParam(productDetails: product);

    await iap.buyNonConsumable(
      purchaseParam: purchaseParam,
    );
  }

  Future<void> handlePurchaseUpdates(
      List<PurchaseDetails> purchases,
      ) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await unlockPremium();
      }

      if (purchase.pendingCompletePurchase) {
        await iap.completePurchase(purchase);
      }
    }
  }

  Future<void> unlockPremium() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('is_subscriber', true);

    if (!mounted) return;

    setState(() {
      isSubscriber = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('👑 Premium activated'),
      ),
    );
  }

  Future<void> restorePremium() async {
    await iap.restorePurchases();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Restoring purchases...'),
      ),
    );
  }
  Future<void> maybeShowPremiumPopup() async {

    final prefs = await SharedPreferences.getInstance();

    int count =
        prefs.getInt('premium_popup_count') ?? 0;

    int last =
        prefs.getInt('premium_popup_last') ?? 0;

    final now =
        DateTime.now().millisecondsSinceEpoch;

    const twoDays =
        2 * 24 * 60 * 60 * 1000;

    if (count >= 3) return;

    if (last != 0 && now - last < twoDays) return;

    await prefs.setInt(
      'premium_popup_count',
      count + 1,
    );

    await prefs.setInt(
      'premium_popup_last',
      now,
    );

    showPremiumPopup();
  }

  void showPremiumPopup() {
    ProductDetails? monthly;
    ProductDetails? yearly;

    for (final product in subscriptionProducts) {
      if (product.id == 'premium_monthly') {
        monthly = product;
      }

      if (product.id == 'premium_yearly') {
        yearly = product;
      }
    }

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            '👑 AI Find Base Premium',
            style: TextStyle(
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Unlock the full AI search experience.\n\n'
                    '✓ Unlimited AI searches\n'
                    '✓ Remove ads\n'
                    '✓ Faster experience\n'
                    '✓ Priority AI base matching',
                style: TextStyle(
                  height: 1.35,
                ),
              ),

              const SizedBox(height: 18),

              if (subscriptionProducts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Loading subscription packages...',
                    style: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 13,
                    ),
                  ),
                ),

              if (monthly != null)
                _subscriptionButton(
                  title: 'Monthly',
                  subtitle: 'Flexible monthly access',
                  price: monthly.price,
                  badge: null,
                  onTap: () {
                    Navigator.pop(context);
                    buySubscription(monthly!);
                  },
                ),

              if (yearly != null)
                _subscriptionButton(
                  title: 'Yearly',
                  subtitle: 'Best value for long-term use',
                  price: yearly.price,
                  badge: 'SAVE MORE',
                  highlighted: true,
                  onTap: () {
                    Navigator.pop(context);
                    buySubscription(yearly!);
                  },
                ),

              const SizedBox(height: 8),

              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  restorePremium();
                },
                child: const Text('Restore Purchase'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Maybe later'),
            ),
          ],
        );
      },
    );
  }

  Widget _subscriptionButton({
    required String title,
    required String subtitle,
    required String price,
    required VoidCallback onTap,
    String? badge,
    bool highlighted = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlighted
              ? const Color(0xFFFACC15)
              : const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: highlighted
                ? const Color(0xFFFACC15)
                : Colors.white.withOpacity(0.12),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: highlighted ? Colors.black : Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: highlighted
                                ? Colors.black
                                : const Color(0xFFFACC15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: highlighted
                                  ? const Color(0xFFFACC15)
                                  : Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: highlighted
                          ? Colors.black.withOpacity(0.72)
                          : const Color(0xFFCBD5E1),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              price,
              style: TextStyle(
                color: highlighted ? Colors.black : const Color(0xFFFACC15),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
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

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 45),
      );

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
      setState(() {
        savedBases.add(item);
      });

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

  Widget buildStatsPanel() {
    final safeLeft = freeSearchLeft < 0 ? 0 : freeSearchLeft;
    final maxCredit = safeLeft > 10 ? safeLeft : 10;
    final percent =
    maxCredit == 0 ? 0.0 : (safeLeft / maxCredit).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
                        backgroundColor: Colors.white.withOpacity(0.18),
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

          buildAdBanner(),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Text(
                  '▶ Watch Ad = +2 free searches',

                  style: TextStyle(
                    color: Colors.white.withOpacity(.8),
                    fontSize: 13,
                  ),
                ),
              ),

              const SizedBox(width: 10),

              ElevatedButton.icon(
                onPressed: watchAdMock,

                icon: const Icon(
                  Icons.play_arrow_rounded,
                ),

                label: const Text(
                  'Watch Ad (+2)',
                ),

                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(
                    0xFF7C3AED,
                  ),

                  foregroundColor: Colors.white,

                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),

                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Align(
            alignment: Alignment.centerLeft,

            child: Text(
              '👑 Premium = Unlimited',

              style: TextStyle(
                color: Colors.white.withOpacity(.8),
                fontSize: 13,
              ),
            ),
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
      borderRadius: BorderRadius.circular(14),

      onTap: showPremiumPopup,

      child: Column(
        children: [
          const Text(
            'Premium',

            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            isSubscriber
                ? 'Unlimited'
                : 'Unlimited',

            textAlign: TextAlign.center,

            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFFFACC15),
            ),
          ),

          const SizedBox(height: 4),

          Text(
            'tap to upgrade',

            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(.65),
            ),
          ),
        ],
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

  Widget buildAdBanner() {
    if (!bannerReady || bannerAd == null) {
      return const SizedBox(
        height: 50,
        child: Center(
          child: Text(
            'Ad loading...',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: bannerAd!.size.height.toDouble(),
      child: Center(
        child: SizedBox(
          width: bannerAd!.size.width.toDouble(),
          height: bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: bannerAd!),
        ),
      ),
    );
  }

  Widget buildFeatureBanner() {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF7C3AED).withOpacity(0.85),
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
                  fontSize: 18,
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
    );
  }

  List<String> levelsForType(String type) {
    if (type == 'BH') return List.generate(8, (i) => 'BH${i + 3}');
    if (type == 'CH') return List.generate(8, (i) => 'CH${i + 3}');

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
            final safeIndex =
            initialIndex < 0 ? levels.length - 1 : initialIndex;

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
                              ),
                              child: Text(item),
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
                      ),
                      child: ListWheelScrollView.useDelegate(
                        key: ValueKey(type),
                        controller: FixedExtentScrollController(
                          initialItem: safeIndex,
                        ),
                        itemExtent: 54,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (index) {
                          setModalState(() {
                            tempLevel = levels[index];
                          });
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: levels.length,
                          builder: (_, index) {
                            final level = levels[index];
                            final active = level == tempLevel;

                            return Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: active ? 120 : 90,
                                height: active ? 46 : 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: active
                                      ? const Color(0xFFFACC15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  level,
                                  style: TextStyle(
                                    fontSize: active ? 24 : 20,
                                    fontWeight: FontWeight.w900,
                                    color: active
                                        ? Colors.black
                                        : Colors.white.withOpacity(0.65),
                                  ),
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

  Future<void> feedbackBase(BaseResult item, bool like) async {
    final key = item.postUrl;

    setState(() {
      if (like) {
        likedBases.add(key);
        dislikedBases.remove(key);
      } else {
        dislikedBases.add(key);
        likedBases.remove(key);
      }
    });

    try {
      await http.post(
        Uri.parse('https://api.cocbasepro.com/ai/feedback'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'postUrl': item.postUrl,
          'title': item.title,
          'level': item.level,
          'baseType': item.baseType,
          'style': item.style,
          'feedback': like ? 'like' : 'dislike',
          'time': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {}

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          like ? '👍 Thanks! Your feedback helps improve AI search results' : '👎 Thanks! We will improve future AI results',
        ),
      ),
    );
  }

  Widget buildAnalysisProgressCard() {
    if (!loading) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFA855F7).withOpacity(0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Padding(
              padding: EdgeInsets.all(11),
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFFFACC15),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analyzing base image...',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'AI is comparing layouts, level and visual structure.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFFCBD5E1),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildResultCard(BaseResult item) {
    final percent =
    item.score <= 1 ? (item.score * 100).round() : item.score.round();

    final saved = savedBases.any(
          (base) => base.postUrl == item.postUrl,
    );

    final liked = likedBases.contains(item.postUrl);
    final disliked = dislikedBases.contains(item.postUrl);
    final isPremium = item.premium == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Image.network(
                  item.image,
                  height: 215,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return Container(
                      height: 215,
                      width: double.infinity,
                      color: const Color(0xFF1F2937),
                      child: const Center(
                        child: Text('Image not available'),
                      ),
                    );
                  },
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.04),
                          Colors.black.withOpacity(0.72),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.62),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFACC15),
                          size: 18,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '4.8',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFACC15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$percent% Match',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          Text(

            item.title,

            maxLines: 1,

            overflow: TextOverflow.ellipsis,

            style: const TextStyle(

              fontSize: 16,

              fontWeight: FontWeight.w800,

              color: Colors.white,

            ),

          ),

          const SizedBox(height:8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _resultChip(item.level),
              _resultChip(item.baseType),
              _resultChip(item.style),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isPremium
                      ? const Color(0xFFFACC15)
                      : const Color(0xFF22C55E),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isPremium ? '👑 Premium' : '✅ Free',
                  style: TextStyle(
                    color: isPremium ? Colors.black : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
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
                icon: Icon(
                  saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                ),
                color: saved ? const Color(0xFFFACC15) : Colors.white70,
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => feedbackBase(item, true),
                  icon: Icon(
                    Icons.thumb_up_rounded,
                    color: liked ? const Color(0xFF22C55E) : Colors.white70,
                  ),
                  label: const Text('Helpful'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                    liked ? const Color(0xFF22C55E) : Colors.white,
                    side: BorderSide(
                      color: liked
                          ? const Color(0xFF22C55E)
                          : Colors.white24,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => feedbackBase(item, false),
                  icon: Icon(
                    Icons.thumb_down_rounded,
                    color: disliked ? const Color(0xFFEF4444) : Colors.white70,
                  ),
                  label: const Text('Not Accurate'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                    disliked ? const Color(0xFFEF4444) : Colors.white,
                    side: BorderSide(
                      color: disliked
                          ? const Color(0xFFEF4444)
                          : Colors.white24,
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

  Widget _resultChip(String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFE5E7EB),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
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
            child: Center(child: Text('No saved bases yet')),
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
                  buildStatsPanel(),

                  const SizedBox(height: 12),

                  buildFeatureBanner(),
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
                    loading: false,
                    onPressed: () async {
                      if (loading) return;
                      await handleSearchLogic();
                    },
                  ),

                  const SizedBox(height: 12),

                  buildAnalysisProgressCard(),

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