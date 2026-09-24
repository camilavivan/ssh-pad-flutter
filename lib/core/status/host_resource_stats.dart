/// Snapshot of Linux host resources (CPU / mem / net / disk / load).
class HostResourceStats {
  const HostResourceStats({
    this.cpuPercent = -1,
    this.memUsedKb = 0,
    this.memTotalKb = 0,
    this.rxBps = 0,
    this.txBps = 0,
    this.load = '—',
    this.diskUsedKb = 0,
    this.diskTotalKb = 0,
    this.ready = false,
  });

  /// -1 until the second CPU sample yields a delta.
  final int cpuPercent;
  final int memUsedKb;
  final int memTotalKb;
  final int rxBps;
  final int txBps;
  final String load;
  final int diskUsedKb;
  final int diskTotalKb;

  /// True after at least one successful parse (CPU may still be -1).
  final bool ready;

  static const empty = HostResourceStats();

  double get memRatio =>
      memTotalKb > 0 ? (memUsedKb / memTotalKb).clamp(0.0, 1.0) : 0.0;

  double get cpuRatio =>
      cpuPercent >= 0 ? (cpuPercent / 100.0).clamp(0.0, 1.0) : 0.0;

  double get diskRatio =>
      diskTotalKb > 0 ? (diskUsedKb / diskTotalKb).clamp(0.0, 1.0) : 0.0;

  String memText() {
    if (memTotalKb <= 0) return '—';
    return '${_fmtKb(memUsedKb)}/${_fmtKb(memTotalKb)}';
  }

  String cpuText() => cpuPercent >= 0 ? '$cpuPercent%' : '…';

  String netText() => '↓${_fmtBps(rxBps)} ↑${_fmtBps(txBps)}';

  String diskText() {
    if (diskTotalKb <= 0) return '—';
    return '${_fmtKb(diskUsedKb)}/${_fmtKb(diskTotalKb)}';
  }

  static String _fmtKb(int kb) {
    final mb = kb / 1024.0;
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)}G';
    if (mb >= 10) return '${mb.toStringAsFixed(0)}M';
    return '${mb.toStringAsFixed(1)}M';
  }

  static String _fmtBps(int bps) {
    if (bps < 0) return '—';
    final kb = bps / 1024.0;
    if (kb >= 1024) return '${(kb / 1024).toStringAsFixed(1)}MB/s';
    if (kb >= 1) return '${kb.toStringAsFixed(0)}KB/s';
    return '${bps}B/s';
  }

  HostResourceStats copyWith({
    int? cpuPercent,
    int? memUsedKb,
    int? memTotalKb,
    int? rxBps,
    int? txBps,
    String? load,
    int? diskUsedKb,
    int? diskTotalKb,
    bool? ready,
  }) {
    return HostResourceStats(
      cpuPercent: cpuPercent ?? this.cpuPercent,
      memUsedKb: memUsedKb ?? this.memUsedKb,
      memTotalKb: memTotalKb ?? this.memTotalKb,
      rxBps: rxBps ?? this.rxBps,
      txBps: txBps ?? this.txBps,
      load: load ?? this.load,
      diskUsedKb: diskUsedKb ?? this.diskUsedKb,
      diskTotalKb: diskTotalKb ?? this.diskTotalKb,
      ready: ready ?? this.ready,
    );
  }
}
