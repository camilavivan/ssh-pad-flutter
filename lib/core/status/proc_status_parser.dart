import 'host_resource_stats.dart';

/// Remote one-shot probe (Linux /proc + df). Same spirit as Kotlin ssh-pad
/// node preview — not copied from ServerBox.
const kHostStatusProbeCmd =
    "echo LOAD \$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null); "
    "echo CPU \$(grep '^cpu ' /proc/stat 2>/dev/null); "
    "echo MEM \$(awk '/MemTotal:/{t=\$2} /MemAvailable:/{a=\$2} END{print t,a}' /proc/meminfo 2>/dev/null); "
    "echo NET \$(awk 'NR>2 {rx+=\$2; tx+=\$10} END{print rx,tx}' /proc/net/dev 2>/dev/null); "
    "echo DISK \$(df -Pk / 2>/dev/null | awk 'NR==2{print \$3,\$2}')";

/// Parsed fields from one probe (absolute counters).
class ProcSample {
  const ProcSample({
    required this.load,
    required this.cpuUser,
    required this.cpuNice,
    required this.cpuSystem,
    required this.cpuIdle,
    required this.cpuIowait,
    required this.cpuIrq,
    required this.cpuSoftirq,
    required this.cpuSteal,
    required this.memTotalKb,
    required this.memAvailableKb,
    required this.rxBytes,
    required this.txBytes,
    required this.diskUsedKb,
    required this.diskTotalKb,
    required this.at,
  });

  final String load;
  final int cpuUser;
  final int cpuNice;
  final int cpuSystem;
  final int cpuIdle;
  final int cpuIowait;
  final int cpuIrq;
  final int cpuSoftirq;
  final int cpuSteal;
  final int memTotalKb;
  final int memAvailableKb;
  final int rxBytes;
  final int txBytes;
  final int diskUsedKb;
  final int diskTotalKb;
  final DateTime at;

  int get cpuIdleAll => cpuIdle + cpuIowait;

  int get cpuTotal =>
      cpuUser +
      cpuNice +
      cpuSystem +
      cpuIdleAll +
      cpuIrq +
      cpuSoftirq +
      cpuSteal;

  int get memUsedKb =>
      memTotalKb > 0 ? (memTotalKb - memAvailableKb).clamp(0, memTotalKb) : 0;
}

/// Parse probe stdout into a [ProcSample]. Returns null if nothing usable.
ProcSample? parseProcProbe(String raw, {DateTime? at}) {
  String load = '—';
  int? cpuUser, cpuNice, cpuSystem, cpuIdle, cpuIowait, cpuIrq, cpuSoftirq, cpuSteal;
  int memTotal = 0, memAvail = 0;
  int rx = 0, tx = 0;
  int diskUsed = 0, diskTotal = 0;
  var sawAnything = false;

  for (final line in raw.split('\n')) {
    final p = line.trim().split(RegExp(r'\s+'));
    if (p.isEmpty || p.first.isEmpty) continue;
    switch (p.first) {
      case 'LOAD':
        if (p.length >= 2) {
          load = p.skip(1).take(3).join(' ');
          sawAnything = true;
        }
      case 'CPU':
        final nums = <int>[];
        for (var i = 1; i < p.length; i++) {
          if (p[i] == 'cpu') continue;
          final n = int.tryParse(p[i]);
          if (n == null) break;
          nums.add(n);
        }
        if (nums.length >= 4) {
          cpuUser = nums[0];
          cpuNice = nums.length > 1 ? nums[1] : 0;
          cpuSystem = nums.length > 2 ? nums[2] : 0;
          cpuIdle = nums.length > 3 ? nums[3] : 0;
          cpuIowait = nums.length > 4 ? nums[4] : 0;
          cpuIrq = nums.length > 5 ? nums[5] : 0;
          cpuSoftirq = nums.length > 6 ? nums[6] : 0;
          cpuSteal = nums.length > 7 ? nums[7] : 0;
          sawAnything = true;
        }
      case 'MEM':
        if (p.length >= 3) {
          memTotal = int.tryParse(p[1]) ?? 0;
          memAvail = int.tryParse(p[2]) ?? 0;
          if (memTotal > 0) sawAnything = true;
        }
      case 'NET':
        if (p.length >= 3) {
          rx = int.tryParse(p[1]) ?? 0;
          tx = int.tryParse(p[2]) ?? 0;
          sawAnything = true;
        }
      case 'DISK':
        if (p.length >= 3) {
          diskUsed = int.tryParse(p[1]) ?? 0;
          diskTotal = int.tryParse(p[2]) ?? 0;
          if (diskTotal > 0) sawAnything = true;
        }
    }
  }

  if (!sawAnything) return null;
  cpuUser ??= 0;
  cpuNice ??= 0;
  cpuSystem ??= 0;
  cpuIdle ??= 0;
  cpuIowait ??= 0;
  cpuIrq ??= 0;
  cpuSoftirq ??= 0;
  cpuSteal ??= 0;

  return ProcSample(
    load: load,
    cpuUser: cpuUser,
    cpuNice: cpuNice,
    cpuSystem: cpuSystem,
    cpuIdle: cpuIdle,
    cpuIowait: cpuIowait,
    cpuIrq: cpuIrq,
    cpuSoftirq: cpuSoftirq,
    cpuSteal: cpuSteal,
    memTotalKb: memTotal,
    memAvailableKb: memAvail,
    rxBytes: rx,
    txBytes: tx,
    diskUsedKb: diskUsed,
    diskTotalKb: diskTotal,
    at: at ?? DateTime.now(),
  );
}

/// Stateful accumulator: applies successive [ProcSample]s to produce rates.
class HostStatusAccumulator {
  ProcSample? _prev;
  HostResourceStats _last = HostResourceStats.empty;

  HostResourceStats get last => _last;

  void reset() {
    _prev = null;
    _last = HostResourceStats.empty;
  }

  HostResourceStats applySample(ProcSample curr) {
    final prev = _prev;
    var cpu = _last.cpuPercent;
    var rxBps = _last.rxBps;
    var txBps = _last.txBps;

    if (prev != null) {
      final dIdle = curr.cpuIdleAll - prev.cpuIdleAll;
      final dTotal = curr.cpuTotal - prev.cpuTotal;
      if (dTotal > 0) {
        cpu = ((1.0 - dIdle / dTotal) * 100).round().clamp(0, 100);
      }
      final dtMs = curr.at.difference(prev.at).inMilliseconds;
      if (dtMs > 0) {
        final dt = dtMs / 1000.0;
        final dRx = curr.rxBytes - prev.rxBytes;
        final dTx = curr.txBytes - prev.txBytes;
        if (dRx >= 0) rxBps = (dRx / dt).round();
        if (dTx >= 0) txBps = (dTx / dt).round();
      }
    }

    _prev = curr;
    _last = HostResourceStats(
      cpuPercent: cpu,
      memUsedKb: curr.memUsedKb,
      memTotalKb: curr.memTotalKb,
      rxBps: rxBps,
      txBps: txBps,
      load: curr.load,
      diskUsedKb: curr.diskUsedKb,
      diskTotalKb: curr.diskTotalKb,
      ready: true,
    );
    return _last;
  }

  /// Parse probe text and update. Returns null if parse failed.
  HostResourceStats? applyRaw(String raw, {DateTime? at}) {
    final sample = parseProcProbe(raw, at: at);
    if (sample == null) return null;
    return applySample(sample);
  }
}
