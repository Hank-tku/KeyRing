import 'package:flutter_test/flutter_test.dart';
import 'package:key_ring/services/background_lock_controller.dart';

void main() {
  testWidgets('locks at two minutes, repeated blur does not extend deadline', (
    tester,
  ) async {
    int locks = 0;
    final controller = BackgroundLockController(
      onLock: () => locks++,
      now: tester.binding.clock.now,
    );
    addTearDown(controller.dispose);
    controller.setForeground(false);
    await tester.pump(const Duration(seconds: 119));
    expect(locks, 0);
    controller.setForeground(false);
    await tester.pump(const Duration(seconds: 1));
    expect(locks, 1);
    await tester.pump(const Duration(minutes: 1));
    controller.setForeground(true);
    expect(locks, 1);
  });

  testWidgets(
    'brief switch retains session; next departure gets its own deadline',
    (tester) async {
      int locks = 0;
      final controller = BackgroundLockController(
        onLock: () => locks++,
        now: tester.binding.clock.now,
      );
      addTearDown(controller.dispose);
      controller.setForeground(false);
      await tester.pump(const Duration(seconds: 90));
      controller.setForeground(true);
      await tester.pump(const Duration(minutes: 5));
      expect(locks, 0);
      controller.setForeground(false);
      await tester.pump(const Duration(minutes: 2));
      expect(locks, 1);
    },
  );

  test(
    'resume checks elapsed wall time even when timer did not run during suspension',
    () {
      var now = DateTime.utc(2026);
      int locks = 0;
      final controller = BackgroundLockController(
        onLock: () => locks++,
        now: () => now,
      );
      addTearDown(controller.dispose);
      controller.setForeground(false);
      now = now.add(const Duration(minutes: 3));
      controller.setForeground(true);
      expect(locks, 1);
    },
  );

  testWidgets(
    'unlock in background starts a fresh deadline; disposal cancels timer',
    (tester) async {
      int locks = 0;
      final controller = BackgroundLockController(
        onLock: () => locks++,
        now: tester.binding.clock.now,
      );
      controller.setForeground(false);
      await tester.pump(const Duration(seconds: 100));
      controller.didUnlock();
      await tester.pump(const Duration(seconds: 119));
      expect(locks, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(locks, 1);
      controller.dispose();
      await tester.pump(const Duration(minutes: 3));
      expect(locks, 1);
    },
  );
}
