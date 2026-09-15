if !(has('win32') || has('win64')) || !executable('cygpath')
	finish
endif

" vimagit assumes that finding cygpath means Vim accepts MSYS paths. Native
" Windows Vim/Neovim needs cygpath's Windows output instead.
runtime autoload/magit/git.vim
execute 'source ' . fnameescape(
	\ expand('<sfile>:p:h:h') . '/autoload/magit/git.vim')
