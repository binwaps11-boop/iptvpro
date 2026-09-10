import com.binwaps.cardmanager.performance.*;
import java.util.*;

/** Runs the exact dependency-free production classes, without an Android SDK. */
public final class PerformanceChecks {
    private static int checks;
    private static void check(boolean result, String label) {
        if (!result) throw new AssertionError(label);
        checks++;
    }
    public static void main(String[] args) {
        int size = 50000;
        List<String> reserved = new ArrayList<>();
        for (int i = 0; i < size; i++) reserved.add(String.format(Locale.ROOT, "%06d", i));
        Set<String> occupied = new HashSet<>(reserved);
        long start = System.nanoTime();
        CodePool generator = new CodePool(size, 3, "0123456789", "", "", reserved);
        List<String> generated = new ArrayList<>(size);
        for (int i = 0; i < size; i++) generated.add(generator.next());
        double generationMs = (System.nanoTime() - start) / 1e6;
        Set<String> unique = new HashSet<>(generated);
        check(unique.size() == size, "50k unique codes");
        check(Collections.disjoint(occupied, unique), "no collision with 50k reserved codes");
        check(generated.stream().allMatch(s -> s.matches("[0-9]{6}")), "numeric alphabet and automatic length");
        CodePool decorated = new CodePool(1000, 9, "ABCDEFGHJKMNPQRSTUVWXYZ23456789", "NET-", "-X", List.of());
        check(decorated.next().matches("NET-[A-Z2-9]{9}-X"), "prefix, suffix and length preserved");
        check(decorated.randomCode(12).length() == 12, "independent passwords");
        check(CodePool.minimumLength(1000, 10, 0) == 4, "capacity margin");
        try { new CodePool(100001, 6, "0123456789", "", "", List.of()); throw new AssertionError("invalid count accepted"); }
        catch (IllegalArgumentException expected) { checks++; }

        start = System.nanoTime();
        PageSlices<String> pages = new PageSlices<>(generated, 65, 3);
        check(pages.size() == 770, "page count includes partial first page");
        int visited = 0;
        for (List<String> page : pages) for (String card : page)
            if (card != null) check(card.equals(generated.get(visited++)), "card order");
        check(visited == size, "all 50k cards paginated once");
        check(pages.get(0).get(0) == null, "first-page offset");
        check(new PageSlices<>(List.of(), 65, 3).isEmpty(), "empty batch makes no blank page");
        double planningMs = (System.nanoTime() - start) / 1e6;

        ThroughputMeter meter = new ThroughputMeter(size, 0);
        check(meter.sample(0, 0).remainingSeconds == -1, "no invented ETA before progress");
        ThroughputMeter.Snapshot sample = meter.sample(10000, 60_000_000_000L);
        check(Math.abs(sample.perSecond - 166.6666667) < 0.001, "rate from elapsed time");
        check(sample.remainingSeconds == 240, "remaining time from observed rate");
        check(meter.sample(9999, 61_000_000_000L).done == 10000, "late progress cannot go backwards");
        check(meter.sample(999999, 300_000_000_000L).done == size, "progress bounded by total");
        check(meter.sample(size, 300_000_000_000L).remainingSeconds == 0, "completion ETA");

        System.out.printf(Locale.ROOT,
            "{\"checks_passed\":%d,\"cards\":%d,\"reserved\":%d,\"generation_ms\":%.3f,\"page_iteration_ms\":%.3f,\"pages\":%d,\"scope\":\"code generation and page planning only; not PDF rendering, router upload or physical printing\"}%n",
            checks, size, reserved.size(), generationMs, planningMs, pages.size());
    }
}
