" Markdown / vimwiki buffer-local settings.

" Grep across the wiki. Path comes from g:vimwiki_path (set in ~/.vimrc.local).
function! s:VimWikiRg(query, bang) abort
	let l:dir = expand(get(g:, 'vimwiki_path', '~/vimwiki/src'))
	let l:cmd = 'rg --line-number --no-heading --color=always --type md --smart-case -- '
		\ . shellescape(a:query) . ' ' . shellescape(l:dir)
	call fzf#vim#grep(l:cmd, 1, fzf#vim#with_preview(), a:bang)
endfunction
command! -bang -nargs=* VimWikiRg call s:VimWikiRg(<q-args>, <bang>0)

" Search wiki tags/anchors. Buffer-local <leader>wg — 'wt' is taken by vimwiki's
" own VimwikiTabIndex, so we use 'wg' (wiki-grep) to avoid overriding it.
noremap <buffer> <leader>wg :VimWikiRg :[\-a-zA-Z0-9]\+:<CR>

setlocal spell
" vimwiki syntax can trip the NFA regex engine (the default, re=0/'auto'); force
" the old backtracking engine. regexpengine is GLOBAL, so use `set` not `setlocal`
" (and re=1, not re=0 which is the no-op default).
if &regexpengine != 1 | set regexpengine=1 | endif
