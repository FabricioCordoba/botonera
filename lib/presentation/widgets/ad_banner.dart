import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdMobBanner extends StatefulWidget {
  const AdMobBanner({super.key});

  static const double height = 50;

  @override
  State<AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<AdMobBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    if (_supportsMobileAds) {
      _loadBanner();
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportsMobileAds) {
      return const SizedBox.shrink();
    }

    final banner = _bannerAd;
    return SizedBox(
      height: AdMobBanner.height,
      width: double.infinity,
      child: Center(
        child: _isLoaded && banner != null
            ? SizedBox(
                width: banner.size.width.toDouble(),
                height: banner.size.height.toDouble(),
                child: AdWidget(ad: banner),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  void _loadBanner() {
    final banner = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) {
            setState(() => _isLoaded = false);
          }
        },
      ),
    );

    _bannerAd = banner;
    try {
      banner.load();
    } catch (_) {
      banner.dispose();
      _bannerAd = null;
    }
  }
}

bool get _supportsMobileAds {
  if (kIsWeb) {
    return false;
  }
  if (WidgetsBinding.instance.runtimeType.toString().contains(
    'TestWidgetsFlutterBinding',
  )) {
    return false;
  }
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

String get _bannerAdUnitId {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'ca-app-pub-3940256099942544/6300978111';
    case TargetPlatform.iOS:
      return 'ca-app-pub-3940256099942544/2934735716';
    default:
      return '';
  }
}
