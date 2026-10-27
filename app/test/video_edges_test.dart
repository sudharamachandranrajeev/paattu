// Video mode's card fades into the page at its edges with one mask, as it
// did with two (one each way).

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/ui/video_background.dart';

void main() {
  Shader fade(Rect rect, Axis axis, double edge) => LinearGradient(
        begin: axis == Axis.horizontal ? Alignment.centerLeft : Alignment.topCenter,
        end: axis == Axis.horizontal ? Alignment.centerRight : Alignment.bottomCenter,
        colors: const [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
        stops: [0, edge, 1 - edge, 1],
      ).createShader(rect);

  Future<List<int>> alphas(WidgetTester tester, Widget card) async {
    final key = GlobalKey();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(width: 400, height: 225, child: card),
        ),
      ),
    ));
    final out = <int>[];
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (var y = 0; y < 225; y += 7) {
        for (var x = 0; x < 400; x += 9) {
          out.add(bytes.getUint8((y * 400 + x) * 4 + 3));
        }
      }
    });
    return out;
  }

  testWidgets('one mask fades the edges as the two did', (tester) async {
    const red = ColoredBox(color: Colors.red);
    final two = await alphas(
      tester,
      ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => fade(rect, Axis.vertical, 0.12),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => fade(rect, Axis.horizontal, 0.08),
          child: red,
        ),
      ),
    );
    final one = await alphas(tester, const FloatingVideo(child: red));
    var worst = 0;
    for (var i = 0; i < one.length; i++) {
      worst = (one[i] - two[i]).abs() > worst ? (one[i] - two[i]).abs() : worst;
    }
    expect(worst, lessThanOrEqualTo(12));
    expect(one.reduce((a, b) => a > b ? a : b), 255);
  });
}
