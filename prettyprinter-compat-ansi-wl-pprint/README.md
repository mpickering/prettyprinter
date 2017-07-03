ansi-wl-pprint compatibility package
====================================

This package defines a compatibility layer between the old `ansi-wl-pprint`
package, and the new `prettyprinter`/`prettyprinter-ansi-terminal` ones.

This allows easily transitioning dependent packages from the old to the new
package, by simply replacing `ansi-wl-pprint` with `prettyprinter-ansi-terminal`
in the `.cabal` file. For adapting third party plugins that output
`ansi-wl-pprint` data, use the proper converter from the
`prettyprinter-convert-ansi-wl-pprint` module.

Note that this package is **only for transitional purposes**, and therefore
deprecated and wholly undocumented. For new development, use the current version
of `prettyprinter`, and the ANSI terminal backend provided in
`prettyprinter-ansi-terminal`.
