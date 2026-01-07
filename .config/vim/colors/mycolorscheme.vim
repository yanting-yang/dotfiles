" taken from https://vi.stackexchange.com/a/22858
set background=dark

hi clear
if exists("syntax_on")
    syntax reset
endif

let g:colors_name = "mycolorscheme"

" highlight-groups
hi clear LineNr
hi LineNr cterm=reverse

" group-name
hi clear Comment
hi Comment ctermfg=darkgreen

" custom
highlight TrailingWhitespace ctermbg=red
call matchadd("TrailingWhitespace", '\s\+$')

highlight Tab ctermbg=red
call matchadd("Tab", '\t')

highlight FinalNewlines ctermbg=red
call matchadd("FinalNewlines", '\n\+\%$')
" \%$       end of file /zero-width
