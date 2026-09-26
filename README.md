# huggingface bucket proxy.

`GET /` returns HTTP 200 with `Compiled at: YYYY-MM-DD HH:MM:SS`.
The timestamp is embedded at compile time using Nim's `CompileDate` and
`CompileTime`, so it stays unchanged across requests and app restarts until
the app is rebuilt.
