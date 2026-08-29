# Folders — design for a future version

Tracking [#18](https://github.com/cschaba/omapass/issues/18). Nothing here is
implemented. The issue asks for a plan, not a release.

## What already works

Folders are not missing. `pass` folders are just `/` in the entry name, and
omapass already handles them:

- `work/aws/prod-root` saves, reads, renames and deletes correctly.
- The list shows the leaf name with its folder beneath it in grey.
- Entries sort by full path, so a folder's entries already appear together.
- Typing `work` already narrows to that folder, because the filter scores the
  whole path.

So the honest framing is not "add folder support". It is **make the structure
visible, and make filing into it easy**. That is a much smaller feature, and
being clear about it keeps us from building a file manager nobody asked for.

## What is actually missing

1. **Structure is invisible.** Thirty entries in six folders read as thirty
   unrelated rows. You can see a folder only by reading each subtitle.
2. **Filing into a folder is retyping.** Adding four entries to `work/` means
   typing `work/` four times. omapass used to prefill the selected entry's
   folder and that caused [#21](https://github.com/cschaba/omapass/issues/21) —
   it silently filed entries where the user had not looked. The convenience was
   right; doing it invisibly was wrong.
3. **You cannot see what folders exist.** There is no way to answer "did I file
   that under `work` or `job`?" without scrolling the whole list.

## Today

```
┌──────────────────────────────────────────────────────────┐
│ Search passwords…                            9 entries   │
├────────────────────────────┬─────────────────────────────┤
│ ▸ prod-root                │ work/aws/prod-root          │
│   work/aws                 │                             │
│   readonly                 │ password                    │
│   work/aws                 │ ••••••••••••                │
│   giro                     │                             │
│   personal/bank            │ login                       │
│   savings                  │ root                        │
│   personal/bank            │                             │
│   carsten                  │                             │
│   github.com               │                             │
├────────────────────────────┴─────────────────────────────┤
│ ⏎ copy  ⇧⏎ type  ⌥⏎ user  ^L fill login  ^N new  …       │
└──────────────────────────────────────────────────────────┘
```

Every row costs two lines, and the folder is repeated on each.

## Option A — headings

Group the unfiltered list under folder headings. Headings are labels, not rows:
they cannot be selected, and arrow keys skip them.

```
┌──────────────────────────────────────────────────────────┐
│ Search passwords…                    9 entries · 4 folders│
├────────────────────────────┬─────────────────────────────┤
│  personal/bank             │ work/aws/prod-root          │
│    giro                    │                             │
│    savings                 │ password                    │
│  work/aws                  │ ••••••••••••                │
│  ▸ prod-root               │                             │
│    readonly                │ login                       │
│  github.com                │ root                        │
│    carsten                 │                             │
│    deploy-bot              │                             │
├────────────────────────────┴─────────────────────────────┤
│ ⏎ copy  ⇧⏎ type  ⌥⏎ user  ^L fill login  ^N new  …       │
└──────────────────────────────────────────────────────────┘
```

Each entry now costs one line instead of two, so more fits on screen even with
the headings. Structure is visible at a glance. Nothing to learn.

While a filter is active the headings disappear and the list goes back to
flat — when you have typed `giro` you want the match, not its neighbourhood.

**Cost:** the list gains a second row type, which touches selection, arrow
movement and mouse hit-testing. Roughly 80 lines of QML and the model logic
that decides where a heading belongs.

## Option B — drill-down

Folders become rows you enter. `Enter` descends, `Backspace` goes up, a
breadcrumb shows where you are.

```
┌──────────────────────────────────────────────────────────┐
│ work/ ▸                                      2 entries   │
├────────────────────────────┬─────────────────────────────┤
│   ..                       │ work/aws/prod-root          │
│   aws/                     │                             │
│ ▸ prod-root                │ password                    │
│   readonly                 │ ••••••••••••                │
└────────────────────────────┴─────────────────────────────┘
```

**This is the one I would not build.** It reads as the obvious answer because
every file manager works this way, but it fights what omapass is. The app's
entire premise is that you never navigate: you type three letters and press
Enter. Drill-down adds a second, slower way to reach the same entry, and then
has to answer awkward questions — does typing search inside the current folder
or everywhere? What does Backspace do when the filter is non-empty? It also
adds modal state, which is the thing most likely to produce another #21.

## Option C — scope

Typing a folder path scopes the list to it, shown as a chip. Everything after
narrows within that scope. `Backspace` on an empty filter drops the chip.

```
┌──────────────────────────────────────────────────────────┐
│ [work/aws ×] prod                            1 entry     │
├────────────────────────────┬─────────────────────────────┤
│ ▸ prod-root                │ work/aws/prod-root          │
└────────────────────────────┴─────────────────────────────┘
```

Keeps one mental model — typing narrows — and scales to any number of entries.
But it mostly duplicates what the filter already does: typing `work/aws prod`
finds the same entry today, without a new concept. The chip is worth having
only once a store is large enough that repeating the prefix becomes tiresome.

## Filing into a folder

Whichever list design wins, this part is the same, and it is the part
[#21](https://github.com/cschaba/omapass/issues/21) was really about.

`Ctrl+N` stays as it is: an empty name, nothing assumed. **`Ctrl+Shift+N` adds
"new in this folder"** — the name field opens prefilled with the selected
entry's folder, *and the title says so*:

```
┌──────────────────────────────────────────────────────────┐
│ New password in work/aws                                 │
│ Name                                                     │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ work/aws/                                            │ │
│ └──────────────────────────────────────────────────────┘ │
```

The difference from the behaviour removed in #21 is that the user asked for it
and the window says what it is doing. The same convenience, without the silence.

## Recommendation

**Option A, plus `Ctrl+Shift+N`.** It fixes both real complaints — structure is
visible, filing is one keystroke — for the least new machinery, and it adds no
new mental model: the list is still a list and typing still filters.

Option C is worth revisiting when someone has a store big enough to want it.
Option B I would decline unless there is a use case that genuinely needs
hierarchy rather than search.

## If Option A is chosen

- `PassStore.js`: group sorted entries into headings; a pure function, unit
  tested in `tests/entries.sh`.
- `Omapass.qml`: a heading delegate; teach `select()` to skip headings, and
  `selectPath()` to keep working.
- Headings suppressed while filtering.
- `Ctrl+Shift+N` in the overlay, and in the pulldown as a summon payload
  (`{"action":"new","folder":"work/aws"}` — the mechanism from #22).
- The bar pulldown keeps its flat list. It is seven rows in a dropdown; headings
  would spend a third of it on labels.
