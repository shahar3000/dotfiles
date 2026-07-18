" Go: indentation is tabs (gofmt) — vim-sleuth detects it.
" NOTE: cmdheight/updatetime/shortmess are GLOBAL options — 'setlocal' on them
" leaks session-wide (opening one .go file would raise cmdheight for everything).
" updatetime + signcolumn are already set globally in vimrc, so nothing extra is
" needed per-filetype here. Left intentionally minimal.
