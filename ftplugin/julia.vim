" Vim filetype plugin file
" Language:	Julia
" Maintainer:	Carlo Baldassi <carlobaldassi@gmail.com>
" Last Change:	2011 dec 11

if exists("b:did_ftplugin")
	finish
endif
let b:did_ftplugin = 1

let s:save_cpo = &cpo
set cpo-=C

setlocal include="^\s*\%(reload\|include\)\>"
setlocal suffixesadd=.jl
setlocal comments=:#
setlocal commentstring=#=%s=#
setlocal cinoptions+=#1
setlocal define="^\s*macro\>"

" Comment the following line if you don't want operators to be
" syntax-highlightened
let g:julia_highlight_operators=1

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Support for LaTex-to-Unicode conversion as in the Julia REPL "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" (The following line loades the LaTex-to-Unicode dictionary from a file; the file was generated from within Julia with the following code:
"  #  open("latex_symbols.vim","w") do f
"  #    println(f, "\" This file is autogenerated")
"  #    println(f, "let g:latex_symbols = {\n    \\ ", join([string("'", latex, "': '", unicode, "'") for (latex,unicode) in sort!(collect(Base.REPLCompletions.latex_symbols), by=x->x[1])], ",\n    \\ "), "}")
"  #  end
" )
exe "source " . join(split(expand("<sfile>:p"), '/', 1)[0:-2], '/') . "/latex_symbols.vim"

" A hack to forcibly get out of completion mode: feed
" this string with feedkeys()
let s:julia_esc_sequence = "\u0091\<BS>"

" Some data used to keep track of the previous completion attempt.
" Used to detect
" 1) if we just attempted the same completion, or
" 2) if backspace was just pressed while completing
" This function initializes and resets the required info

function! s:JuliaResetLastCompletionInfo()
    let b:julia_completed_once = 0
    let b:julia_bs_while_completing = 0
    let b:julia_last_compl = {
        \ 'line': '',
        \ 'col0': -1,
        \ 'col1': -1,
        \ }
endfunction

call s:JuliaResetLastCompletionInfo()

" Following are some flags used to pass information between the function which
" attempts the LaTeX-to-Unicode completion and the fallback function

" Was a (possibly partial) completion found?
let b:julia_found_completion = 0
" Is the cursor just after a single backslash
let b:julia_singlebslash = 0
" Backup value of the completeopt settings
" (since we temporarily add the 'longest' setting while
"  attempting LaTeX-to-Unicode)
let b:bk_completeopt = &completeopt
" Are we in the middle of a Julia tab completion?
let b:julia_tab_completing = 0


" This function only detects whether an exact match is found for a LaTeX
" symbol in front of the cursor
function! LaTeXtoUnicode_match()
    let col1 = col('.')
    let l = getline('.')
    let col0 = match(l[0:col1-2], '\\[^[:space:]\\]\+$')
    if col0 == -1
        return 0
    endif
    let base = l[col0 : col1-1]
    return has_key(g:latex_symbols, base)
endfunction

" Helper function to sort suggestion entries
function! s:partmatches_sort(p1, p2)
    return a:p1.word > a:p2.word ? 1 : a:p1.word < a:p2.word ? -1 : 0
endfunction

" Helper function to fix display of Unicode compose characters
" in the suggestions menu (they are displayed on top of '◌')
function! s:fix_compose_chars(uni)
    let u = matchstr(a:uni, '^.')
    let isc = ("\u0300" <= u && u <= "\u036F") ||
        \     ("\u1DC0" <= u && u <= "\u1DFF") ||
        \     ("\u20D0" <= u && u <= "\u20FF") ||
        \     ("\uFE20" <= u && u <= "\uFE2F")
    return isc ? "\u25CC" . a:uni : a:uni
endfunction

