package com.binwaps.cardmanager.performance;

import java.util.AbstractList;
import java.util.List;

/** Read-only page views: no flattened list, no copying every card into page arrays. */
public final class PageSlices<T> extends AbstractList<List<T>> {
    private final List<T> cards;
    private final int perPage;
    private final int skipped;
    private final int cells;
    public PageSlices(List<T> cards, int perPage, int skipped) {
        if (perPage < 1 || skipped < 0 || skipped >= perPage)
            throw new IllegalArgumentException("Invalid page layout");
        this.cards = cards;
        this.perPage = perPage;
        this.skipped = skipped;
        this.cells = cards.isEmpty() ? 0 : Math.addExact(cards.size(), skipped);
    }
    @Override public int size() { return cells == 0 ? 0 : (cells - 1) / perPage + 1; }
    @Override public List<T> get(int page) {
        if (page < 0 || page >= size()) throw new IndexOutOfBoundsException();
        final int start = page * perPage;
        final int count = Math.min(perPage, cells - start);
        return new AbstractList<T>() {
            @Override public int size() { return count; }
            @Override public T get(int index) {
                if (index < 0 || index >= count) throw new IndexOutOfBoundsException();
                int position = start + index - skipped;
                return position < 0 ? null : cards.get(position);
            }
        };
    }
}
