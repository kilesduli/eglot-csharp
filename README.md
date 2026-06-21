# eglot-csharp

`eglot-csharp` provides Eglot with support for accessing metadata URIs
specific to [`csharp-ls`](https://github.com/razzmatazz/csharp-language-server),
so xref features such as jumping to definitions work correctly.

## How to use
Require the package directly. It intentionally provides no autoloaded commands.

```elisp
(add-to-list 'load-path "/path/to/eglot-csharp")
(require 'eglot-csharp)
```

To disable metadata URI support:

```elisp
(setq ec-enable-csharp-metadata-support nil)
```

## License

This project is licensed under the GPL-3.0-or-later. See [LICENSE](LICENSE).
