import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:kiosk_mode/kiosk_mode.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:audio_session/audio_session.dart' as audio_session;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Anti-Screenshot sudah dipindah ke sistem Android langsung
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

class _ExamBrowserFinalState extends State<ExamBrowserFinal> with WidgetsBindingObserver {
  InAppWebViewController? webViewController;
  final String customUserAgent = "MSAT-ExamBrowser-V1";
  final String exitPassword = "1111";
  
  // URL Pusat untuk mengecek ID (Discovery Server)
  final String discoveryBaseUrl = "https://mgmp.anbk.my.id/";

  final AudioPlayer audioPlayer = AudioPlayer();
  bool isVerified = false;
  bool isLoading = false;
  bool isError = false;
  double progress = 0;
  String errorMsg = "";
  String? targetUrl;
  final TextEditingController _idController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupExamEnvironment();
  }

  Future<void> _setupExamEnvironment() async {
    try {
      await WakelockPlus.enable();
      await startKioskMode();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      
      // Clear cache on startup for security
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

  Future<void> _verifyExamId(String id) async {
    if (id.isEmpty) return;

    setState(() {
      isLoading = true;
      isError = false;
    });

    try {
      final response = await http.get(
        Uri.parse("${discoveryBaseUrl}student/exam/verify-id?id=$id"),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            targetUrl = data['url'];
            isVerified = true;
            isLoading = false;
          });
        } else {
          setState(() {
            isError = true;
            errorMsg = data['message'] ?? "ID tidak valid.";
            isLoading = false;
          });
        }
      } else {
        throw Exception("Gagal terhubung ke server verifikasi.");
      }
    } catch (e) {
      setState(() {
        isError = true;
        errorMsg = "Koneksi Gagal: Pastikan Anda terhubung ke internet.";
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    stopKioskMode();
    audioPlayer.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _reportViolation("Aplikasi ditinggalkan");
    }
  }

  Future<void> _playAlertSound() async {
    try {
      await audioPlayer.play(AssetSource('alert.mp3'), volume: 1.0);
    } catch (e) {
      debugPrint("Sound error: $e");
    }
  }

  void _reportViolation(String type) {
    _playAlertSound();
    webViewController?.evaluateJavascript(
      source: "if(typeof reportViolation === 'function') { reportViolation('app_switch'); } else { console.log('Violation: $type'); }"
    );
  }

  void _showExitDialog() {
    final TextEditingController _passController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('Otoritas Proktor', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Masukkan password untuk keluar:', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 15),
            TextField(
              controller: _passController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'PIN Keamanan',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('BATAL')),
          ElevatedButton(
            onPressed: () {
              if (_passController.text == exitPassword) {
                stopKioskMode().then((_) => SystemNavigator.pop());
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password Salah!')));
              }
            },
            child: const Text('KELUAR'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isVerified) return _buildDiscoveryScreen();
    
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
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigo),
                ),
              Expanded(
                child: Stack(
                  children: [
                    InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(targetUrl!)),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 80, color: Colors.red),
            const SizedBox(height: 20),
            const Text("Koneksi Bermasalah", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(errorMsg, textAlign: TextAlign.center),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  isError = false;
                  isLoading = true;
                });
                webViewController?.reload();
              },
              child: const Text("Coba Lagi"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryScreen() {
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
              // Tombol Keluar Tersembunyi tapi jelas
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  icon: const Icon(Icons.power_settings_new_rounded, color: Colors.white24, size: 28),
                  onPressed: _showExitDialog,
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 60),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Image.asset('assets/logo.png', height: 80, errorBuilder: (_, __, ___) => const Icon(Icons.school, size: 80, color: Colors.white)),
                      ),
                      const SizedBox(height: 30),
                      const Text("XAMBRO", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 5)),
                      const Text("MSAT EXAM BROWSER", style: TextStyle(color: Colors.indigoAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                      const SizedBox(height: 40),
                      
                      // Input Card
                      Container(
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(
                          color: Colors.white, 
                          borderRadius: BorderRadius.circular(35),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))
                          ]
                        ),
                        child: Column(
                          children: [
                            const Text("MASUKKAN ID UJIAN", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
                            const SizedBox(height: 15),
                            TextField(
                              controller: _idController,
                              textAlign: TextAlign.center,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 8, color: Color(0xFF1E293B)),
                              decoration: InputDecoration(
                                hintText: "", 
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (isError) Text(errorMsg, style: const TextStyle(color: Colors.red, fontSize: 12), textAlign: TextAlign.center),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: isLoading ? null : () => _verifyExamId(_idController.text),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5), 
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                                ),
                                child: isLoading
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                                    : const Text("MULAI UJIAN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.black)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 30),
                      
                      // Kesiapan Perangkat Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.indigoAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: Colors.indigoAccent.withOpacity(0.2))
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.indigoAccent, size: 24),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossorigin: CrossAxisAlignment.start,
                                children: [
                                  Text("Kesiapan Perangkat:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Pastikan koneksi internet stabil dan baterai perangkat Anda mencukupi selama ujian berlangsung.",
                                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
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
}
