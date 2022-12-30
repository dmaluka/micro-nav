# Nav plugin

The `nav` plugin provides simple code navigation:

* jumping to a definition (tag) of the given identifier
* jumping to a result of a simple search (grep) for the given text

In particular, it efficiently utilizes the mouse for easy jumping via a
mouse click on an identifier.

## Prerequisites

You need the following programs installed:

* grep
* [GNU Global](https://www.gnu.org/software/global/global.html) aka gtags
* [fzf](https://github.com/junegunn/fzf)

For tag jumping, you need GTAGS index files to be created beforehand.
That is usually as easy as running `gtags` in the top directory of your
project.

## Commands

* `tag` command jumps to the definition of the given identifier. If
  there are multiple definitions found, it runs fzf to show a menu of
  definitions, so you can select which one to jump to.

  Example:

  ```
  > tag foo
  ```

* `grep` command searches for matches of the given regex pattern in all
  files in the current directory. It runs fzf to show a menu of results
  of the search. When you select a match from this menu, it jumps to the
  location of that match.

  Example:

  ```
  > grep foo.*bar
  ```

  You can pass additional flags to grep. E.g. for a case-insensitive
  search:

  ```
  > grep -i foo
  ```

## Mouse and key bindings

* `Ctrl-MouseRight` click on an identifier will jump to its definition,
  just like with the `tag` command. If the click is not on a word, it
  will instead jump back to the location where we were before the last
  jump.

* `Alt-MouseRight` click on a word will search for occurrences of this
  word in all files in the current directory, just like with the `grep`
  command. If the click is not on a word, it will instead jump back to
  the location where we were before the last jump.

* `F9` key press will jump back to the location where we were before the
  last jump.

You can re-bind these actions to some other mouse buttons or keys if you
wish, by modifying the corresponding bindings in your `bindings.json`.

## Known bugs

* If grep takes long and we exit fzf before grep completes, if we then
  manage to interrupt grep via Ctrl-C (within the time window between
  fzf exit and subsequent grep exit), then the entire Micro terminates,
  even if there are unsaved changes! (Actually this seems to be a known
  Micro's issue [#2612](https://github.com/zyedidia/micro/issues/2612))
* Various grep flags (e.g. `-F`, `-P`) aren't properly supported
* Patterns with various special characters (e.g. quotes, backslashes,
  parentheses, spaces) aren't properly supported
* ...

Patches are welcome.
