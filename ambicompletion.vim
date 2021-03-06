" AmbiCompletion -- Ambiguous completion.
"
" Maintainer: Shuhei Kubota <kubota.shuhei+vim@gmail.com>
" Description:
"
"   This script provides an ambiguous completion functionality.
"
"   A long function name, tired to type, a vague memory of spelling, ...
"   Ambiguous completion supports you with similar words in your buffer.
"
"   Your type does not need to match the beginning of answer word.
"   "egining" -> "beginning"
"   
"   For those who are forgetful.
"
"   This is a fork of the first version of Word Fuzzy Completion.
"   (http://www.vim.org/scripts/script.php?script_id=3857)
"   adding architectural changes(mainly no need +python), middle-word-match, global candidates, speed tuning.
"
" Usage:
"
"   1. Set completefunc to g:AmbiCompletion.
"
"       :set completefunc=g:AmbiCompletion
"
"       "optional
"       :inoremap <C-U>  <C-X><C-U>
"
" Variables:
"
"   (A right hand side value is a default value.)
"
"   g:AmbiCompletion_cacheCheckpoint = 50
"
"       cache-updating interval.
"       The cache is updated when changedtick progresses by this value.
" 
" Commands:
"   
"   AmbiCompletionRefreshCache
"
"       clear the cache.
"
" Memo:
"
"   g:AmbiCompletion__DEBUG = 0
"   
"       outputs (does :echom) each completion logs.
"
"

command! AmbiCompletionRefreshCache call <SID>clearCache()

if !exists('g:AmbiCompletion_cacheCheckpoint')
    let g:AmbiCompletion_cacheCheckpoint = 50
endif


let g:AmbiCompletion__DEBUG = 0

let g:AmbiCompletion__WORD_SPLITTER = '\V\>\zs\ze\<\|\<\|\>\|\s'
let g:AmbiCompletion__LCSV_COEFFICIENT_THRESHOLD = 0.7

if !exists("s:lastWord")
    let s:lastWord = ""
endif

if !exists("s:again")
    let s:again = 0
endif

if !exists("s:words")
    " {word: first_bufnr}
    let s:words = {}
endif

if !exists("s:bufs")
    " {bufnr: tick}
    let s:bufs = {}
endif

function! s:clearCache()
    let s:lastWord = ""
    let s:words = {}
    let s:bufs = {}
endfunction

function! s:scanBufs()
    for buf in getbufinfo()
        call s:scanBufForWords(buf.bufnr)
    endfor
endfunction

function! s:scanBufForWords(bufnr)
    let tick = getbufinfo(a:bufnr)[0].variables.changedtick

    let lasttick = -g:AmbiCompletion_cacheCheckpoint
    if has_key(s:bufs, a:bufnr)
        let lasttick = s:bufs[a:bufnr]
    endif

    if tick - lasttick < g:AmbiCompletion_cacheCheckpoint
        return
    endif

    "call s:LOG('  scan ' . getbufinfo(a:bufnr)[0].name . ' ' . lasttick . ' ' . tick)

    let s:bufs[a:bufnr] = tick

    " remove all words in the buffer
    for w in keys(s:words)
        if s:words[w] == a:bufnr
            call remove(s:words, w)
        endif
    endfor

    " collect words in the buffer
    "let bwords = getbufvar(a:bufnr, "Ambi_words", {})
    for line in getbufline(a:bufnr, 1, "$")
        for word in split(line, g:AmbiCompletion__WORD_SPLITTER)
            if len(word) > 3 
                if !has_key(s:words, word)
                    let s:words[word] = a:bufnr
                endif
                "if !has_key(bwords, word)
                "    let bwords[word] = a:bufnr
                "endif
            endif
        endfor
    endfor
    "call setbufvar(a:bufnr, "Ambi_words", bwords)
endfunction

function! g:AmbiCompletion(findstart, base)

    " Find a target word

    if a:findstart
        " Get cursor word.
        let cur_text = strpart(getline('.'), 0, col('.') - 1)
        "return match(cur_text, '\V\w\+\$')

        " I want get a last word(maybe a multi-byte char)!!
        let cur_words = split(cur_text, '\V\<')
        if len(cur_words) == 0
            return match(cur_text, '\V\w\+\$')
        else
            let last_word = cur_words[-1]
            "echom 'last_word:' . last_word
            "echom 'result:' . strridx(cur_text, last_word)
            return strridx(cur_text, last_word)
        endif
    endif

    if 0&&exists('b:Ambi_words')
        let bwords = getbufvar(getbufinfo('$')[0].bufnr, "Ambi_words", {})
        call s:complete(a:findstart, a:base, keys(bwords))
    endif
    call  s:complete(a:findstart, a:base)
