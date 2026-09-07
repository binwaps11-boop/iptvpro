import com.binwaps.cardmanager.performance.PdfParts;
import com.binwaps.cardmanager.performance.ThroughputMeter;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.CancellationException;

/** Production partition/checkpoint logic; fixture bytes are NOT Android-rendered PDFs. */
public final class PdfRecoveryChecks {
    private static int checks;
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
        checks++;
    }
    public static void main(String[] args) throws Exception {
        PdfParts parts = new PdfParts(770, 1, true);
        check(parts.size() == 7 && parts.get(6).from == 768 && parts.get(6).toExclusive == 770,
                "50k-card layout must cover all pages, including the short final part");
        for (int copies = 1; copies <= 20; copies++) {
            PdfParts plan = new PdfParts(770, copies, true);
            int cursor = 0;
            for (PdfParts.Range range : plan) {
                if (range.from != cursor || range.toExclusive <= range.from ||
                        (range.toExclusive - range.from) * copies > PdfParts.MAX_PHYSICAL_PAGES)
                    throw new AssertionError("Gap, overlap, or too many physical pages");
                cursor = range.toExclusive;
            }
            check(cursor == 770 && plan.pagesCompleted(plan.size()) == 770, "Copies preserve coverage");
        }
        check(new PdfParts(0, 1, true).isEmpty(), "Empty batch has no file");
        check(new PdfParts(128, 1, true).size() == 1 && new PdfParts(129, 1, true).size() == 2, "Split boundary");
        check(new PdfParts(770, 20, false).size() == 1, "Single-file option");
        PdfParts large = new PdfParts(Integer.MAX_VALUE, 20, true);
        check(large.get(large.size() - 1).toExclusive == Integer.MAX_VALUE &&
                large.pagesCompleted(large.size()) == Integer.MAX_VALUE, "Arithmetic does not overflow");
        try { new PdfParts(1, 0, true); throw new AssertionError("Invalid copies accepted"); }
        catch (IllegalArgumentException expected) { checks++; }
        try { parts.get(parts.size()); throw new AssertionError("Invalid index accepted"); }
        catch (IndexOutOfBoundsException expected) { checks++; }
        try { parts.pagesCompleted(-1); throw new AssertionError("Invalid checkpoint accepted"); }
        catch (IllegalArgumentException expected) { checks++; }

        Path folder = Files.createTempDirectory("cardmanager-pdf-check-");
        try {
            File directory = folder.toFile();
            List<String> names = List.of("cards_job_0001.pdf", "cards_job_0002.pdf", "cards_job_0003.pdf");
            for (String name : names) Files.writeString(folder.resolve(name), "fixture content " + name);
            List<String> hashes = List.of(
                    PdfParts.fingerprint(folder.resolve(names.get(0)).toFile(), () -> true),
                    PdfParts.fingerprint(folder.resolve(names.get(1)).toFile(), () -> true),
                    PdfParts.fingerprint(folder.resolve(names.get(2)).toFile(), () -> true));
            check(parts.verifiedPrefix(directory, names, hashes, () -> true) == 3, "Reuse intact saved prefix");
            check(parts.pagesCompleted(3) == 384, "Resume immediately after saved prefix");
            check(parts.verifiedPrefix(directory, List.of(names.get(0), names.get(0)),
                    List.of(hashes.get(0), hashes.get(0)), () -> true) == 1, "Repeated file cannot stand for two parts");
            check(parts.verifiedPrefix(directory, names, List.of(hashes.get(0)), () -> true) == 0, "Reject incomplete manifest");
            check(parts.verifiedPrefix(directory, List.of("../cards_escape.pdf"), List.of(hashes.get(0)), () -> true) == 0,
                    "Manifest cannot escape export directory");
            check(parts.verifiedPrefix(directory, List.of(names.get(0)), List.of("bad-digest"), () -> true) == 0,
                    "Reject malformed digest");
            try { parts.verifiedPrefix(directory, names, hashes, () -> false); throw new AssertionError("Verification ignores cancellation"); }
            catch (CancellationException expected) { checks++; }
            try { PdfParts.fingerprint(folder.resolve(names.get(0)).toFile(), () -> false); throw new AssertionError("Hash ignores cancellation"); }
            catch (CancellationException expected) { checks++; }
            // Equal byte length: size alone must not accept damaged contents.
            byte[] original = Files.readAllBytes(folder.resolve(names.get(1)));
            byte[] changed = original.clone(); changed[0] ^= 1;
            Files.write(folder.resolve(names.get(1)), changed);
            check(parts.verifiedPrefix(directory, names, hashes, () -> true) == 1, "Corruption stops at first damaged part");
            Files.write(folder.resolve(names.get(1)), original);
            Files.delete(folder.resolve(names.get(1)));
            check(parts.verifiedPrefix(directory, names, hashes, () -> true) == 1, "Missing middle part never skips a hole");
            Files.delete(folder.resolve(names.get(0)));
            check(parts.verifiedPrefix(directory, names, hashes, () -> true) == 0, "Evicted cache rebuilds from first missing part");
            Path empty = folder.resolve("cards_empty.pdf");
            Files.createFile(empty);
            check(parts.verifiedPrefix(directory, List.of(empty.getFileName().toString()),
                    List.of(PdfParts.fingerprint(empty.toFile(), () -> true)), () -> true) == 0, "Empty file is incomplete");
            try { PdfParts.resolve(directory, "/tmp/cards_escape.pdf"); throw new AssertionError("Absolute path accepted"); }
            catch (IOException expected) { checks++; }
        } finally {
            try (var paths = Files.list(folder)) { for (Path path : paths.toList()) Files.deleteIfExists(path); }
            Files.deleteIfExists(folder);
        }

        ThroughputMeter resumed = new ThroughputMeter(10000, 0L);
        var initial = ThroughputMeter.withOverallCount(resumed.sample(0, 0L), 40000, 50000);
        check(initial.done == 40000 && initial.perSecond == 0 && initial.remainingSeconds == -1,
                "Resume does not count saved work as new throughput");
        var measured = ThroughputMeter.withOverallCount(resumed.sample(1000, 2_000_000_000L), 41000, 50000);
        check(measured.done == 41000 && measured.total == 50000 && measured.perSecond == 500 && measured.remainingSeconds == 18,
                "Rate and ETA measure this attempt; overall count includes saved work");
        System.out.println("{\"scope\":\"production Java PDF partition and recovery logic; fixture files, no Android PDF rendering\",\"checks_passed\":" + checks + "}");
    }
}
