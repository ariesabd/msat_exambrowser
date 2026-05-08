import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:kiosk_mode/kiosk_mode.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      fullScreen: true,
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setFullScreen(true);
      await windowManager.setPreventClose(true);
      await windowManager.setAlwaysOnTop(true);
    });
  }

  runApp(const MaterialApp(
    home: ExamBrowserFinal(),
    debugShowCheckedModeBanner: false,
  ));
}

class ExamBrowserFinal extends StatefulWidget {
  const ExamBrowserFinal({super.key});

  @override
  State<ExamBrowserFinal> createState() => _ExamBrowserFinalState();
}

class _ExamBrowserFinalState extends State<ExamBrowserFinal> with WidgetsBindingObserver, WindowListener {
  InAppWebViewController? webViewController;
  final String customUserAgent = "MSAT-ExamBrowser-V1";
  final String exitPassword = "1111";
  
  final AudioPlayer audioPlayer = AudioPlayer();
  final TextEditingController _urlController = TextEditingController();
  
  bool isUrlSet = false;
  String currentUrl = "";
  bool isLoading = true;
  bool isError = false;
  double progress = 0;
  String errorMsg = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _setupExamEnvironment();
    _checkSavedUrl();
  }

  @override
  void onWindowBlur() {
    if (isUrlSet) {
      _reportViolation("Aplikasi kehilangan fokus (Alt+Tab/Win Key)");
    }
  }

  Future<void> _checkSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('exam_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      setState(() {
        currentUrl = savedUrl;
        isUrlSet = true;
      });
    }
    setState(() => isLoading = false);
  }

  Future<void> _saveAndOpenUrl(String url) async {
    if (url.isEmpty) return;
    
    setState(() => isLoading = true);

    // Auto-fix URL
    String formattedUrl = url.trim();
    if (!formattedUrl.startsWith('http')) {
      formattedUrl = 'https://' + formattedUrl;
    }
    if (!formattedUrl.endsWith('/')) {
      formattedUrl = formattedUrl + '/';
    }

    try {
      final response = await http.get(Uri.parse(formattedUrl + "student/exam/verify-id?id=CHECK")).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('exam_url', formattedUrl);
        
        setState(() {
          currentUrl = formattedUrl;
          isUrlSet = true;
          isLoading = true;
          isError = false;
        });
      } else {
        throw "Bukan Server MSAT";
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        isError = true;
        errorMsg = "URL Tidak Valid atau Bukan Server MSAT!";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: URL tidak valid atau server tidak merespon!'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _resetUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('exam_url');
    setState(() {
      isUrlSet = false;
      currentUrl = "";
      isLoading = false;
    });
  }

  Future<void> _setupExamEnvironment() async {
    try {
      await WakelockPlus.enable();
      if (!Platform.isWindows) {
        await startKioskMode();
      }
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await InAppWebViewController.clearAllCache();

      final session = await audio_session.AudioSession.instance;
      await session.configure(const audio_session.AudioSessionConfiguration(
        avAudioSessionCategory: audio_session.AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: audio_session.AVAudioSessionCategoryOptions.defaultToSpeaker,
        androidAudioAttributes: audio_session.AndroidAudioAttributes(
          usage: audio_session.AndroidAudioUsage.alarm,
          contentType: audio_session.AndroidAudioContentType.sonification,
        ),
      ));
    } catch (e) {
      debugPrint("Setup error: $e");
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    if (!Platform.isWindows) {
      stopKioskMode();
    }
    audioPlayer.dispose();
    _urlController.dispose();
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && isUrlSet) {
      _reportViolation("Aplikasi ditinggalkan");
    }
  }

  void _reportViolation(String type) {
    audioPlayer.play(AssetSource('alert.mp3'), volume: 1.0);
    webViewController?.evaluateJavascript(
      source: "if(typeof reportViolation === 'function') { reportViolation('app_switch'); }"
    );
  }

  void _showExitDialog({bool isReset = false}) {
    final TextEditingController _passController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(isReset ? 'Reset Konfigurasi' : 'Otoritas Proktor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isReset ? 'Masukkan password untuk ganti link:' : 'Masukkan password untuk keluar:'),
            const SizedBox(height: 15),
            TextField(
              controller: _passController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'PIN Keamanan'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('BATAL')),
          ElevatedButton(
            onPressed: () {
              if (_passController.text == exitPassword) {
                Navigator.pop(context);
                if (isReset) {
                  _resetUrl();
                } else {
                  if (Platform.isWindows) {
                    exit(0);
                  } else {
                    stopKioskMode().then((_) => SystemNavigator.pop());
                  }
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password Salah!')));
              }
            },
            child: Text(isReset ? 'OK' : 'KELUAR'),
          ),
        ],
      ),
    );
  }

  void _openScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text("Scan QR Link Ujian")),
          body: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  Navigator.pop(context);
                  _saveAndOpenUrl(barcode.rawValue!);
                  break;
                }
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading && !isUrlSet) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!isUrlSet) return _buildSetupScreen();
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showExitDialog();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              if (isLoading || progress < 1.0)
                LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  backgroundColor: Colors.grey[900],
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigoAccent),
                ),
              Expanded(
                child: Stack(
                  children: [
                    InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(currentUrl)),
                      initialSettings: InAppWebViewSettings(
                        userAgent: customUserAgent,
                        useShouldOverrideUrlLoading: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        cacheEnabled: false,
                        clearCache: true,
                      ),
                      onWebViewCreated: (controller) => webViewController = controller,
                      onProgressChanged: (controller, p) {
                        setState(() {
                          progress = p / 100;
                          if (progress == 1.0) isLoading = false;
                        });
                      },
                      onLoadError: (controller, url, code, message) {
                        setState(() {
                          isError = true;
                          errorMsg = "Gagal memuat halaman ujian.";
                        });
                      },
                    ),
                    if (isError) _buildErrorView(),
                  ],
                ),
              ),
              // Bottom Bar Navigation
              Container(
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1B4B),
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Digital Clock
                    StreamBuilder(
                      stream: Stream.periodic(const Duration(seconds: 1)),
                      builder: (context, snapshot) {
                        final now = DateTime.now();
                        return Text(
                          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}",
                          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'monospace'),
                        );
                      },
                    ),
                    
                    // Center Branding (Static)
                    Row(
                      children: [
                        Image.asset('assets/logo.png', height: 24, errorBuilder: (_,__,___) => const Icon(Icons.school, color: Colors.white, size: 20)),
                        const SizedBox(width: 10),
                        const Text("MSAT XAMBRO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
                      ],
                    ),

                    // Exit Button
                    IconButton(
                      icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 26),
                      onPressed: () => _showExitDialog(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetupScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  icon: const Icon(Icons.power_settings_new_rounded, color: Colors.white24, size: 28),
                  onPressed: _showExitDialog,
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(35),
                          boxShadow: [
                            BoxShadow(color: Colors.indigo.withOpacity(0.2), blurRadius: 30, spreadRadius: 5)
                          ]
                        ),
                        child: Image.asset('assets/logo.png', height: 100, errorBuilder: (_,__,___) => const Icon(Icons.school, size: 100, color: Colors.white)),
                      ),
                      const SizedBox(height: 40),
                      const Text("MSAT XAMBRO", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4)),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                        decoration: BoxDecoration(color: Colors.indigoAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                        child: const Text("SMART EXAM SOLUTION", style: TextStyle(color: Colors.indigoAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                      ),
                      const SizedBox(height: 50),
                      Container(
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Column(
                          children: [
                            const Text("KONFIGURASI UJIAN", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                            const SizedBox(height: 25),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _openScanner,
                                icon: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 24),
                                label: const Text("SCAN QR CODE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigoAccent,
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  elevation: 10,
                                  shadowColor: Colors.indigoAccent.withOpacity(0.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 25),
                            Row(
                              children: [
                                Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 15),
                                  child: Text("ATAU", style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                                Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                              ],
                            ),
                            const SizedBox(height: 25),
                            TextField(
                              controller: _urlController,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                hintText: "Ketik Link Ujian Manual...",
                                hintStyle: const TextStyle(color: Colors.white24, fontWeight: FontWeight.normal),
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.3),
                                prefixIcon: const Icon(Icons.link, color: Colors.white30),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.indigoAccent, width: 2)),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.send_rounded, color: Colors.indigoAccent),
                                  onPressed: () => _saveAndOpenUrl(_urlController.text),
                                ),
                              ),
                              onSubmitted: (val) => _saveAndOpenUrl(val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt_rounded, color: Colors.amber, size: 18),
                            SizedBox(width: 10),
                            Text(
                              "Pastikan Internet & Baterai Stabil",
                              style: TextStyle(color: Colors.white30, fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 80, color: Colors.red),
            const SizedBox(height: 20),
            const Text("Gagal Memuat Halaman", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(currentUrl, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => setState(() => isError = false),
              child: const Text("Coba Lagi"),
            ),
            TextButton(
              onPressed: () => _showExitDialog(isReset: true),
              child: const Text("Ganti Link", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}
