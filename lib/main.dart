import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'helper.dart';

void main() {
  runApp(const SupertonicApp());
}

class SupertonicApp extends StatelessWidget {
  const SupertonicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Supertonic 2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5CF6),
          brightness: Brightness.dark,
        ),
      ),
      home: const TTSPage(),
    );
  }
}

class TTSPage extends StatefulWidget {
  const TTSPage({super.key});

  @override
  State<TTSPage> createState() => _TTSPageState();
}

class _TTSPageState extends State<TTSPage> {
  final TextEditingController _textController = TextEditingController(
    text: 'Hello, this is a text to speech example.',
  );

  final AudioPlayer _audioPlayer = AudioPlayer();

  TextToSpeech? _textToSpeech;
  Style? _style;

  bool _isLoading = false;
  bool _isGenerating = false;
  bool _isPlaying = false;

  String _status = 'Not initialized';

  int _totalSteps = 5;
  double _speed = 1.05;
  String _selectedLang = 'en';

  // ✅ Progress
  double _progress = 0.0;
  String _progressLabel = '';

  // ✅ Voice selector
  // Add your styles here (must exist in assets/voice_styles/)
  final Map<String, String> _voiceStyles = const {
    'M1 (Default)': 'assets/voice_styles/M1.json',
    // Uncomment / add if you have these files:
    // 'F1': 'assets/voice_styles/F1.json',
    // 'M2': 'assets/voice_styles/M2.json',
    // 'Soft': 'assets/voice_styles/Soft.json',
  };
  late String _selectedVoiceName;

  String? _lastGeneratedFilePath;

  @override
  void initState() {
    super.initState();
    _selectedVoiceName = _voiceStyles.keys.first;
    _setupAudioPlayerListeners();
    _loadModels();
  }

