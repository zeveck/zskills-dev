#!/usr/bin/env python3
"""Extract visible body text from an HTML file using stdlib html.parser.

Walks the parse tree, emitting `data` from every node except <script>/<style>,
collapses whitespace within runs, and emits one normalized line per text block.

Usage: extract-html-text.py <input.html>
Output: normalized text to stdout
"""
import sys
import re
from html.parser import HTMLParser


# Tags whose textual content is non-visible / non-prose. We exclude void
# tags (meta, link, br, hr, img) from this set even when they're nominally
# head-only, because html.parser does not auto-close them — counting their
# starts without ends would leave skip_depth permanently positive and
# silently swallow the entire body.
SKIP_TAGS = {"script", "style", "head", "title"}
BLOCK_TAGS = {
    "p", "div", "section", "article", "header", "footer", "main", "nav",
    "h1", "h2", "h3", "h4", "h5", "h6",
    "ul", "ol", "li", "dl", "dt", "dd",
    "table", "thead", "tbody", "tr", "th", "td",
    "pre", "blockquote", "figure", "figcaption", "hr", "br",
    "form", "fieldset",
}


class TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip_depth = 0
        self.parts = []
        self._buf = []

    def _flush(self):
        if self._buf:
            text = "".join(self._buf)
            text = re.sub(r"\s+", " ", text).strip()
            if text:
                self.parts.append(text)
            self._buf = []

    def handle_starttag(self, tag, attrs):
        if tag in SKIP_TAGS:
            self.skip_depth += 1
        if tag in BLOCK_TAGS:
            self._flush()

    def handle_endtag(self, tag):
        if tag in BLOCK_TAGS:
            self._flush()
        if tag in SKIP_TAGS:
            self.skip_depth = max(0, self.skip_depth - 1)

    def handle_data(self, data):
        if self.skip_depth > 0:
            return
        self._buf.append(data)

    def close(self):
        self._flush()
        super().close()


def main():
    if len(sys.argv) != 2:
        print("usage: extract-html-text.py <input.html>", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        html = f.read()
    p = TextExtractor()
    p.feed(html)
    p.close()
    for line in p.parts:
        print(line)


if __name__ == "__main__":
    main()