endfunction

"function! s:complete(findstart, base, words)
function! s:complete(findstart, base)
    " Complete
call s:HOGE('=== start completion ===')

    " Care about a multi-byte word
    let baselen = strlen(substitute(a:base, '.', 'x', 'g'))
    let base_self_lcsv = s:AmbiCompletion__LCS(split(a:base, '\V\zs'), split(a:base, '\V\zs'), 0)
    "let baselen = strlen(a:base)

	if baselen == 0
		return []
	endif

    " geta
    let geta = 1.0
    if s:again || s:lastWord == a:base
        let geta = 0.5
    else
        let s:lastWord = a:base
call s:HOGE('vvv updating cache vvv')
        " Updating may be skipped internally
        call s:scanBufs()
call s:HOGE('^^^ updated cache ^^^')
    endif

    " Candidates need contain at least one char in a:base
    let CONTAINDEDIN_REGEXP = '\V\[' . tolower(join(uniq(sort(split(a:base, '\V\zs'))), '')) . ']'
    " Candidates need have their length at least considered-similar LSV value
    let min_word_elem_len = (base_self_lcsv * g:AmbiCompletion__LCSV_COEFFICIENT_THRESHOLD * geta + 1) / 2

    let results = []

call s:HOGE('vvv merging global candidates vvv')
    "let candidates = a:words
    let candidates = keys(s:words)
call s:HOGE('^^^ merged global candidates ^^^')

call s:HOGE('vvv pre-filtering candidates('. string(len(candidates)) . ') vvv')
    call filter(candidates, { idx, val -> 
                \ base_self_lcsv * (g:AmbiCompletion__LCSV_COEFFICIENT_THRESHOLD * geta - 0.1) <= ((strchars(val) - strchars(substitute(val, CONTAINDEDIN_REGEXP, '', 'g'))) * 2 - 1) * 0.75
                \ })
    call filter(candidates, { idx, val ->
                \ base_self_lcsv * (g:AmbiCompletion__LCSV_COEFFICIENT_THRESHOLD * geta - 0.1) <= s:estimate(substitute(tolower(val), CONTAINDEDIN_REGEXP, ' ', 'g'))
                \ })
call s:HOGE('^^^ pre-filtered candidates('. string(len(candidates)) . ') ^^^')

" call s:HOGE('vvv sorting candidates vvv')
"     call sort(candidates, {w1, w2 -> strchars(w1) < strchars(w2)})
" call s:HOGE('^^^ sorted candidates ^^^')

call s:HOGE('vvv filtering candidates('. string(len(candidates)) . ') vvv')
    let baselist = split(tolower(a:base), '\V\zs')

    let bestscore = base_self_lcsv
    for word in candidates
        let lcsv = s:AmbiCompletion__LCS(baselist, split(tolower(word), '\V\zs'), bestscore * geta)
        "echom 'lcsv: ' . word . ' ' . string(lcsv)
        "call s:LOG(word . ' ' . lcsv)

        "call s:LOG(word . ' ' . string(lcsv))
        "call s:LOG(word . ' ' . string(base_self_lcsv * g:AmbiCompletion__LCSV_COEFFICIENT_THRESHOLD * geta))
        if 0 < lcsv && base_self_lcsv * g:AmbiCompletion__LCSV_COEFFICIENT_THRESHOLD * geta <= lcsv
            "let bufnr = s:words[word]
            call add(results, [word, lcsv])

            "if bestscore != 0
            "    let g:AmbiCompletion__DEBUG = 0
            "endif

            if bestscore < lcsv
                let bestscore = lcsv
            endif
        endif
    endfor
call s:HOGE('^^^ filtered candidates('.len(results).') ^^^')

    if len(results) <= 1 && !s:again
        call s:LOG("- - again!! - -")
        let s:again = 1
        call  s:complete(a:findstart, a:base)
        return
    endif

    "LCS
    call sort(results, function('s:lcscompare'))
call s:HOGE('sorted results')

" update words and re-complee
"    if len(results) == 0 && !updated && !s:recurring
"        " detect irritating situation
"        call s:updateWordsCache()
"        let s:recurring = 1
"        let result = g:AmbiCompletion(a:findstart, a:base)
"        let s:recurring = 0
"        return result
"    endif

call s:HOGE('=== end completion ===')
    "return map(results, '{''word'': v:val[0], ''menu'': v:val[1]}')
    for r in results
        call complete_add({'word': r[0], 'menu': r[1]})
    endfor

    let s:again = 0
endfunction