" Omnicompletion function. Besides the usual two-stage omnifunc behaviour,
" it has the following peculiar features:
"  *) keeps track of the previous completion attempt
"  *) sets some info to be used by the fallback function
"  *) either returns a list of completions if a partial match is found, or a
"     Unicode char if an exact match is found
"  *) forces its way out of completion mode through a hack in some cases
function! LaTeXtoUnicode_omnifunc(findstart, base)
    if a:findstart
        " first stage
        " set info for the callback
        let b:julia_tab_completing = 1
        let b:julia_found_completion = 1
        " analyse current line
        let col1 = col('.')
        let l = getline('.')
        let col0 = match(l[0:col1-2], '\\[^[:space:]\\]\+$')
        " compare with previous completion attempt
        let b:julia_bs_while_completing = 0
        let b:julia_completed_once = 0
        if col0 == b:julia_last_compl['col0']
            let prevl = b:julia_last_compl['line']
            if col1 == b:julia_last_compl['col1'] && l ==# prevl
                let b:julia_completed_once = 1
            elseif col1 == b:julia_last_compl['col1'] - 1 && l ==# prevl[0 : col1-2] . prevl[col1 : -1]
                let b:julia_bs_while_completing = 1
            endif
        endif
        " store completion info for next attempt
        let b:julia_last_compl['col0'] = col0
        let b:julia_last_compl['col1'] = col1
        let b:julia_last_compl['line'] = l
        " is the cursor right after a backslash?
        let b:julia_singlebslash = (match(l[0:col1-2], '\\$') >= 0)
        " completion not found
        if col0 == -1
            let b:julia_found_completion = 0
            call feedkeys(s:julia_esc_sequence)
            let col0 = -2
        endif
        return col0
    else
        " read settings (eager mode is implicit when suggestions are disabled)
        let suggestions = get(g:, "julia_latex_suggestions_enabled", 1)
        let eager = get(g:, "julia_latex_to_unicode_eager", 1) || !suggestions
        " search for matches
        let partmatches = []
        let exact_match = 0
        for k in keys(g:latex_symbols)
            if k ==# a:base
                let exact_match = 1
            endif
            if len(k) >= len(a:base) && k[0 : len(a:base)-1] ==# a:base
                let menu = s:fix_compose_chars(g:latex_symbols[k])
                call add(partmatches, {'word': k, 'menu': menu})
            endif
        endfor
        " exact matches are replaced with Unicode
        " exceptions:
        "  *) we reached an exact match by pressing backspace while completing
        "  *) the exact match is one among many, and the eager setting is
        "     disabled, and it's the first time this completion is attempted
        if exact_match && !b:julia_bs_while_completing && (len(partmatches) == 1 || eager || b:julia_completed_once)
            " the completion is successful: reset the last completion info...
            call s:JuliaResetLastCompletionInfo()
            " ...force our way out of completion mode...
            call feedkeys(s:julia_esc_sequence)
            " ...return the Unicode symbol
            return [g:latex_symbols[a:base]]
        endif
        " here, only partial matches were found; either throw them away or
        " pass them on
        if !suggestions
            let partmatches = []
        else
            call sort(partmatches, "s:partmatches_sort")
        endif
        if empty(partmatches)
            call feedkeys(s:julia_esc_sequence)
            let b:julia_found_completion = 0
        endif
        return partmatches
    endif
endfunction

set omnifunc=LaTeXtoUnicode_omnifunc

" Trigger for the previous mapping of <Tab>
let s:JuliaFallbackTabTrigger = "\u0091JuliaFallbackTab"

" Function which saves the current insert-mode mapping of a key sequence `s`
" and associates it with another key sequence `k` (e.g. stores the current
" <Tab> mapping into the Fallback trigger)
function! s:JuliaSetFallbackTab(s, k)
    let mmdict = maparg(a:s, 'i', 0, 1)
    if empty(mmdict)
        exe 'inoremap <buffer> ' . a:k . ' <Tab>'
        return
    endif
    let rhs = mmdict["rhs"]
    if rhs ==# '<Plug>JuliaTab'
        return
    endif
    let pre = '<buffer>'
    if mmdict["silent"]
        let pre = pre . '<silent>'
    endif
    if mmdict["expr"]
        let pre = pre . '<expr>'
    endif
    if mmdict["noremap"]
        let cmd = 'inoremap '
    else
        let cmd = 'imap '
    endif
    exe cmd . pre . ' ' . a:k . ' ' . rhs
endfunction

" This is the function which is mapped to <Tab>
function! JuliaTab()
    " the <Tab> is passed through to the fallback mapping if the completion
    " menu is present, and it hasn't been raised by the Julia tab, and there
    " isn't an exact match before the cursor when suggestions are disabled
    if pumvisible() && !b:julia_tab_completing && (get(g:, "julia_latex_suggestions_enabled", 1) || !LaTeXtoUnicode_match())
        call feedkeys(s:JuliaFallbackTabTrigger)
        return ''
    endif
    " temporary change to completeopt to use the `longest` setting, which is
    " probably the only one which makes sense given that the goal of the
    " completion is to substitute the final string
    let b:bk_completeopt = &completeopt
    set completeopt+=longest
    " invoke omnicompletion; failure to perform LaTeX-to-Unicode completion is
    " handled by the CompleteDone autocommand.
    return "\<C-X>\<C-O>"
endfunction

" This function is called at every CompleteDone event, and is meant to handle
" the failures of LaTeX-to-Unicode completion by calling a fallback
function! JuliaFallbackCallback()
    if !b:julia_tab_completing
        " completion was not initiated by Julia, nothing to do
        return
    else
        " completion was initiated by Julia, restore completeopt
        let &completeopt = b:bk_completeopt
    endif
    " at this point Julia tab completion is over
    let b:julia_tab_completing = 0
    " if the completion was successful do nothing
    if b:julia_found_completion == 1 || b:julia_singlebslash == 1
        return
    endif
    " fallback
    call feedkeys(s:JuliaFallbackTabTrigger)
    return
