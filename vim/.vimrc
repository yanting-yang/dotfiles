syntax on
filetype plugin indent on

set expandtab
set number
set shiftwidth=4
set showcmd
set softtabstop=4
set tabstop=4

" status line
set laststatus=2    " always show status line
set statusline=%!MyStatusLine()

fun! MyStatusLine()
    let l:statusline=''
    let l:statusline.='[%t]'    " tail of the file name
    let l:statusline.='[fenc=%{&fileencoding}, ff=%{&fileformat}, ft=%{&filetype}]'
    let l:statusline.='%m'      " modified flag
    let l:statusline.='%r'      " read only flag
    let l:statusline.='%='      " separation between left and right aligned items
    let l:statusline.='[ts=%{&ts}, sts=%{&sts}, sw=%{&sw}, et=%{&et}]'
    let l:maxwid=strlen(&columns)
    let l:statusline.="[c=%".l:maxwid."c/%".l:maxwid."{strlen(getline('.'))}/%{&columns}]"
    let l:maxwid=strlen(line("$"))
    let l:statusline.="[l=%".l:maxwid."l/%L %3p%%]"
    return l:statusline
endfun

fun! TrimTrailingWhitespace()
    let l:save = winsaveview()
    keeppatterns %s/\s\+$//e
    call winrestview(l:save)
endfun
command! TrimTrailingWhitespace call TrimTrailingWhitespace()

fun! TrimFinalNewlines()
    let l:save = winsaveview()
    keeppatterns %s/\n\+\%$//e
    call winrestview(l:save)
endfun
command! TrimFinalNewlines call TrimFinalNewlines()

colorscheme mycolorscheme
