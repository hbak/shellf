" ~/.local/share/nvim/site/pack/hahnpack/start/vim-rest-console/syntax/rest.vim

if exists('b:current_syntax')
    finish
endif
echom "Our syntax highlighting code will go here."
syn keyword control $>

let b:current_syntax = 'shellf'
