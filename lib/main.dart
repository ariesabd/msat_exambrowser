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
import 'package:screen_protector/screen_protector.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      fullScreen: true,
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: true, // Sembunyikan dari taskbar
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: true,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setFullScreen(true);
      await windowManager.setResizable(false);
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
  
  // Security Layer
  double? initialAspectRatio;
  bool isViolationReported = false;
  final String secureToken = 'TVNBVC1FWEFNLVNFQ1VSRS0yMDI2';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    ScreenProtector.preventScreenshotOn(); // Aktifkan blokir screenshot & rekam layar
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
  void didChangeMetrics() {
    super.didChangeMetrics();
    _checkSplitScreen();
  }

  void _checkSplitScreen() {
    if (!isUrlSet || isViolationReported) return;

    final double currentAspectRatio =
        WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.aspectRatio;

    if (initialAspectRatio == null) {
      initialAspectRatio = currentAspectRatio;
      return;
    }

    // Jika rasio berubah lebih dari 15%, anggap sebagai split screen
    if ((currentAspectRatio - initialAspectRatio!).abs() > 0.15) {
      _reportViolation("Layar terbagi (Split Screen)");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _checkSplitScreen(); // Re-check on resume
    }
    if (state == AppLifecycleState.paused && isUrlSet) {
      _reportViolation("Aplikasi ditinggalkan (Home/Recent)");
    }
  }

  void _reportViolation(String reason) {
    if (isViolationReported) return;
    isViolationReported = true;

    // Play Alert Sound
    audioPlayer.play(AssetSource('alert.mp3'), volume: 1.0);

    // 1. Laporan Langsung via HTTP (Paling Ampuh & Anti-Freeze)
    _reportViolationDirect(reason);

    // 2. Laporan via WebView (Jika masih aktif)
    webViewController?.evaluateJavascript(
      source: "if(typeof reportViolation === 'function') { reportViolation('$reason'); }"
    );

    // 3. UI Feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("PELANGGARAN: $reason"),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
    
    // Reset flag after 5 seconds to allow reporting again if needed (or keep true to block)
    Future.delayed(const Duration(seconds: 5), () => isViolationReported = false);
  }

  Future<void> _reportViolationDirect(String reason) async {
    try {
      final String reportUrl = "${currentUrl.endsWith('/') ? currentUrl : '$currentUrl/'}student/exam/report_violation_api";
      
      await http.post(
        Uri.parse(reportUrl),
        headers: {
          'X-MSAT-Auth-Token': secureToken,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'reason': reason,
          'url': currentUrl,
        },
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint("Direct report failed: $e");
    }
  }

  void _showExitDialog({bool isReset = false}) {
    final TextEditingController _passController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: isReset ? Colors.amber.withOpacity(0.1) : Colors.indigoAccent.withOpacity(0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        isReset ? Icons.settings_backup_restore_rounded : Icons.lock_person_rounded,
                        color: isReset ? Colors.amber : Colors.indigoAccent,
                        size: 40,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isReset ? 'RESET KONFIGURASI' : 'OTORITAS PROKTOR',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  children: [
                    Text(
                      isReset ? 'Masukkan PIN untuk mengganti link ujian:' : 'Masukkan PIN untuk menutup aplikasi:',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passController,
                      obscureText: true,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 10),
                      decoration: InputDecoration(
                        hintText: "••••",
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.1)),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.3),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.indigoAccent, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('BATAL', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('PIN Salah!'), backgroundColor: Colors.redAccent),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isReset ? Colors.amber : Colors.indigoAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            child: Text(isReset ? 'RESET' : 'KELUAR', style: const TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
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
        // Tombol back dimatikan total agar siswa tidak terganggu
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
                      initialUrlRequest: URLRequest(
                        url: WebUri(currentUrl),
                        headers: {'X-MSAT-Auth-Token': secureToken},
                      ),
                      initialSettings: InAppWebViewSettings(
                        userAgent: customUserAgent,
                        useShouldOverrideUrlLoading: false,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        cacheEnabled: true, // Ubah ke true agar session lebih stabil
                        clearCache: false, // Jangan hapus cache tiap reload agar login awet
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        databaseEnabled: true,
                        transparentBackground: true,
                        disableContextMenu: true, // Matikan klik kanan
                        supportZoom: false, // Matikan zoom manual
                      ),
                      onWebViewCreated: (controller) => webViewController = controller,
                      onLoadStart: (controller, url) {
                        debugPrint("Navigating to: $url");
                        setState(() {
                          isLoading = true;
                          isError = false;
                        });
                      },
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
                      onLoadStop: (controller, url) {
                        // Simpan rasio layar awal untuk deteksi split screen
                        initialAspectRatio ??= WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.aspectRatio;
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
