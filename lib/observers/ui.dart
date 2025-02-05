import 'dart:async';
import 'dart:ui';

import 'package:easy_debounce/easy_debounce.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:frontobs_core/log_vault.dart';
import 'package:frontobs_core/monitoring_entries.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

class ScrollDetector extends StatefulWidget {
  ScrollDetector({
    required this.child,
    this.identification,
    this.payload,
    this.scope = "Общий скрол",
  }) {
    if (identification == null) {
      identification = Trace.current(1)
          .frames
          .firstOrNull
          ?.member
          ?.replaceAll(".build.<fn>", "");
    }
  }

  final Widget child;
  final String scope;
  String? identification;
  final Map<String, dynamic>? payload;

  @override
  State<ScrollDetector> createState() => _ScrollDetectorState();
}

class _ScrollDetectorState extends State<ScrollDetector> {
  double startExtent = 0.0;

  bool debouncing = false;

  final id = Uuid().v1();

  @override
  Widget build(BuildContext context) {
    return NotificationListener(
        onNotification: (notification) {
          if (notification is ScrollNotification) {
            if (!debouncing) {
              startExtent = notification.metrics.extentBefore;
              debouncing = true;
            }
            EasyDebounce.debounce(
                '____scroll_debouncer_$id',
                // <-- An ID for this particular debouncer
                Duration(seconds: 1), // <-- The debounce duration
                () {
              debouncing = false;
              final offsetStart =
                  startExtent / notification.metrics.extentTotal;
              final offsetCurrent = notification.metrics.extentBefore /
                  notification.metrics.extentTotal;
              final viewport = notification.metrics.extentInside /
                  notification.metrics.extentTotal;

              LogVault.addEntry(MonitoringEntry(
                scope: widget.scope,
                kind: "Скролл",
                severity: "Отладка",
                identification: widget.identification ?? "Без идентификации",
                payload: {
                  "Начало экрана": offsetCurrent == 0,
                  "Конец экрана": offsetCurrent + viewport == 1,
                  "Предыдущий отступ": offsetStart,
                  "Нынешний отступ": offsetCurrent,
                  "Процент видимого экрана": viewport,
                  if (widget.payload != null) ...widget.payload!,
                },
                logTimestamp: DateTime.now(),
              ));

              EasyDebounce.cancel("____scroll_debouncer_$id");
            } // <-- The target method
                );
            /*print(
                "SCROLL ${notification.metrics.extentBefore / notification.metrics.extentTotal}"
                " ${notification.metrics.extentInside / notification.metrics.extentTotal}"
                " ${notification.metrics.extentTotal / notification.metrics.extentTotal}");*/
          }
          return false;
        },
        child: widget.child);
  }
}

class TapDetector extends StatelessWidget {
  TapDetector({
    required this.child,
    this.identification,
    this.scope = "Общие нажатия",
    this.payload,
  }) {
    if (identification == null) {
      identification =
          Trace.current(1).frames.first.member?.replaceAll(".build.<fn>", "");
    }
  }

  final Widget child;
  final String scope;
  final String? payload;
  String? identification;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) {
        LogVault.addEntry(MonitoringEntry(
          scope: scope,
          kind: "Нажатие",
          identification: identification ?? "Без индентификации",
          severity: "Отладка",
          payload: {
            "Координата Х": details.globalPosition.dx,
            "Координата Y": details.globalPosition.dy,
          },
          logTimestamp: DateTime.now(),
        ));
      },
      child: child,
    );
  }
}

class ScreenRecorder extends StatefulWidget {
  const ScreenRecorder({
    super.key,
    required this.child,
    required this.controller,
  });

  final Widget child;
  final ScreenRecorderController controller;

  @override
  State<ScreenRecorder> createState() => controller;
}

class ScreenRecorderController extends State<ScreenRecorder> {
  final key = GlobalKey();

  Future<Uint8List?> captureScreen() async {
    final c = Completer();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      c.complete();
    });
    await c.future;

    if (key.currentContext == null) {
      print("[OBERON] Screenshot not awailable");
      return null;
    }
    final rObj =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final imageRaw =
        await rObj.toImage(pixelRatio: View.of(context).devicePixelRatio / 6);
    final bytes = await imageRaw.toByteData(format: ImageByteFormat.png);
    return Uint8List.view(bytes!.buffer);
    // return img.Image.fromBytes(
    //     width: imageRaw.width, height: imageRaw.height, bytes: bytes!.buffer);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: key,
      child: widget.child,
    );
  }
}
