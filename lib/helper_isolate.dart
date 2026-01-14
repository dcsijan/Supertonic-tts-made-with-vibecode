import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

class IsolateRequest {
  final String text;
  final String lang;
  final int steps;
  final double speed;
  final Map<String, dynamic> cfgs;
  final Map<String, dynamic> voiceJson;
  final Map<String, String> modelPaths;

  IsolateRequest({
    required this.text,
    required this.lang,
    required this.steps,
    required this.speed,
    required this.cfgs,
    required this.voiceJson,
    required this.modelPaths,
  });
}

Future<Map<String, dynamic>> ttsIsolate(IsolateRequest req) async {
  final ort = OnnxRuntime();

  final opts = OrtSessionOptions(
    providers: [OrtProvider.NNAPI, OrtProvider.CPU],
  );

  final dp = await ort.createSession(req.modelPaths['dp']!, options: opts);
  final enc = await ort.createSession(req.modelPaths['enc']!, options: opts);
  final vec = await ort.createSession(req.modelPaths['vec']!, options: opts);
  final voc = await ort.createSession(req.modelPaths['voc']!, options: opts);

  // 🔹 Minimal example (skeleton)
  // Your full inference logic goes here (same math, no rootBundle)

  final sampleRate = req.cfgs['ae']['sample_rate'];

  // Dummy sine (replace with full pipeline)
  final len = sampleRate * 2;
  final audio = List<double>.generate(
    len,
    (i) => math.sin(2 * math.pi * 440 * i / sampleRate),
  );

  return {
    'wav': audio,
    'duration': [2.0],
  };
}