function! s:AmbiCompletion__LCS(word1, word2, bestscore)
    let w1 = a:word1
    let w2 = a:word2
    let len1 = len(w1) + 1
    let len2 = len(w2) + 1

    let prev = repeat([0], len2)
    let curr = repeat([0], len2)

    let superstring = (join(a:word2,'') =~ join(a:word1,''))

    "echom string(prev)
    for i1 in range(1, len1 - 1)
        for i2 in range(1, len2 - 1)
            "echom 'w1['.(i1-1).']:'.w1[i1-1]
            "echom 'w2['.(i2-1).']:'.w2[i2-1]
            if w1[i1-1] == w2[i2-1]
                let x = 1
                if 0 <= i1-2 && 0 <= i2-2 && w1[i1-2] == w2[i2-2]
                    let x = 2
                endif
            else
                let x = 0
            endif
            let curr[i2] = max([ prev[i2-1] + x, prev[i2], curr[i2-1] ])

            "call s:LOGHOOK(a:word2, "word_here", 'w1['.(i1-1).']:'.w1[i1-1])
            "call s:LOGHOOK(a:word2, "word_here", 'w2['.(i2-1).']:'.w2[i2-1])
            "call s:LOGHOOK(a:word2, "word_here", join(a:word2, '') . '[' . string(i2) . '] score:' . string(curr[i2]) . ' curr:[' . string(curr) . '] potential:' . string(2*(len2-1-i2)) . ' best:' . string(a:bestscore))
            "call s:LOGHOOK(a:word2, "word_here", 'i1(' . string(i1) . ') == i2('. string(i2) . ') || len1-1(' . string(len1-1) . ') <= i1(' . string(i1) . ')')

            " speed tuning
            if (i1 == i2 || len1-1 <= i1) && !superstring
                "call s:LOGHOOK(a:word2, "deepest", 'curr[i2]('. string(curr[i2]) .') + 2*(len2-1-i2)(' . string(2*(len2-1-i2)) . ') < a:bestscore - 1('.string(a:bestscore - 1).')')
                if curr[i2] + 2*(len2-1-i2) < a:bestscore * g:AmbiCompletion__LCSV_COEFFICIENT_THRESHOLD + 1
                    " no hope...
                    return 0 "curr[i2]
                endif
                "if curr[i2] + 2*(len2-1-i2) < a:bestscore
                "    "call s:LOG("  x")
                "    return curr[i2]
                "endif
            endif
        endfor
        let temp = prev
        let prev = curr
        let curr = temp
        "echom string(prev)
    endfor
    "echom string(prev)
    return prev[len2-1] "mutibyte cared
endfunction

function! s:estimate(str)
    let score = 0
    let combo = 0
    for i in range(0, len(a:str))
        if a:str[i] == ' '
            let score = score + 1 + combo
            let combo = 1
        else
            let combo = 0
        endif
    endfor
    return score
endfunction

" reverse order
function! s:strlencompare(w1, w2)
    let w1len = strchars(a:w1)
    let w2len = strchars(a:w2)

    if w1len < w2len
        return 1
    elseif w1len == w2len
        "" by char code
        "if a:w1 < a:w2
        "    return 1
        "elseif a:w1 == a:w2
            return 0
        "else
        "    return -1
        "endif
    else
        return -1
    endif
endfunction

function! s:lcscompare(word1, word2)
    if a:word1[1] > a:word2[1]
        return -1
    elseif a:word1[1] < a:word2[1]
        return 1
    elseif len(a:word1[0]) < len(a:word2[0])
        return -1
    elseif len(a:word1[0]) > len(a:word2[0])
        return 1
    elseif a:word1[0] < a:word2[0]
        return -1
    elseif a:word1[0] > a:word2[0]
        return 1
    else
        return 0
    endif
endfunction

let s:HOGE_RELSTART = reltime()
function! s:HOGE(msg)
    if g:AmbiCompletion__DEBUG
        echom strftime('%c') . ' ' . reltimestr(reltime(s:HOGE_RELSTART)) .  ' ' . a:msg
        let s:HOGE_RELSTART = reltime()
    endif
endfunction

function! s:LOG(msg)
    if g:AmbiCompletion__DEBUG
        echom strftime('%c') . ' ' . a:msg
    endif
endfunction

function! s:LOGHOOK(word, trigger, msg)
    if g:AmbiCompletion__DEBUG
        let word = a:word
        if type(word) == 3 "List
            let word = join(word, '')
        endif
        if word == a:trigger
            echom strftime('%c') . ' ' . a:msg
        endif
    endif
endfunction

function! g:AmbiCompletionTEST(w1, w2)
    echo "'" . a:w1 . "' VS '" . a:w2 . "' => " . string(s:AmbiCompletion__LCS(split(a:w1, '\V\zs'), split(a:w2, '\V\zs'), 0))
endfunction
