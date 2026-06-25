#!/usr/bin/env python3
"""Small feasibility probe for Velotype block identity/layer/export questions.

This intentionally models Markdown blocks at a text level instead of importing
Velotype internals, so it can run quickly and make architectural questions
concrete without product-code changes.
"""
from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import re
from pathlib import Path


@dataclasses.dataclass
class Block:
    index: int
    kind: str
    text: str
    start: int
    end: int

    @property
    def fingerprint(self) -> str:
        normalized = re.sub(r"\s+", " ", self.text.strip()).lower()
        return hashlib.sha256(normalized.encode()).hexdigest()[:16]


def split_blocks(markdown: str) -> list[Block]:
    blocks: list[Block] = []
    pos = 0
    for idx, match in enumerate(re.finditer(r"(?:^|\n)(.*?)(?=\n\s*\n|\Z)", markdown, re.S)):
        text = match.group(1)
        if text.startswith("\n"):
            text = text[1:]
        if not text.strip():
            continue
        start = match.start(1)
        end = start + len(text)
        stripped = text.lstrip()
        if stripped.startswith("#"):
            kind = "heading"
        elif stripped.startswith("<!--"):
            kind = "comment"
        elif re.match(r"[-*+] \[[ xX]\]", stripped):
            kind = "task"
        elif stripped.startswith(("- ", "* ", "+ ")):
            kind = "list"
        else:
            kind = "paragraph"
        blocks.append(Block(len(blocks), kind, text, start, end))
    return blocks


def identity(markdown: str) -> dict:
    result = {}
    for b in split_blocks(markdown):
        data = dataclasses.asdict(b)
        data["fingerprint"] = b.fingerprint
        result[b.fingerprint] = data
    return result


def reconcile(sidecar: dict, markdown: str) -> dict:
    blocks = split_blocks(markdown)
    by_fp = {b.fingerprint: b for b in blocks}
    results = []
    for ann in sidecar["annotations"]:
        fp = ann["fingerprint"]
        matched = by_fp.get(fp)
        if matched:
            results.append({**ann, "status": "exact-fingerprint", "block": dataclasses.asdict(matched)})
            continue
        # crude fallback: token overlap, enough to reveal limits
        old_tokens = set(re.findall(r"[a-z0-9]+", ann["quoted"].lower()))
        best = None
        best_score = 0.0
        for b in blocks:
            tokens = set(re.findall(r"[a-z0-9]+", b.text.lower()))
            if not old_tokens or not tokens:
                continue
            score = len(old_tokens & tokens) / len(old_tokens | tokens)
            if score > best_score:
                best = b
                best_score = score
        if best and best_score >= 0.35:
            results.append({**ann, "status": "fuzzy-token", "score": round(best_score, 3), "block": dataclasses.asdict(best)})
        else:
            results.append({**ann, "status": "unmatched"})
    return {"results": results}


def export_layers(markdown: str, policy: str) -> str:
    if policy == "preserve":
        return markdown
    if policy == "omit":
        return re.sub(r"\n?<!--\s*velotype:(?:comment|todo).*?-->\n?", "\n", markdown, flags=re.S).strip() + "\n"
    if policy == "render":
        def repl(m: re.Match[str]) -> str:
            raw = m.group(0)
            payload = re.sub(r"^<!--\s*velotype:(comment|todo)\s*|\s*-->$", "", raw.strip(), flags=re.S)
            return f"\n> [!NOTE] {payload.strip()}\n"
        return re.sub(r"<!--\s*velotype:(?:comment|todo).*?-->", repl, markdown, flags=re.S)
    if policy == "fail":
        if re.search(r"<!--\s*velotype:(?:comment|todo)", markdown):
            raise SystemExit("layered metadata present and policy=fail")
        return markdown
    raise SystemExit(f"unknown policy {policy}")


def citations(markdown: str) -> list[str]:
    return sorted(set(re.findall(r"@[-A-Za-z0-9_:.#$%&+?<>~/]+", markdown)))


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("identity"); p.add_argument("file", type=Path)
    p = sub.add_parser("reconcile"); p.add_argument("sidecar", type=Path); p.add_argument("file", type=Path)
    p = sub.add_parser("export-layers"); p.add_argument("policy", choices=["omit","render","preserve","fail"]); p.add_argument("file", type=Path)
    p = sub.add_parser("citations"); p.add_argument("file", type=Path)
    args = parser.parse_args()
    if args.cmd == "identity":
        print(json.dumps(identity(args.file.read_text()), indent=2))
    elif args.cmd == "reconcile":
        print(json.dumps(reconcile(json.loads(args.sidecar.read_text()), args.file.read_text()), indent=2))
    elif args.cmd == "export-layers":
        print(export_layers(args.file.read_text(), args.policy))
    elif args.cmd == "citations":
        print(json.dumps(citations(args.file.read_text()), indent=2))

if __name__ == "__main__":
    main()
