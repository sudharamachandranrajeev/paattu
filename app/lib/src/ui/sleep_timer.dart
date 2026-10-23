// The sleep timer's button and sheet: pick a while, or the end of this song,
// and Paattu quiets down and pauses when it is up (player/sleep_timer.dart).

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../player/sleep_timer.dart';
import '../util.dart';

/// The dome's sleep-timer button: a moon, lit while a timer is running.
class SleepTimerButton extends StatelessWidget {
  const SleepTimerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Paattu.of(context).player;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: player.sleep,
      builder: (context, _) => _Ticking(builder: (context) {
        final sleep = player.sleep;
        final left = sleep.remaining;
        return IconButton(
          tooltip: !sleep.on
              ? 'Sleep timer'
              : sleep.endOfSong
                  ? 'Sleep timer: stops at the end of this song'
                  : 'Sleep timer: ${describeSleep(left)}',
          icon: Icon(sleep.on ? Icons.bedtime : Icons.bedtime_outlined,
              color: sleep.on ? scheme.primary : null),
          onPressed: () => showSleepTimer(context),
        );
      }),
    );
  }
}

/// Rebuilds once a second, so a countdown on screen moves.
class _Ticking extends StatefulWidget {
  const _Ticking({required this.builder});
  final WidgetBuilder builder;

  @override
  State<_Ticking> createState() => _TickingState();
}

class _TickingState extends State<_Ticking> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// The sheet: how long to play for, or stop at the end of this song.
Future<void> showSleepTimer(BuildContext context) {
  final app = Paattu.of(context);
  final sleep = app.player.sleep;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) {
      void pick(Duration? duration, {bool endOfSong = false}) {
        if (endOfSong) {
          sleep.startAtEndOfSong();
          app.toast('Paattu stops at the end of this song');
        } else if (duration == null) {
          sleep.cancel();
          app.toast('Sleep timer off');
        } else {
          sleep.start(duration);
          app.toast('Paattu stops in ${describeSleep(duration)}');
        }
        Navigator.pop(sheet);
      }

      return SafeArea(
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: sleep,
            builder: (context, _) => _Ticking(builder: (context) {
              final on = sleep.on;
              final left = sleep.remaining;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('Sleep timer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  if (on)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          Icon(sleep.endOfSong ? Icons.music_note : Icons.bedtime,
                              color: Theme.of(sheet).colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              sleep.endOfSong
                                  ? 'Stops at the end of this song'
                                  : '${describeSleep(left)} · ${_clockAt(left)}',
                              style: Theme.of(sheet).textTheme.bodyLarge,
                            ),
                          ),
                          if (!sleep.endOfSong)
                            TextButton(
                              onPressed: () => sleep.extend(const Duration(minutes: 5)),
                              child: const Text('+5 min'),
                            ),
                          TextButton(
                            onPressed: () => pick(null),
                            child: const Text('Turn off'),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.music_note),
                    title: const Text('End of this song'),
                    subtitle: const Text("Stops when the song playing finishes"),
                    trailing: sleep.endOfSong ? const Icon(Icons.check) : null,
                    onTap: () => pick(null, endOfSong: true),
                  ),
                  for (final minutes in sleepPresets)
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(plural(minutes, 'minute')),
                      trailing: !sleep.endOfSong && left != null && _closeTo(left, minutes)
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => pick(Duration(minutes: minutes)),
                    ),
                ],
              );
            }),
          ),
        ),
      );
    },
  );
}

/// Whether [left] is still that preset (it counts down from it).
bool _closeTo(Duration left, int minutes) =>
    left.inSeconds > (minutes - 1) * 60 && left.inSeconds <= minutes * 60;

/// The clock time it stops at, as the phone shows it ("11:42 pm").
String _clockAt(Duration? left) {
  if (left == null) return '';
  final at = DateTime.now().add(left);
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return '$hour:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'am' : 'pm'}';
}
