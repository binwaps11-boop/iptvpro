package com.binwaps.cardmanager.performance;

/** Uses a monotonic clock supplied by the caller; counts are completed work only. */
public final class ThroughputMeter {
    private final int total;
    private final long startedNanos;
    private int completed;

    public ThroughputMeter(int total, long startedNanos) {
        if (total < 0) throw new IllegalArgumentException("Negative total");
        this.total = total;
        this.startedNanos = startedNanos;
    }

    public synchronized Snapshot sample(int done, long nowNanos) {
        completed = Math.max(completed, Math.min(total, Math.max(0, done)));
        long elapsed = Math.max(0L, nowNanos - startedNanos);
        double seconds = elapsed / 1_000_000_000.0;
        double rate = seconds >= 0.1 ? completed / seconds : 0;
        long remaining = completed == total ? 0 : rate > 0 ? (long) Math.ceil((total - completed) / rate) : -1;
        return new Snapshot(completed, total, seconds, rate, remaining);
    }

    /** Resume progress includes saved work; rate and ETA describe only this attempt. */
    public static Snapshot withOverallCount(Snapshot attempt, int done, int total) {
        if (total < 0 || done < 0 || done > total) throw new IllegalArgumentException("Invalid progress");
        return new Snapshot(done, total, attempt.elapsedSeconds, attempt.perSecond,
                done == total ? 0 : attempt.remainingSeconds);
    }

    public static final class Snapshot {
        public final int done;
        public final int total;
        public final double elapsedSeconds;
        public final double perSecond;
        public final long remainingSeconds;
        private Snapshot(int done, int total, double elapsed, double rate, long remaining) {
            this.done = done; this.total = total; this.elapsedSeconds = elapsed;
            this.perSecond = rate; this.remainingSeconds = remaining;
        }
    }
}
