package com.binwaps.cardmanager.performance;

import java.security.SecureRandom;
import java.util.Collection;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

/** A batch-local, cryptographically random code pool with bounded collision retries. */
public final class CodePool {
    private final char[] alphabet;
    private final String prefix;
    private final String suffix;
    private final int length;
    private final Set<String> used;
    private final SecureRandom random = new SecureRandom();
    private final byte[] entropy = new byte[4096];
    private int cursor = entropy.length;

    public CodePool(int count, int requestedLength, String alphabet, String prefix, String suffix,
                    Collection<String> reserved) {
        if (count < 0 || count > 100000 || requestedLength < 1 || requestedLength > 24)
            throw new IllegalArgumentException("عدد الكروت أو طول الرمز خارج النطاق المسموح");
        if (alphabet.length() < 2 || alphabet.length() > 128 || alphabet.chars().distinct().count() != alphabet.length())
            throw new IllegalArgumentException("أبجدية الرموز غير صالحة");
        this.alphabet = alphabet.toCharArray();
        this.prefix = prefix;
        this.suffix = suffix;
        this.used = new HashSet<>(Math.max(16, count * 2));
        for (String value : reserved) used.add(key(value));
        this.length = Math.max(requestedLength, minimumLength(count, alphabet.length(), used.size()));
    }

    public static int minimumLength(int count, int base, int reserved) {
        if (base < 2 || count < 0 || reserved < 0) throw new IllegalArgumentException("Invalid capacity");
        long needed = Math.max(1L, 10L * count + reserved);
        long capacity = base;
        int length = 1;
        while (capacity < needed) { capacity *= base; length++; }
        return length;
    }

    private static String key(String value) { return value.trim().toLowerCase(Locale.ROOT); }

    public int getLength() { return length; }

    /** No sequential suffix fallback: every accepted code keeps the requested alphabet. */
    public String next() {
        for (int attempt = 0; attempt < 256; attempt++) {
            String value = prefix + randomCode(length) + suffix;
            if (used.add(key(value))) return value;
        }
        throw new IllegalStateException("تعذّر توليد رمز فريد — زد عدد الخانات وأعد المحاولة");
    }

    public String randomCode(int size) {
        if (size < 1 || size > 24) throw new IllegalArgumentException("طول كلمة المرور غير صالح");
        char[] code = new char[size];
        int limit = 256 - 256 % alphabet.length;
        for (int i = 0; i < size;) {
            if (cursor == entropy.length) { random.nextBytes(entropy); cursor = 0; }
            int value = entropy[cursor++] & 255;
            if (value < limit) code[i++] = alphabet[value % alphabet.length];
        }
        return new String(code);
    }
}
