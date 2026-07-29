#!/usr/bin/env python3
"""
Inject data/_index.json into the dashboard template and write a
self-contained dashboard.html.

The template keeps a `<script id="data" ...>` block. On first build it holds
the literal placeholder __DATA__; on later builds it holds the previously
injected JSON. This script replaces whatever is inside that block with the
current data/_index.json, so it is safe to run repeatedly.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "dashboard.html")
INDEX = os.path.join(HERE, "data", "_index.json")

PAT = re.compile(
    r'(<script id="data" type="application/json">)(.*?)(</script>)', re.S
)


def main():
    if not os.path.exists(INDEX):
        sys.exit(f"missing {INDEX} — run analyze.py first")
    data = open(INDEX, encoding="utf-8").read().strip()
    # validate
    json.loads(data)
    html = open(TEMPLATE, encoding="utf-8").read()

    if "__DATA__" in html:
        html = html.replace("__DATA__", data)
    elif PAT.search(html):
        html = PAT.sub(lambda m: m.group(1) + data + m.group(3), html)
    else:
        sys.exit("template has no data <script> block to inject into")

    with open(TEMPLATE, "w", encoding="utf-8") as fh:
        fh.write(html)
    n = len(json.loads(data))
    print(f"injected {len(data)} bytes ({n} chip[s]) -> dashboard.html")


if __name__ == "__main__":
    main()
