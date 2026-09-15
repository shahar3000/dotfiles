function! s:magit_windows_path(path)
	return magit#utils#strip(system('cygpath -w ' . shellescape(a:path)))
endfunction

function! magit#git#is_work_tree(path)
	let dir = getcwd()
	try
		call magit#utils#chdir(a:path)
		let top_dir = system(g:magit_git_cmd . ' rev-parse --show-toplevel')
		if v:shell_error != 0
			return ''
		endif
		return s:magit_windows_path(magit#utils#strip(top_dir)) . '/'
	finally
		call magit#utils#chdir(dir)
	endtry
endfunction

function! magit#git#set_top_dir(path)
	let dir = getcwd()
	try
		call magit#utils#chdir(a:path)
		let top_dir = system(g:magit_git_cmd . ' rev-parse --show-toplevel')
		if v:shell_error != 0
			throw 'set_top_dir_error'
		endif
		let git_dir = system(g:magit_git_cmd . ' rev-parse --git-dir')
		if v:shell_error != 0
			throw 'set_top_dir_error'
		endif
		let b:magit_top_dir = s:magit_windows_path(
			\ magit#utils#strip(top_dir)) . '/'
		let b:magit_git_dir = s:magit_windows_path(
			\ magit#utils#strip(git_dir)) . '/'
	finally
		call magit#utils#chdir(dir)
	endtry
endfunction
