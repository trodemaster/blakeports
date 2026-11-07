---
name: emaculation-forum
description: Draft a post for the Emaculation forum (emaculation.com, phpBB) — e.g. sharing QEMU/PPC patches, findings or how-tos with cat7 and other users. Use when asked to write, tighten or format a forum post, or to produce phpBB/BBCode text to paste. Drafts in Markdown in the orac Obsidian vault, then converts to conservative BBCode in a .txt file next to it.
---

# Emaculation forum posts

Emaculation (https://www.emaculation.com/forum/) runs phpBB. Posts are written
in Markdown in Obsidian first, then converted to BBCode for pasting.

## Where the files go

Both files live in the orac vault's `Computer/` folder (capital C — Obsidian
paths are case-sensitive even though macOS isn't):

| File | Purpose |
|---|---|
| `Computer/<slug>.md` | The draft, read and edited in Obsidian |
| `Computer/<slug>.txt` | BBCode to paste into the forum |

Read and write vault files through the Obsidian CLI (see the `obsidian`
skill): write the content to `$TMPDIR` first, then `app.vault.create()` or
`app.vault.modify()` via `eval`. The user edits the draft by hand, so always
read the current note before changing or converting it, and build on that
text rather than on an earlier copy.

```bash
OBS=/Applications/Obsidian.app/Contents/MacOS/Obsidian
$OBS vault=orac open path="Computer/<slug>.md"      # show it to the user
```

## Writing the post

The user wants posts short and to the point, and trims anything extra by
hand, so write the short version the first time. Aim for about 500 words
for a three-patch post.

- **Intro: two or three sentences.** Say what was run (guest, CPUs, host,
  purpose), what the patches are against, and the overall result. No link
  list, no background.
- **Don't name the person you're replying to.** Posts usually go in that
  person's own thread (e.g. cat7's G5 QEMU thread), so say "`G5-openbios`
  QEMU", not "cat7's `G5-openbios` QEMU".
- **The main thing gets the space** (the patches, the fix, the finding).
  For each patch or fix, give a **Problem** paragraph (what fails, the
  symptom or cost, and the mechanism, briefly) and a **Fix** paragraph (what
  changes and why it is safe). Take the substance from the patch's own commit
  message so the post matches the code.
- **Links only where they're used.** Put one commit link after each patch,
  and say once that `.patch` can be appended for the raw patch. Link
  upstream issues where they come up. Leave out branch, port and repo links
  unless asked.
- **Side topics get one short paragraph each.** That covers build flags, App
  Nap and similar: the result or percentage, and how to avoid the problem.
  No tables of individual runs, no caveat sections, no "not covered" notes.
- **Leave out abandoned approaches** (e.g. the dropped TLBIE mailbox), and
  local fixes the post doesn't need (e.g. our App Nap commit, when the advice
  is simply to run headless), unless asked.
- **Facts and measurements only:** no marketing, no closing offers to rebase
  or do more work.

## Converting to BBCode

```bash
python3 -I ~/Developer/blakeports/.claude/skills/emaculation-forum/scripts/md2bbcode.py draft.md > "$TMPDIR/<slug>.txt"
```

Read the draft out of the vault into `$TMPDIR/draft.md` first (the
`obsidian read` command). Then write the `.txt` into the vault with `eval`
and open it with `code ~/orac/Computer/<slug>.txt` for copying.

What the converter does, and the forum's limits it follows:

- **Headings become `[b]…[/b]`.** Never use `[size]`: the forum rejects
  sizes over 100 ("You may only use fonts up to size 100"), and the user
  prefers plain formatting anyway.
- **Used:** `**bold**` → `[b]`, `*italic*` → `[i]`, `[text](url)` →
  `[url=…]…[/url]`, lists → `[list]`/`[*]`, and fenced blocks → `[code]`.
- **Inline code becomes plain text**, since phpBB has no inline code tag.
  Bare URLs are left as they are, and phpBB links them.
- **Each paragraph and list item is one line.** Copying from the terminal
  inserts hard line breaks, so always hand over the `.txt` file, never text in
  the chat.

Check the output for anything the converter can't express (tables, images,
nested lists) and rewrite those parts of the draft as plain paragraphs.
