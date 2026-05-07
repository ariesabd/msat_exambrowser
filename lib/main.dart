import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:kiosk_mode/kiosk_mode.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:audio_session/audio_session.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
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
  
  // --- CARA GANTI LINK ---
  // Ganti link di bawah ini jika alamat web ujian Anda berubah, 
  // lalu build ulang APK-nya.
  final String currentUrl = "https://mgmp.anbk.my.id/";
  // -----------------------

  final String customUserAgent = "MSAT-ExamBrowser-V1";
  final String exitPassword = "1111";

  final AudioPlayer audioPlayer = AudioPlayer();
  bool isLoading = true;
  bool isError = false;
  double progress = 0;
  String errorMsg = "";

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

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
        androidAudioAttributes: AndroidAudioAttributes(
          usage: AndroidAudioUsage.alarm,
          contentType: AndroidAudioContentType.sonification,
        ),
      ));
    } catch (e) {
      debugPrint("Setup error: $e");
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
        title: Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.indigo.shade800),
            const SizedBox(width: 10),
            const Text('Otoritas Proktor', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Masukkan password untuk menutup ujian:', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 15),
            TextField(
              controller: _passController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.password),
                hintText: 'PIN Keamanan',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: Text('BATAL', style: TextStyle(color: Colors.grey.shade600))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade800,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (_passController.text == exitPassword) {
                stopKioskMode().then((_) => SystemNavigator.pop());
              } else {
                HapticFeedback.vibrate();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password Salah!'), backgroundColor: Colors.redAccent)
                );
              }
            },
            child: const Text('KELUAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 80, color: Colors.indigo.shade200),
            const SizedBox(height: 20),
            const Text("Koneksi Bermasalah", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(errorMsg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  isError = false;
                  isLoading = true;
                });
                _fetchTargetUrl();
              },
              icon: const Icon(Icons.refresh),
              label: const Text("COBA LAGI"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _showExitDialog();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              if (currentUrl.isNotEmpty && !isError)
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(currentUrl)),
                  initialSettings: InAppWebViewSettings(
                    userAgent: customUserAgent,
                    disableContextMenu: true,
                    supportZoom: false,
                    overScrollMode: OverScrollMode.NEVER,
                    useOnLoadResource: true,
                    javaScriptEnabled: true,
                    allowsInlineMediaPlayback: true,
                  ),
                  onWebViewCreated: (controller) => webViewController = controller,
                  onLoadStart: (controller, url) => setState(() => isLoading = true),
                  onLoadStop: (controller, url) => setState(() => isLoading = false),
                  onProgressChanged: (controller, p) => setState(() => progress = p / 100),
                  onReceivedError: (controller, request, error) {
                    setState(() {
                      isError = true;
                      errorMsg = "Gagal memuat halaman: ${error.description}";
                    });
                  },
                ),
              
              if (isError) _buildErrorView(),

              if (isLoading && !isError)
                Container(
                  color: Colors.white,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset('assets/logo.png', height: 100, errorBuilder: (_, __, ___) => const Icon(Icons.school, size: 100, color: Colors.indigo)),
                        const SizedBox(height: 30),
                        const SizedBox(
                          width: 200,
                          child: LinearProgressIndicator(
                            backgroundColor: Color(0xFFEEEEEE),
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
                          ),
                        ),
                        const SizedBox(height: 15),
                        const Text("Menyiapkan Ruang Ujian...", style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1.2)),
                      ],
                    ),
                  ),
                ),
              
              // Progress bar tipis di bagian paling atas
              if (isLoading && progress > 0 && progress < 1.0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                ),

              // Tombol Keluar Tersembunyi
              Positioned(
                top: 5,
                right: 5,
                child: Opacity(
                  opacity: 0.05,
                  child: IconButton(
                    icon: const Icon(Icons.close_fullscreen, size: 20),
                    onPressed: _showExitDialog,
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
