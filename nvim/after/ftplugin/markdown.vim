" Markdown / vimwiki buffer-local settings.

" Grep across the wiki. Path comes from g:vimwiki_path (set in ~/.vimrc.local).
function! s:VimWikiRg(query, bang) abort
	let l:dir = expand(get(g:, 'vimwiki_path', '~/vimwiki/src'))
	let l:cmd = 'rg --line-number --no-heading --color=always --type md --smart-case -- '
		\ . shellescape(a:query) . ' ' . shellescape(l:dir)
	call fzf#vim#grep(l:cmd, 1, fzf#vim#with_preview(), a:bang)
endfunction
command! -bang -nargs=* VimWikiRg call s:VimWikiRg(<q-args>, <bang>0)

" Search wiki tags/anchors. Buffer-local <leader>W (wiki-grep). NOT <leader>wg:
" that made <leader>w a strict prefix of it, so the global <leader>w (:Windows)
" would stall for timeoutlen in every wiki buffer. Capital W avoids the prefix
" clash and vimwiki's own 'wt' (VimwikiTabIndex).
nnoremap <buffer> <leader>W :VimWikiRg :[\-a-zA-Z0-9]\+:<CR>

setlocal spell
" vimwiki syntax can trip the NFA regex engine (the default, re=0/'auto'); force
" the old backtracking engine. regexpengine is GLOBAL, so use `set` not `setlocal`
" (and re=1, not re=0 which is the no-op default).
if &regexpengine != 1 | set regexpengine=1 | endif
