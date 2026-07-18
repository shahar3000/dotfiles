" nvim entry point — share one config between vim and nvim.
" (Liran's trick: keep everything in ~/.vimrc, have nvim source it.)
set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath
source ~/.vimrc
