" isn't working:
"  - syn keyword shellfControl $> (it had been working since the beginning)
"
" ~/.local/share/nvim/site/pack/hahnpack/start/vim-rest-console/syntax/rest.vim
"
" personal learnings:
"	- keepend in a region doesn't allow contained matches to go past the end pattern
"	- contained will only be recognized when mentinoed in the "contains" field
"	of another match
" questions
"   - what is the difference between me=.. and re=..., what do they
"     fundamentally mean?  Couldn't get headerSetter[equals,rhs] to work using
"     separate region/matches and offsets, had to contain one in the other

if exists('b:current_syntax')
	finish
endif

unlet! b:current_syntax
syn include @LUA syntax/lua.vim
unlet! b:current_syntax
syn include @SH syntax/sh.vim
unlet! b:current_syntax
syn include @VIMSCRIPT syntax/vim.vim

setlocal iskeyword+=$,>

syn region headerBlock start=/\%^/ end=/\n--/ contains=headerSetterEqualsLine,headerSetterLua,headerSetterVim fold
" " this is what I thought should have worked
" syn keyword headerSetterEquals = nextgroup=headerEqualsRhs contained
" "syn keyword only works for keyword characters (as defined by the 'iskeyword' setting), and ( usually is not contained.  You have to use :syn match instead" - https://stackoverflow.com/a/12843796   I don't get it but whatever
" syn match headerSetterEqualsLine /= .\+$/ nextgroup=headerEqualsRhs contained contains=headerSetterEquals,headerSetterEqualsRhs
syn match headerSetterEqualsLine /[[:alnum:]-_]\+ = .\+$/ contained contains=headerSetterEquals,headerSetterEqualsRhs containedin=headerBlock keepend

" with a)headerSetterEquals and b)headerSetterEqualsRhs I attempted to use me=,re=,he= to get both of these to 
" match on the equals but assign a) to highlight the equals and b) to
" highlight the rest.  Could not get it to work, I fundamentally just don't
" understand what me,re are supposed to do
" syn match headerSetterEquals / = /me=s-1,he=e-1 contained containedin=headerSetterEqualsLine nextgroup=headerSetterEqualsRhs keepend
" syn region headerSetterEquals start=/ =/ end=/= .\+$'/me=s-2,hs=s,he=s+1 contained containedin=headerSetterEqualsLine keepend
" - can't get region headerSetterEquals to work -- the \"region\" extends past the equals no matter how i set re=,me=,he=

syn region headerSetterEquals start=/ =/ end=/= .\+$/ contained containedin=headerSetterEqualsLine contains=headerSetterEqualsRhs keepend
syn match headerSetterEqualsRhs / = .\+$/ms=s+3 contained containedin=headerSetterEquals contains=@SH keepend
 
syn keyword headerSetterLua lua nextgroup=headerLuaRhs contained
syn keyword headerSetterVim vim nextgroup=headerVimRhs contained
" syn match headerEqualsRhs '.\+$' contains=@SH contained
syn match headerLuaRhs '.\+$' contains=@LUA keepend contained
syn match headerVimRhs '.\+$' contains=@VIMSCRIPT keepend contained


syn region executionBlock start=/--.*$/ end=/\n--/me=s+1,re=s+1,he=s+1 contains=executionLine,postProcessDirectives,executionBlockAnnotation,shellfControl fold keepend
" syn region executionBlockAnnotation start=/--[^\n]*/hs=s+2 end='$' containedin=executionBlock 
syn region executionLine start=/^/ end=/\$>/re=s-1,me=s-1 contains=@SH keepend contained
syn region executionBlockAnnotation start=/--/rs=s+2,hs=s+2 end='$' contained containedin=executionBlock keepend
syn region postProcessDirectives start=/\$>/ end="$" contains=postProcessFunctionBody
syn region postProcessFunctionBody start="{"hs=e+1 end="}"he=s-1 contained contains=@LUA keepend
syn keyword shellfControl $>

syn region shellfComment start="#" end=/$/
" I don't know when shellfControl stopped working



hi def link headerBlock            Variable
hi def link headerSetterEqualsLine Variable
hi def link shellfControl         Comment
hi def link shellfComment         Comment
hi def link executionBlockAnnotation shellfComment
hi def link postProcessDirectives  Special
hi def link headerRhs              Normal
hi def link headerSetterLua        LineNr
hi def link headerSetterVim        LineNr
hi def link headerSetterEquals     LineNr

" temporary highlights for debugging
" hi def link executionBlock IncSearch

let b:current_syntax = 'shellf'
