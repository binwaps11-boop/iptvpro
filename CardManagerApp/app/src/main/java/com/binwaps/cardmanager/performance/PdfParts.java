package com.binwaps.cardmanager.performance;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.AbstractList;
import java.util.List;
import java.util.concurrent.CancellationException;
import java.util.function.BooleanSupplier;
import java.util.regex.Pattern;

/** Page-bounded PDF parts and verified recovery; independent of Android rendering. */
public final class PdfParts extends AbstractList<PdfParts.Range> {
    public static final int MAX_PHYSICAL_PAGES = 128;
    private static final Pattern FILE_NAME = Pattern.compile("cards_[A-Za-z0-9_-]+\\.pdf");
    private static final Pattern HASH = Pattern.compile("[0-9a-f]{64}");
    private static final char[] HEX = "0123456789abcdef".toCharArray();
    private final int pages;
    private final int pagesPerPart;

    public PdfParts(int pages, int copies, boolean split) {
        if (pages < 0 || copies < 1 || copies > 20) throw new IllegalArgumentException("Invalid PDF layout");
        this.pages = pages;
        this.pagesPerPart = split ? Math.max(1, MAX_PHYSICAL_PAGES / copies) : Math.max(1, pages);
    }
    @Override public int size() { return pages == 0 ? 0 : (pages - 1) / pagesPerPart + 1; }
    @Override public Range get(int index) {
        if (index < 0 || index >= size()) throw new IndexOutOfBoundsException();
        int from = index * pagesPerPart;
        return new Range(from, (int) Math.min(pages, (long) from + pagesPerPart));
    }
    public int pagesCompleted(int parts) {
        if (parts < 0 || parts > size()) throw new IllegalArgumentException("Invalid checkpoint");
        return (int) Math.min(pages, (long) parts * pagesPerPart);
    }
    public static File resolve(File directory, String name) throws IOException {
        if (name == null || !FILE_NAME.matcher(name).matches()) throw new IOException("Invalid PDF part name");
        File file = new File(directory, name);
        if (!directory.getCanonicalFile().equals(file.getCanonicalFile().getParentFile()))
            throw new IOException("PDF part outside export directory");
        return file;
    }
    public static String fingerprint(File file, BooleanSupplier active) throws IOException {
        final MessageDigest md;
        try { md = MessageDigest.getInstance("SHA-256"); }
        catch (NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
        try (FileInputStream in = new FileInputStream(file)) {
            byte[] buffer = new byte[65536];
            int read;
            while ((read = in.read(buffer)) != -1) {
                if (!active.getAsBoolean()) throw new CancellationException("PDF verification cancelled");
                md.update(buffer, 0, read);
            }
        }
        if (!active.getAsBoolean()) throw new CancellationException("PDF verification cancelled");
        StringBuilder text = new StringBuilder(64);
        for (byte b : md.digest()) { text.append(HEX[(b & 255) >>> 4]); text.append(HEX[b & 15]); }
        return text.toString();
    }
    /** Stop at the first missing/changed part; never skip a hole in the document. */
    public int verifiedPrefix(File directory, List<String> names, List<String> hashes, BooleanSupplier active) {
        if (names.size() != hashes.size() || names.size() > size()) return 0;
        java.util.HashSet<String> seen = new java.util.HashSet<>();
        for (int i = 0; i < names.size(); i++) {
            if (!active.getAsBoolean()) throw new CancellationException("PDF verification cancelled");
            if (!seen.add(names.get(i))) return i;
            if (hashes.get(i) == null || !HASH.matcher(hashes.get(i)).matches()) return i;
            try {
                File file = resolve(directory, names.get(i));
                if (!file.isFile() || file.length() == 0 || !hashes.get(i).equals(fingerprint(file, active))) return i;
            } catch (IOException e) { return i; }
        }
        return names.size();
    }
    public static final class Range {
        public final int from;
        public final int toExclusive;
        private Range(int from, int toExclusive) { this.from = from; this.toExclusive = toExclusive; }
    }
}
