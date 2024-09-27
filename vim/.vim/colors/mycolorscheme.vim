" taken from https://vi.stackexchange.com/a/22858

set background=dark

hi clear
if exists("syntax_on")
    syntax reset
endif

let g:colors_name = "mycolorscheme"

" highlight-groups
hi LineNr cterm=bold ctermfg=white

" group-name
hi Comment cterm=italic ctermfg=gray

" custom
highlight TrailingWhitespace ctermbg=red
call matchadd("TrailingWhitespace", '\s\+$')
" Highlighting matches using :match are limited to three
" matches (aside from :match, :2match and :3match are
" available). matchadd() does not have this limitation and in
" addition makes it possible to prioritize matches.
" From 41.2 - Inside a single-quote string all the characters are as they are.
" From :match - {group} must exist at the moment this command is executed.
" \s        whitespace character: <Space> and <Tab>
" \+        1 or more   as many as possible
" $         end-of-line (at end of pattern) /zero-width
highlight Tab ctermbg=red
call matchadd("Tab", '\t')
" \t        matches <Tab>
highlight FinalNewlines ctermbg=red
call matchadd("FinalNewlines", '\n\+\%$')
" \%$       end of file /zero-width
