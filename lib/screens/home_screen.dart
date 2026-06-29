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
  final ScrollController scrollController = ScrollController();

  File? selectedImage;
  String? selectedLevel;
  String currentSearchId = '';

  int totalBases = 2633;
  int freeSearchLeft = 0;
  int totalSearchCount = 0;

  bool loading = false;
  bool isSubscriber = false;
  bool dailyBonusPopupPending = false;

  List<BaseResult> results = [];
  List<BaseResult> savedBases = [];

  BannerAd? bannerAd;
  InterstitialAd? interstitialAd;
  RewardedAd? rewardedAd;

  bool bannerReady = false;
  bool interstitialReady = false;
  bool rewardedReady = false;
  bool rewardedLoading = false;
  bool rewardedShowing = false;
  int rewardedRetryCount = 0;

  Set<String> likedBases = {};
  Set<String> dislikedBases = {};
  BaseResult? pendingPremiumBase;


  static const String premiumMapUrl =
      'https://raw.githubusercontent.com/hoangquocvuong/premium-map.json/main/premium-map.json';

  bool premiumMapLoaded = false;
  Map<String, String> premiumLinkMap = {};


  final InAppPurchase iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? purchaseSubscription;

  List<ProductDetails> subscriptionProducts = [];

  static const Set<String> subscriptionIds = {
    'aifindbase_premium_monthly',
    'aifindbase_premium_yearly',
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
    initPurchases();
  }

  @override
  void dispose() {
    bannerAd?.dispose();
    interstitialAd?.dispose();
    rewardedAd?.dispose();
    scrollController.dispose();
    purchaseSubscription?.cancel();
    super.dispose();
  }

  void showDailyBonusPopup() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return AlertDialog(
          title: const Text('🎁 Daily Login Reward'),
          content: const Text(
            '+2 Search Credits added!\n\n'
                'Open the app every day to receive more free AI searches.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Awesome!'),
            ),
          ],
        );
      },
    );
  }

  Future<void> initializeApp() async {
    final prefs = await SharedPreferences.getInstance();

    totalSearchCount = prefs.getInt('total_search_count') ?? 0;
    freeSearchLeft = prefs.getInt('free_search_left') ?? 0;
    isSubscriber = prefs.getBool('is_subscriber') ?? false;

    await loadSavedBases(prefs);
    await loadTotalBases();
    await loadPremiumLinkMap();

    final welcomeShown = prefs.getBool('welcome_bonus_shown') ?? false;

    if (!welcomeShown) {
      freeSearchLeft += 5;

      await prefs.setBool('welcome_bonus_shown', true);
      await prefs.setInt('free_search_left', freeSearchLeft);
      await prefs.setString(
        'daily_bonus_day',
        DateTime.now().toIso8601String().substring(0, 10),
      );

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
      dailyBonusPopupPending = true;

      await prefs.setString('daily_bonus_day', today);
      await prefs.setInt('free_search_left', freeSearchLeft);
    }

    if (mounted) {
      setState(() {});

      if (dailyBonusPopupPending) {
        dailyBonusPopupPending = false;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDailyBonusPopup();
        });
      }
    }

    if (isSubscriber) {
      disposeAdsForPremium();
    } else {
      loadBannerAd();
      loadInterstitialAd();
      loadRewardedAd();
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
      await showRewardAd(
        onRewardEarned: rewardSuccess,
        unavailableMessage:
        'Video reward is temporarily unavailable. Please try again in a moment.',
      );
    } else {
      await searchSimilarBases();
    }
  }

  void disposeAdsForPremium() {
    bannerAd?.dispose();
    bannerAd = null;
    bannerReady = false;

    interstitialAd?.dispose();
    interstitialAd = null;
    interstitialReady = false;

    rewardedAd?.dispose();
    rewardedAd = null;
    rewardedReady = false;
    rewardedLoading = false;
    rewardedShowing = false;

    if (mounted) {
      setState(() {});
    }
  }

  void showPremiumNoAdsMessage() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('👑 Premium is active: unlimited searches and no ads.'),
      ),
    );
  }

  void watchAdMock() {
    if (isSubscriber) {
      showPremiumNoAdsMessage();
      return;
    }

    showRewardAd(
      onRewardEarned: rewardSuccess,
      unavailableMessage:
      'Video reward is temporarily unavailable. Please try again in a moment.',
    );
  }

  void loadBannerAd() {
    if (isSubscriber) {
      disposeAdsForPremium();
      return;
    }

    bannerAd?.dispose();

    bannerAd = BannerAd(
      adUnitId: iosBannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('Banner loaded');

          if (!mounted || isSubscriber) {
            ad.dispose();
            return;
          }

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
    if (isSubscriber) {
      interstitialAd?.dispose();
      interstitialAd = null;
      interstitialReady = false;
      return;
    }

    InterstitialAd.load(
      adUnitId: iosInterstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (isSubscriber) {
            ad.dispose();
            return;
          }

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

  void goHome() {
    FocusScope.of(context).unfocus();

    if (scrollController.hasClients) {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }

  }

  void loadRewardedAd({bool force = false}) {
    if (isSubscriber) {
      rewardedAd?.dispose();
      rewardedAd = null;
      rewardedReady = false;
      rewardedLoading = false;
      return;
    }

    if (rewardedLoading) return;

    if (!force && rewardedAd != null && rewardedReady) return;

    rewardedLoading = true;

    RewardedAd.load(
      adUnitId: iosRewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('Rewarded loaded');

          if (isSubscriber) {
            ad.dispose();
            rewardedAd = null;
            rewardedReady = false;
            rewardedLoading = false;
            return;
          }

          rewardedAd?.dispose();
          rewardedAd = ad;

          rewardedReady = true;
          rewardedLoading = false;
          rewardedRetryCount = 0;

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
          rewardedLoading = false;

          if (mounted) {
            setState(() {});
          }

          if (isSubscriber) return;

          rewardedRetryCount++;
          final retrySeconds = rewardedRetryCount <= 2 ? 4 : 10;

          Future.delayed(Duration(seconds: retrySeconds), () {
            if (!mounted || isSubscriber) return;
            loadRewardedAd(force: true);
          });
        },
      ),
    );
  }

  void showRewardUnavailableDialog({
    required String message,
    required VoidCallback onTryAgain,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return AlertDialog(
          title: const Text('Video Reward'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: onTryAgain,
              child: const Text('Try Again'),
            ),
          ],
        );
      },
    );
  }

  Future<void> showRewardAd({
    required Future<void> Function() onRewardEarned,
    String unavailableMessage =
    'Video reward is temporarily unavailable. Please try again in a moment.',
  }) async {
    if (isSubscriber) {
      showPremiumNoAdsMessage();
      return;
    }

    if (rewardedShowing) return;

    if (!rewardedReady || rewardedAd == null) {
      loadRewardedAd(force: true);

      if (!mounted || isSubscriber) return;

      showRewardUnavailableDialog(
        message: unavailableMessage,
        onTryAgain: () {
          Navigator.pop(context);

          Future.delayed(const Duration(milliseconds: 700), () {
            if (!mounted || isSubscriber) return;

            showRewardAd(
              onRewardEarned: onRewardEarned,
              unavailableMessage: unavailableMessage,
            );
          });
        },
      );

      return;
    }

    final ad = rewardedAd!;

    rewardedAd = null;
    rewardedReady = false;
    rewardedShowing = true;

    bool rewardEarned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('Rewarded ad showed');
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('Rewarded ad dismissed');

        rewardedShowing = false;

        ad.dispose();

        if (!isSubscriber) {
          loadRewardedAd(force: true);
        }

        if (!rewardEarned && mounted && !isSubscriber) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video was closed before the reward was completed.'),
            ),
          );
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint(
          'Rewarded show failed: code=${error.code}, domain=${error.domain}, message=${error.message}',
        );

        rewardedShowing = false;

        ad.dispose();

        if (!isSubscriber) {
          loadRewardedAd(force: true);
        }

        if (!mounted || isSubscriber) return;

        showRewardUnavailableDialog(
          message: unavailableMessage,
          onTryAgain: () {
            Navigator.pop(context);

            Future.delayed(const Duration(milliseconds: 700), () {
              if (!mounted || isSubscriber) return;

              showRewardAd(
                onRewardEarned: onRewardEarned,
                unavailableMessage: unavailableMessage,
              );
            });
          },
        );
      },
    );

    await ad.show(
      onUserEarnedReward: (ad, reward) async {
        debugPrint('Reward earned: ${reward.amount} ${reward.type}');

        rewardEarned = true;
        await onRewardEarned();
      },
    );
  }

  void maybeShowInterstitialAd() {
    if (isSubscriber) return;

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
        if (!isSubscriber) {
          loadInterstitialAd();
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Interstitial show failed: ${error.message}');
        ad.dispose();
        if (!isSubscriber) {
          loadInterstitialAd();
        }
      },
    );

    ad.show();
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

    disposeAdsForPremium();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('👑 Premium activated: unlimited searches and no ads.'),
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
    if (isSubscriber) {
      showPremiumNoAdsMessage();
      return;
    }

    ProductDetails? monthly;
    ProductDetails? yearly;

    for (final product in subscriptionProducts) {
      if (product.id == 'aifindbase_premium_monthly') {
        monthly = product;
      }

      if (product.id == 'aifindbase_premium_yearly') {
        yearly = product;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 22,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 430,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5FF),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '🚀 Upgrade AI Search',
                            style: TextStyle(
                              color: Color(0xFF111827),
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF374151),
                            size: 26,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Find Similar Bases Faster with AI',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    buildPremiumItem('Unlimited AI Image Searches'),
                    buildPremiumItem('Remove All Ads'),
                    buildPremiumItem('Faster AI Matching'),
                    buildPremiumItem('Access 2600+ Verified Bases'),
                    buildPremiumItem('TH / BH / CH Search Support'),

                    const SizedBox(height: 8),

                    Text(
                      'Unlimited AI-powered base search and premium features.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.45),
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      'Auto-renews unless cancelled.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.45),
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 8),

                    if (subscriptionProducts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Loading subscription packages...',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 13,
                          ),
                        ),
                      ),

                    Row(
                      children: [
                        Expanded(
                          child: premiumPlanCard(
                            title: 'Monthly',
                            price: monthly?.price ?? '\$4.99',
                            subtitle: '/ Month',
                            highlighted: false,
                            onTap: () {
                              if (monthly == null) return;

                              Navigator.pop(context);
                              buySubscription(monthly!);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: premiumPlanCard(
                            title: 'Yearly',
                            price: yearly?.price ?? '\$39.99',
                            subtitle: '/ Year',
                            badge: 'Save 40%',
                            highlighted: true,
                            onTap: () {
                              if (yearly == null) return;

                              Navigator.pop(context);
                              buySubscription(yearly!);
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () {
                            launchUrl(
                              Uri.parse(
                                'https://www.cocbasepro.com/p/privacy-policy.html',
                              ),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          child: const Text(
                            'Privacy Policy',
                            style: TextStyle(
                              color: Color(0xFF7C3AED),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Text(
                          '|',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            launchUrl(
                              Uri.parse(
                                'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
                              ),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          child: const Text(
                            'Terms of Use',
                            style: TextStyle(
                              color: Color(0xFF7C3AED),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        restorePremium();
                      },
                      child: const Text(
                        'Restore Purchase',
                        style: TextStyle(
                          color: Color(0xFF6D28D9),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildPremiumItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF22C55E),
            size: 25,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget premiumPlanCard({
    required String title,
    required String price,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
    bool highlighted = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: highlighted
                ? const Color(0xFF22C55E)
                : const Color(0xFFE5E7EB),
            width: highlighted ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6D28D9),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              price,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6D28D9),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6D28D9),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(height: 4),
              Text(
                badge,
                style: const TextStyle(
                  color: Color(0xFF22C55E),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      ),
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
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),

            border: Border.all(
              color: highlighted
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFE5E7EB),
              width: highlighted ? 2 : 1,
            ),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),

          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6D28D9),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                price,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6D28D9),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),

              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6D28D9),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),

              if (badge != null) ...[
                const SizedBox(height: 4),

                Text(
                  badge,
                  style: const TextStyle(
                    color: Color(0xFF22C55E),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
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
      currentSearchId = data['searchId']?.toString() ?? '';
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
    final isPremiumBase = item.premium == true;

    if (isPremiumBase && !isSubscriber) {
      showPremiumBaseLockedDialog(item);
      return;
    }

    await openBaseLink(item);
  }

  void showPremiumBaseLockedDialog(BaseResult item) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F5FF),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.38),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFACC15).withOpacity(0.22),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Color(0xFFEAB308),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Premium Base',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF374151),
                        size: 26,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'This matched base is premium.',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Upgrade to unlock premium base links instantly, or watch a short ad to get this base link.',
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.62),
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          showRewardAdForPremiumBase(item);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6D28D9),
                          side: const BorderSide(
                            color: Color(0xFF7C3AED),
                            width: 1.4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text(
                          'Watch Ad',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          showPremiumPopup();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFACC15),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text(
                          'Upgrade',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  String cleanLayoutLink(String value) {
    return value
        .trim()
        .replaceAll('&amp;', '&')
        .replaceAll('&AMP;', '&');
  }

  String getRawBaseLink(BaseResult item) {
    final rawLink =
    item.accessLink.trim().isNotEmpty ? item.accessLink : item.postUrl;

    return cleanLayoutLink(rawLink);
  }

  String? extractPremiumMapKey(String link) {
    final cleaned = cleanLayoutLink(link);

    final uri = Uri.tryParse(cleaned);

    if (uri != null) {
      final segments = uri.pathSegments;

      final eIndex = segments.indexOf('e');

      if (eIndex >= 0 && eIndex + 1 < segments.length) {
        final id = segments[eIndex + 1].trim();

        if (RegExp(r'^\d+$').hasMatch(id)) {
          return id;
        }
      }

      for (final segment in segments.reversed) {
        final match = RegExp(r'\d+').firstMatch(segment);

        if (match != null) {
          return match.group(0);
        }
      }

      final queryId = uri.queryParameters['id'] ??
          uri.queryParameters['e'] ??
          uri.queryParameters['product'];

      if (queryId != null && RegExp(r'^\d+$').hasMatch(queryId)) {
        return queryId;
      }
    }

    final fallback = RegExp(r'/e/(\d+)').firstMatch(cleaned);

    if (fallback != null) {
      return fallback.group(1);
    }

    final anyNumber = RegExp(r'\b\d{4,}\b').firstMatch(cleaned);

    return anyNumber?.group(0);
  }

  Future<void> loadPremiumLinkMap({bool force = false}) async {
    if (premiumMapLoaded && !force) return;

    try {
      final response = await http
          .get(
        Uri.parse(premiumMapUrl),
      )
          .timeout(
        const Duration(seconds: 12),
      );

      if (response.statusCode != 200) {
        debugPrint('Premium map load failed: ${response.statusCode}');
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        debugPrint('Premium map is not a JSON object');
        return;
      }

      premiumLinkMap = decoded.map(
            (key, value) {
          return MapEntry(
            key.toString(),
            cleanLayoutLink(value.toString()),
          );
        },
      );

      premiumMapLoaded = true;

      debugPrint('Premium map loaded: ${premiumLinkMap.length} links');
    } catch (e) {
      debugPrint('Premium map error: $e');
    }
  }

  Future<String> resolveBaseLink(BaseResult item) async {
    final rawLink = getRawBaseLink(item);

    if (rawLink.isEmpty) {
      return '';
    }

    if (item.premium != true) {
      return rawLink;
    }

    if (rawLink.contains('link.clashofclans.com')) {
      return cleanLayoutLink(rawLink);
    }

    if (!premiumMapLoaded || premiumLinkMap.isEmpty) {
      await loadPremiumLinkMap();
    }

    final mapKey = extractPremiumMapKey(rawLink);

    if (mapKey != null) {
      final mappedLink = premiumLinkMap[mapKey];

      if (mappedLink != null && mappedLink.trim().isNotEmpty) {
        return cleanLayoutLink(mappedLink);
      }
    }

    final directMappedLink = premiumLinkMap[rawLink];

    if (directMappedLink != null && directMappedLink.trim().isNotEmpty) {
      return cleanLayoutLink(directMappedLink);
    }

    return rawLink;
  }

  Future<void> openBaseLink(BaseResult item) async {
    final link = await resolveBaseLink(item);

    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Base link not available')),
      );
      return;
    }

    if (item.premium == true &&
        !link.contains('link.clashofclans.com') &&
        !isSubscriber) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Premium link could not be unlocked. Please try again later.',
          ),
        ),
      );

      return;
    }

    final uri = Uri.tryParse(link);

    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid base link')),
      );
      return;
    }

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open base link')),
      );
    }
  }

  void showRewardAdForPremiumBase(BaseResult item) {
    if (isSubscriber) {
      openBaseLink(item);
      return;
    }

    pendingPremiumBase = item;

    showRewardAd(
      unavailableMessage:
      'Video reward is temporarily unavailable. Please try again in a moment or upgrade to Premium to unlock instantly.',
      onRewardEarned: () async {
        final itemToOpen = pendingPremiumBase;
        pendingPremiumBase = null;

        if (itemToOpen != null) {
          await openBaseLink(itemToOpen);
        }
      },
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
          const SizedBox(height: 24),
          buildAdBanner(),
          const SizedBox(height: 20),
          buildWatchAdCreditRow(),
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
      onTap: isSubscriber ? showPremiumNoAdsMessage : showPremiumPopup,
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
          const Text(
            'No Ads',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFFFACC15),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isSubscriber ? 'active' : 'tap to upgrade',
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

  Widget buildWatchAdCreditRow() {
    final bool disabled = isSubscriber;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                disabled
                    ? '👑 Premium active: no ads needed'
                    : '▶ Watch Ad = +2 free searches',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: disabled
                      ? const Color(0xFFFACC15).withOpacity(.86)
                      : Colors.white.withOpacity(.82),
                  fontSize: 13,
                  height: 1.0,
                  fontWeight: disabled ? FontWeight.w800 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                disabled ? 'Unlimited searches are already unlocked' : '👑 Premium = Unlimited',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(.82),
                  fontSize: 13,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 46,
          child: ElevatedButton.icon(
            onPressed: disabled ? showPremiumNoAdsMessage : watchAdMock,
            icon: Icon(
              disabled ? Icons.workspace_premium_rounded : Icons.play_arrow_rounded,
              size: 18,
            ),
            label: Text(
              disabled ? 'No Ads Active' : 'Watch Ad (+2)',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: disabled
                  ? const Color(0xFF374151)
                  : const Color(0xFF7C3AED),
              foregroundColor: disabled
                  ? const Color(0xFFFACC15)
                  : Colors.white,
              disabledBackgroundColor: const Color(0xFF374151),
              disabledForegroundColor: const Color(0xFFFACC15),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildAdBanner() {
    if (isSubscriber) {
      return const SizedBox.shrink();
    }

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
                color: const Color(0xFFFACC15),
                width: selectedLevel == null ? 1.6 : 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFACC15).withOpacity(0.14),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
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
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFFFACC15),
                ),
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
          'searchId': currentSearchId,
          'feedback': like ? 'correct' : 'incorrect',

          'selectedSlug': item.slug.isNotEmpty ? item.slug : item.id,
          'selectedPostUrl': item.postUrl,

          'postUrl': item.postUrl,
          'title': item.title,
          'level': item.level,
          'baseType': item.baseType,
          'style': item.style,
          'defense': item.defense,
          'accessLink': item.accessLink,
          'image': item.image,
          'premium': item.premium,
          'score': item.score,
          'time': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          like
              ? '👍 Thanks! Your feedback helps improve AI search results'
              : '👎 Thanks! We will improve future AI results',
        ),
      ),
    );
  }

  Widget buildAnalysisProgressCard() {
    if (!loading) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.20, end: 0.86),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4, bottom: 18),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111827).withOpacity(0.95),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFFA855F7).withOpacity(0.48),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withOpacity(0.22),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withOpacity(0.22),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFFFACC15),
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Analyzing AI Base Data...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Scanning internet layouts and ranking similar bases.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.74),
                            fontSize: 12.5,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(value * 100).round()}%',
                    style: const TextStyle(
                      color: Color(0xFFFACC15),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: value,
                  backgroundColor: const Color(0xFF334155),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFA855F7),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _analysisStep(
                      icon: Icons.image_search_rounded,
                      label: 'Reading image',
                      done: true,
                    ),
                  ),
                  Expanded(
                    child: _analysisStep(
                      icon: Icons.grid_view_rounded,
                      label: 'Detecting base',
                      done: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _analysisStep(
                      icon: Icons.storage_rounded,
                      label: 'Matching data',
                      done: true,
                    ),
                  ),
                  Expanded(
                    child: _analysisStep(
                      icon: Icons.leaderboard_rounded,
                      label: 'Ranking results',
                      done: false,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _analysisStep({
    required IconData icon,
    required String label,
    required bool done,
  }) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : icon,
          size: 15,
          color: done ? const Color(0xFF22C55E) : const Color(0xFFFACC15),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.82),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget buildAiResultsHeader() {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF7C3AED).withOpacity(0.26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFFFACC15),
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            results.isEmpty ? 'AI Results' : 'AI Results (${results.length})',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget buildAiResultsEmptyState() {
    if (loading || results.isNotEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF22D3EE).withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.image_search_rounded,
              color: Color(0xFFC084FC),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'No results yet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Upload a base screenshot, choose level and start AI search.',
                  style: TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 12.5,
                    height: 1.3,
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

    final meta = [
      item.level,
      item.baseType,
      item.style,
      item.defense,
    ].where((value) => value.trim().isNotEmpty).join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF22D3EE).withOpacity(0.70),
          width: 1.35,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22D3EE).withOpacity(0.14),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.network(
                  item.image,
                  width: 138,
                  height: 126,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return Container(
                      width: 138,
                      height: 126,
                      color: const Color(0xFF1F2937),
                      child: const Icon(Icons.image_not_supported),
                    );
                  },
                ),
              ),
              Positioned(
                left: 7,
                top: 7,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.64),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.16),
                    ),
                  ),
                  child: Text(
                    '$percent%',
                    style: const TextStyle(
                      color: Color(0xFFFACC15),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isPremium ? '👑 Premium Base' : '✅ Free Base',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isPremium
                              ? const Color(0xFFFACC15)
                              : const Color(0xFF22C55E),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => saveBase(item),
                      icon: Icon(
                        saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                      ),
                      color: saved ? const Color(0xFFFACC15) : Colors.white70,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  meta.isEmpty ? 'AI matched base layout' : meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$percent% Match',
                  style: const TextStyle(
                    color: Color(0xFFFACC15),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => openBase(item),
                    icon: const Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                    ),
                    label: const Text(
                      'Open Base',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE9D5FF),
                      foregroundColor: const Color(0xFF3B0764),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: _miniFeedbackButton(
                        label: 'Helpful',
                        icon: Icons.thumb_up_rounded,
                        active: liked,
                        activeColor: const Color(0xFF22C55E),
                        onTap: () => feedbackBase(item, true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _miniFeedbackButton(
                        label: 'Not Accurate',
                        icon: Icons.thumb_down_rounded,
                        active: disliked,
                        activeColor: const Color(0xFFEF4444),
                        onTap: () => feedbackBase(item, false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniFeedbackButton({
    required String label,
    required IconData icon,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 29,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withOpacity(0.12)
              : Colors.black.withOpacity(0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? activeColor : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? activeColor : Colors.white70,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? activeColor : Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultMetaText(
      String text, {
        Color color = const Color(0xFFE5E7EB),
        bool bold = false,
      }) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 13,
        fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
      ),
    );
  }

  Widget _dot() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '•',
        style: TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 13,
          fontWeight: FontWeight.w900,
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
                  padding: const EdgeInsets.only(
                    top: 8,
                    bottom: 24,
                    left: 4,
                    right: 4,
                  ),
                  itemCount: savedBases.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    childAspectRatio: 1.05,
                  ),
                  itemBuilder: (_, index) {
                    final item = savedBases[index];

                    return GestureDetector(
                      onTap: () => openBase(item),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.28),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
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
            child: Container(color: Colors.black.withOpacity(0.66)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppHeader(totalBases: totalBases),

                  const SizedBox(height: 18),

                  buildStatsPanel(),

                  const SizedBox(height: 26),

                  buildFeatureBanner(),

                  const SizedBox(height: 30),

                  ImagePickerBox(image: selectedImage),

                  // ✅ Tạo khoảng cách giữa khung ảnh và 2 nút
                  const SizedBox(height: 18),

                  ActionButtons(
                    onChoose: pickImage,
                    onReset: resetAll,
                  ),

                  // ✅ Tạo khoảng cách giữa 2 nút và chọn level
                  const SizedBox(height: 22),

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

                  buildAiResultsHeader(),

                  const SizedBox(height: 10),

                  buildAiResultsEmptyState(),

                  ...results.map(buildResultCard),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNav(
        onHome: goHome,
        onSaved: openSavedDialog,
        onPremium: showPremiumPopup,
        onMore: openMoreMenu,
      ),
    );
  }
}