endfunction

" Did we install the Julia tab mappings?
let b:julia_tab_set = 0

" Setup the Julia tab mapping
function! s:JuliaSetTab(wait_vim_enter)
    " g:julia_did_vim_enter is set from an autocommand in ftdetect
    if a:wait_vim_enter && !get(g:, "julia_did_vim_enter", 0)
        return
    endif
    if !get(g:, "julia_latex_to_unicode", 1)
        return
    endif
    call s:JuliaSetFallbackTab('<Tab>', s:JuliaFallbackTabTrigger)
    imap <buffer> <Tab> <Plug>JuliaTab
    inoremap <buffer><expr> <Plug>JuliaTab JuliaTab()

    augroup Julia
        autocmd!
        " Every time a completion finishes, the fallback may be invoked
        autocmd CompleteDone <buffer> call JuliaFallbackCallback()
    augroup END

    let b:julia_tab_set = 1
endfunction

" Revert the Julia tab mapping settings
function! JuliaUnsetTab()
    if !b:julia_tab_set
        return
    endif
    iunmap <buffer> <Tab>
    if empty(maparg("<Tab>", "i"))
        call s:JuliaSetFallbackTab(s:JuliaFallbackTabTrigger, '<Tab>')
    endif
    iunmap <buffer> <Plug>JuliaTab
    exe 'iunmap <buffer> ' . s:JuliaFallbackTabTrigger
    autocmd! Julia
    augroup! Julia
endfunction

" YouCompleteMe plugin does not work well with LaTeX symbols
" suggestions
if exists("g:loaded_youcompleteme") || exists("g:loaded_neocomplcache")
    let g:julia_latex_suggestions_enabled = 0
endif

" Try to postpone the first initialization as much as possible,
" by calling s:JuliaSetTab only at VimEnter or later
call s:JuliaSetTab(1)
autocmd VimEnter *.jl call s:JuliaSetTab(0)

""""""""""""""[ End of LaTeX-to-Unicode section ]""""""""""""""


let b:undo_ftplugin = "setlocal include< suffixesadd< comments< commentstring<"
	\ . " define< shiftwidth< expandtab< indentexpr< indentkeys< cinoptions< omnifunc<"
        \ . " | call JuliaUnsetTab()"
        \ . " | delfunction LaTeXtoUnicode_omnifunc | delfunction JuliaTab | delfunction JuliaUnsetTab"

" MatchIt plugin support
if exists("loaded_matchit")
	let b:match_ignorecase = 0

	" note: beginKeywords must contain all blocks in order
	" for nested-structures-skipping to work properly
	let s:beginKeywords = '\<\%(function\|macro\|begin\|type\|immutable\|let\|do\|\%(bare\)\?module\|quote\|if\|for\|while\|try\)\>'
	let s:endKeyowrds = '\<end\>'

	" note: this function relies heavily on the syntax file
	function! JuliaGetMatchWords()
		let s:attr = synIDattr(synID(line("."),col("."),1),"name")
		if s:attr == 'juliaConditional'
			return s:beginKeywords . ':\<\%(elseif\|else\)\>:' . s:endKeyowrds
		elseif s:attr =~ '\<\%(juliaRepeat\|juliaRepKeyword\)\>'
			return s:beginKeywords . ':\<\%(break\|continue\)\>:' . s:endKeyowrds
		elseif s:attr == 'juliaBlKeyword'
			return s:beginKeywords . ':' . s:endKeyowrds
		elseif s:attr == 'juliaException'
			return s:beginKeywords . ':\<\%(catch\|finally\)\>:' . s:endKeyowrds
		endif
		return ''
	endfunction

	let b:match_words = 'JuliaGetMatchWords()'

	" we need to skip everything within comments, strings and
	" the 'end' keyword when it is used as a range rather than as
	" the end of a block
	let b:match_skip = 'synIDattr(synID(line("."),col("."),1),"name") =~ '
		\ . '"\\<julia\\%(ComprehensionFor\\|RangeEnd\\|QuotedBlockKeyword\\|InQuote\\|Comment[LM]\\|\\%(\\|[EILbB]\\|Shell\\)String\\|RegEx\\)\\>"'

	let b:undo_ftplugin = b:undo_ftplugin
            \ . " | unlet! b:match_words b:match_skip b:match_ignorecase"
            \ . " | delfunction JuliaGetMatchWords"
endif

if has("gui_win32")
	let b:browsefilter = "Julia Source Files (*.jl)\t*.jl\n"
        let b:undo_ftplugin = b:undo_ftplugin . " | unlet! b:browsefilter"
endif

let &cpo = s:save_cpo
unlet s:save_cpo
