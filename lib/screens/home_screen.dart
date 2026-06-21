import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/app_header.dart';
import '../widgets/usage_card.dart';
import '../widgets/image_picker_box.dart';
import '../widgets/action_buttons.dart';
import '../widgets/level_input.dart';
import '../widgets/search_button.dart';
import '../widgets/bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker picker = ImagePicker();
  final TextEditingController levelController = TextEditingController();

  File? selectedImage;
  int totalBases = 2633;
  int freeSearchLeft = 5;
  bool loading = false;

  Future<void> pickImage() async {
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );

    if (file == null) return;

    setState(() {
      selectedImage = File(file.path);
    });
  }

  void resetAll() {
    setState(() {
      selectedImage = null;
      levelController.clear();
      loading = false;
    });
  }

  void fakeSearch() {
    if (selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an image first')),
      );
      return;
    }

    if (levelController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'For best results, enter TH/BH/CH level, e.g. TH18, BH10, CH10',
          ),
        ),
      );
    }

    setState(() {
      loading = true;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        loading = false;
      });
    });
  }

  void watchAdMock() {
    setState(() {
      freeSearchLeft += 2;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You received +2 free searches')),
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
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF020617),
              ),
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
                  LevelInput(controller: levelController),
                  const SizedBox(height: 16),
                  SearchButton(
                    loading: loading,
                    onPressed: fakeSearch,
                  ),
                  const SizedBox(height: 16),
                  if (loading)
                    const Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text('Analyzing image...'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNav(),
    );
  }
}