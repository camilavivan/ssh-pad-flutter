import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_pad_flutter/core/status/host_resource_stats.dart';
import 'package:ssh_pad_flutter/core/status/proc_status_parser.dart';

void main() {
  group('parseProcProbe', () {
    test('parses load cpu mem net disk lines', () {
      const raw = '''
LOAD 0.15 0.10 0.05
CPU cpu 1000 0 500 8500 100 0 0 0
MEM 8000000 2000000
NET 1000000 500000
DISK 50000000 100000000
''';
      final s = parseProcProbe(raw, at: DateTime.utc(2026, 1, 1));
      expect(s, isNotNull);
      expect(s!.load, '0.15 0.10 0.05');
      expect(s.cpuUser, 1000);
      expect(s.cpuSystem, 500);
      expect(s.cpuIdle, 8500);
      expect(s.cpuIowait, 100);
      expect(s.memTotalKb, 8000000);
      expect(s.memAvailableKb, 2000000);
      expect(s.memUsedKb, 6000000);
      expect(s.rxBytes, 1000000);
      expect(s.txBytes, 500000);
      expect(s.diskUsedKb, 50000000);
      expect(s.diskTotalKb, 100000000);
    });

    test('handles CPU without cpu token (nums only)', () {
      const raw = 'CPU 10 0 5 85 0 0 0 0\nMEM 1024 512\n';
      final s = parseProcProbe(raw);
      expect(s, isNotNull);
      expect(s!.cpuUser, 10);
      expect(s.cpuIdle, 85);
      expect(s.memUsedKb, 512);
    });

    test('returns null on empty junk', () {
      expect(parseProcProbe(''), isNull);
      expect(parseProcProbe('hello world'), isNull);
    });
  });

  group('HostStatusAccumulator', () {
    test('CPU percent from delta; net bps from byte delta', () {
      final acc = HostStatusAccumulator();
      final t0 = DateTime.utc(2026, 1, 1, 0, 0, 0);
      final t1 = DateTime.utc(2026, 1, 1, 0, 0, 2);

      final a = acc.applyRaw(
        'LOAD 0.1 0.1 0.1\n'
        'CPU cpu 100 0 50 850 0 0 0 0\n'
        'MEM 4096000 2048000\n'
        'NET 10000 2000\n'
        'DISK 1000 10000\n',
        at: t0,
      );
      expect(a, isNotNull);
      expect(a!.ready, isTrue);
      expect(a.cpuPercent, -1);
      expect(a.memUsedKb, 2048000);
      expect(a.diskRatio, closeTo(0.1, 0.001));

      final b = acc.applyRaw(
        'LOAD 1.2 0.8 0.4\n'
        'CPU cpu 300 0 150 870 0 0 0 0\n'
        'MEM 4096000 1024000\n'
        'NET 10000 2000\n'
        'DISK 1000 10000\n',
        at: t1,
      );
      expect(b!.cpuPercent, 94);
      expect(b.load, '1.2 0.8 0.4');
      expect(b.rxBps, 0);
      expect(b.txBps, 0);
      expect(b.memText(), isNot(equals('—')));
    });

    test('net rates scale with elapsed time', () {
      final acc = HostStatusAccumulator();
      final t0 = DateTime.utc(2026, 6, 1, 12, 0, 0);
      final t1 = DateTime.utc(2026, 6, 1, 12, 0, 1);
      acc.applyRaw(
        'CPU cpu 0 0 0 100 0 0 0 0\nNET 0 0\nMEM 1000 500\n',
        at: t0,
      );
      final s = acc.applyRaw(
        'CPU cpu 0 0 0 200 0 0 0 0\nNET 102400 51200\nMEM 1000 500\n',
        at: t1,
      );
      expect(s!.rxBps, 102400);
      expect(s.txBps, 51200);
      expect(s.netText(), contains('↓'));
      expect(s.netText(), contains('↑'));
    });

    test('reset clears deltas', () {
      final acc = HostStatusAccumulator();
      final t0 = DateTime.utc(2026, 1, 1);
      acc.applyRaw('CPU cpu 1 0 0 9 0 0 0 0\nMEM 100 50\n', at: t0);
      acc.reset();
      expect(acc.last.ready, isFalse);
      final again = acc.applyRaw(
        'CPU cpu 2 0 0 18 0 0 0 0\nMEM 100 50\n',
        at: t0.add(const Duration(seconds: 1)),
      );
      expect(again!.cpuPercent, -1);
    });
  });

  group('HostResourceStats formatters', () {
    test('fmt helpers', () {
      const s = HostResourceStats(
        cpuPercent: 12,
        memUsedKb: 512 * 1024,
        memTotalKb: 2 * 1024 * 1024,
        rxBps: 2048,
        txBps: 3 * 1024 * 1024,
        ready: true,
      );
      expect(s.cpuText(), '12%');
      expect(s.memText(), contains('/'));
      expect(s.netText(), contains('KB/s'));
      expect(s.netText(), contains('MB/s'));
    });
  });
}