  void _setupAudioPlayerListeners() {
    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;

      setState(() {
        _isPlaying = state.playing;

        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          _status = 'Ready';
        } else if (state.processingState == ProcessingState.loading) {
          _status = 'Loading audio...';
        } else if (state.processingState == ProcessingState.buffering) {
          _status = 'Buffering...';
        }
      });
    });
  }

  Future<void> _loadModels() async {
    setState(() {
      _isLoading = true;
      _status = 'Loading models...';
      _progress = 0;
      _progressLabel = '';
    });

    try {
      _textToSpeech = await loadTextToSpeech('assets/onnx', useGpu: false);

      final voicePath = _voiceStyles[_selectedVoiceName]!;
      _style = await loadVoiceStyle([voicePath]);

      setState(() {
        _isLoading = false;
        _status = 'Ready (Voice: $_selectedVoiceName)';
      });
    } catch (e, stackTrace) {
      logger.e('Error loading models', error: e, stackTrace: stackTrace);
      setState(() {
        _isLoading = false;
        _status = 'Error: $e';
      });
    }
  }

  Future<void> _changeVoice(String voiceName) async {
    if (_isLoading || _isGenerating) return;

    setState(() {
      _selectedVoiceName = voiceName;
      _isLoading = true;
      _status = 'Loading voice: $voiceName...';
    });

    try {
      final voicePath = _voiceStyles[voiceName]!;
      _style = await loadVoiceStyle([voicePath]);

      setState(() {
        _isLoading = false;
        _status = 'Ready (Voice: $voiceName)';
      });
    } catch (e, stackTrace) {
      logger.e('Error loading voice style', error: e, stackTrace: stackTrace);
      setState(() {
        _isLoading = false;
        _status = 'Error loading voice: $e';
      });
    }
  }

  Future<void> _generateSpeech() async {
    if (_textToSpeech == null || _style == null) {
      setState(() => _status = 'Models not loaded yet');
      return;
    }

    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _status = 'Please enter some text');
      return;
    }

    setState(() {
      _isGenerating = true;
      _progress = 0.0;
      _progressLabel = 'Starting...';
      _status = 'Generating speech ($_selectedVoiceName)...';
    });

    List<double>? wav;
    List<double>? duration;

    try {
      final result = await _textToSpeech!.call(
        text,
        _selectedLang,
        _style!,
        _totalSteps,
        speed: _speed,
        onProgress: (p, msg) {
          if (!mounted) return;
          setState(() {
            _progress = p.clamp(0.0, 1.0);
            _progressLabel = msg;
          });
        },
      );

      wav = (result['wav'] as List).cast<double>();
      duration = (result['duration'] as List).cast<double>();
    } catch (e) {
      logger.e('Error generating speech', error: e);
      setState(() {
        _isGenerating = false;
        _status = 'Error generating speech: $e';
      });
      return;
    }

    try {
      setState(() {
        _progress = 0.95;
        _progressLabel = 'Saving WAV...';
      });

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/speech_$timestamp.wav';

      writeWavFile(outputPath, wav!, _textToSpeech!.sampleRate);

      final file = File(outputPath);
      if (!file.existsSync()) throw Exception('Failed to create WAV file');

      final absolutePath = file.absolute.path;

      setState(() {
        _isGenerating = false;
        _progress = 1.0;
        _progressLabel = 'Done';
        _status = 'Playing ${duration![0].toStringAsFixed(2)}s ($_selectedVoiceName)...';
        _lastGeneratedFilePath = absolutePath;
      });

      await _audioPlayer.setAudioSource(AudioSource.uri(Uri.file(absolutePath)));
      await _audioPlayer.play();
    } catch (e) {
      logger.e('Error playing audio', error: e);
      setState(() {
        _isGenerating = false;
        _status = 'Error playing audio: $e';
      });
    }
  }

  Future<void> _downloadFile() async {
    if (_lastGeneratedFilePath == null) return;

    try {
      final sourceFile = File(_lastGeneratedFilePath!);
      if (!sourceFile.existsSync()) {
        setState(() => _status = 'Error: File no longer exists');
        return;
      }

      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        setState(() => _status = 'Error: Could not access downloads folder');
        return;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final downloadPath = '${downloadsDir.path}/speech_$timestamp.wav';

      await sourceFile.copy(downloadPath);
      logger.i('File saved to $downloadPath');

      setState(() => _status = 'File saved to: $downloadPath');
    } catch (e) {
      logger.e('Error downloading file', error: e);
      setState(() => _status = 'Error downloading file: $e');
    }
  }

  Color _statusTint() {
    if (_isLoading || _isGenerating) return const Color(0xFFFFB020);
    if (_status.startsWith('Error')) return const Color(0xFFFF4D6D);
    return const Color(0xFF34D399);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isLoading || _isGenerating;

    return Scaffold(
      body: Stack(
        children: [
          const _GlassBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GlassCard(
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF8B5CF6).withOpacity(0.95),
                                const Color(0xFF06B6D4).withOpacity(0.85),
                              ],
                            ),
                          ),
                          child: const Icon(Icons.graphic_eq, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Supertonic 2',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Voice: $_selectedVoiceName',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: busy ? null : _loadModels,
                          icon: Icon(Icons.refresh, color: Colors.white.withOpacity(0.85)),
                          tooltip: 'Reload models',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  _GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            _PulseDot(color: _statusTint(), active: busy),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _status,
                                style: const TextStyle(fontSize: 14.5, height: 1.2),
                              ),
                            ),
                            if (busy)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),

                        // ✅ Progress bar when generating
                        if (_isGenerating) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: _progress,
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${(_progress * 100).toStringAsFixed(0)}% • $_progressLabel',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Voice',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white.withOpacity(0.85),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _GlassDropdownAny<String>(
                                      value: _selectedVoiceName,
                                      enabled: !busy,
                                      items: _voiceStyles.keys
                                          .map((name) => DropdownMenuItem(
                                                value: name,
                                                child: Text(name),
                                              ))
                                          .toList(),
                                      onChanged: (v) => _changeVoice(v),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              const Text(
                                'Text',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 10),
                              _GlassInput(controller: _textController, enabled: !busy),

                              const SizedBox(height: 14),

                              _GlassSlider(
                                title: 'Denoising Steps',
                                valueText: '$_totalSteps',
                                min: 1,
                                max: 20,
                                value: _totalSteps.toDouble(),
                                divisions: 19,
                                enabled: !busy,
                                onChanged: (v) => setState(() => _totalSteps = v.toInt()),
                              ),
                              const SizedBox(height: 10),
                              _GlassSlider(
                                title: 'Speed',
                                valueText: _speed.toStringAsFixed(2),
                                min: 0.5,
                                max: 2.0,
                                value: _speed,
                                divisions: 30,
                                enabled: !busy,
                                onChanged: (v) => setState(() => _speed = v),
                              ),

                              const SizedBox(height: 12),

                              Row(
                                children: [
                                  Text(
                                    'Language',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white.withOpacity(0.85),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _GlassDropdownAny<String>(
                                      value: _selectedLang,
                                      enabled: !busy,
                                      items: const [
                                        DropdownMenuItem(value: 'en', child: Text('English')),
                                        DropdownMenuItem(value: 'ko', child: Text('한국어')),
                                        DropdownMenuItem(value: 'es', child: Text('Español')),
                                        DropdownMenuItem(value: 'pt', child: Text('Português')),
                                        DropdownMenuItem(value: 'fr', child: Text('Français')),
                                      ],
                                      onChanged: (v) => setState(() => _selectedLang = v),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        _GlassCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: _PrimaryGlassButton(
                                  icon: _isPlaying ? Icons.stop : Icons.play_arrow,
                                  label: _isPlaying ? 'Stop' : 'Generate',
                                  busy: _isGenerating,
                                  onPressed: busy
                                      ? null
                                      : _isPlaying
                                          ? () async {
                                              await _audioPlayer.stop();
                                              if (mounted) setState(() => _status = 'Ready');
                                            }
                                          : _generateSpeech,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _SecondaryGlassButton(
                                  icon: Icons.download,
                                  label: 'Save WAV',
                                  onPressed: (!busy && _lastGeneratedFilePath != null)
                                      ? _downloadFile
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (_lastGeneratedFilePath != null) ...[
                          const SizedBox(height: 14),
                          _GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Last file',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _lastGeneratedFilePath!,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.white.withOpacity(0.75),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}

/* ---------------- UI Widgets (glass) ---------------- */

class _GlassBackground extends StatelessWidget {
  const _GlassBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0B1020),
            Color(0xFF111A33),
            Color(0xFF0B1020),
          ],
        ),
      ),
      child: Stack(
        children: const [
          _GlowBlob(alignment: Alignment(-0.9, -0.9), color: Color(0xFF8B5CF6)),
          _GlowBlob(alignment: Alignment(0.9, -0.2), color: Color(0xFF22C55E)),
          _GlowBlob(alignment: Alignment(0.2, 0.95), color: Color(0xFF06B6D4)),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  const _GlowBlob({required this.alignment, required this.color});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.18),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withOpacity(0.08),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                spreadRadius: 1,
                offset: const Offset(0, 10),
                color: Colors.black.withOpacity(0.25),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassInput extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;

  const _GlassInput({required this.controller, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: TextField(
            controller: controller,
            maxLines: 5,
            enabled: enabled,
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              hintText: 'Enter text to synthesize...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassSlider extends StatelessWidget {
  final String title;
  final String valueText;
  final double min;
  final double max;
  final double value;
  final int? divisions;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _GlassSlider({
    required this.title,
    required this.valueText,
    required this.min,
    required this.max,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              valueText,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.75),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}

class _GlassDropdownAny<T> extends StatelessWidget {
  final T value;
  final bool enabled;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  const _GlassDropdownAny({
    required this.value,
    required this.enabled,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF0F1630),
              items: items,
              onChanged: enabled ? (v) => onChanged(v as T) : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryGlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const _PrimaryGlassButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF8B5CF6).withOpacity(0.95),
                const Color(0xFF06B6D4).withOpacity(0.85),
              ],
            ),
          ),
          child: Container(
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryGlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _SecondaryGlassButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          side: BorderSide(color: Colors.white.withOpacity(0.18)),
          foregroundColor: Colors.white.withOpacity(0.9),
        ),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  final Color color;
  final bool active;
  const _PulseDot({required this.color, required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(active ? 0.95 : 0.7),
        boxShadow: [
          BoxShadow(
            blurRadius: active ? 16 : 8,
            spreadRadius: 1,
            color: color.withOpacity(active ? 0.35 : 0.18),
          ),
        ],
      ),
    );
  }
}
