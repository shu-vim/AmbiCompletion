vim9script
set completefunc=g:AmbiCompletion9

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
"   1. Set completefunc to g:AmbiCompletion9.
"
"       :set completefunc=g:AmbiCompletion9
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
"   g:AmbiCompletion_minimalLength = 4
"
"       a minimal length of candidate words.
"       Each word with a length less than this value is omitted.
"
"   g:AmbiCompletion_preferPrefixMatch = 1
"
"       non-0: each candidate word gets +1 point if starts with the word under
"       the cursor
"       0: gets no extra point
" 
" Commands:
"   
"   AmbiCompletionRefreshCache
"
"       clear the cache.
"
" Memo:
"
"   AmbiCompletion__DEBUG = 0
"   
"       outputs (does :echom) each completion logs.
"

command! AmbiCompletionRefreshCache call ClearCache()

if !exists('g:AmbiCompletion_cacheCheckpoint')
    g:AmbiCompletion_cacheCheckpoint = 50
endif

if !exists('g:AmbiCompletion_minimalLength')
    g:AmbiCompletion_minimalLength = 4
endif

if !exists('g:AmbiCompletion_preferPrefixMatch')
    g:AmbiCompletion_preferPrefixMatch = 1
endif


const AmbiCompletion__DEBUG = 0

const AmbiCompletion__WORD_SPLITTER = '\V\>\zs\ze\<\|\<\|\>\|\s'
const CalcScoreV_COEFFICIENT_THRESHOLD = 0.7

if !exists("lastWord")
    let lastWord = ""
endif

if !exists("again")
    let again = 0
endif

if !exists("words")
    " {word: first_bufnr}
    let words: dict<number> = {}
endif

" {bufnr: tick}
let bufs: dict<number> = {}

def ClearCache()
    lastWord = ""
    words = {}
    bufs = {}
enddef

def ScanBufs()
    for buf in getbufinfo()
        call ScanBufForWords(buf.bufnr)
    endfor
enddef

def ScanBufForWords(bufnr: number)
    let bi = getbufinfo(bufnr)
    let bi0 = bi[0]
    let v = bi0.variables
    let tick = v.changedtick

    let lasttick = -g:AmbiCompletion_cacheCheckpoint
    if has_key(bufs, bufnr)
        lasttick = bufs[bufnr]
    endif

    if tick - lasttick < g:AmbiCompletion_cacheCheckpoint
        return
    endif

    "call Log('  scan ' . getbufinfo(bufnr)[0].name . ' ' . lasttick . ' ' . tick)

    let bufstemp: dict<number> = bufs
    bufstemp[bufnr] = tick
    bufs = bufstemp

    " remove all words in the buffer
    for w in keys(words)
        if words[w] == bufnr
            call remove(words, w)
        endif
    endfor

    " collect words in the buffer
    "let bwords = getbufvar(bufnr, "Ambi_words", {})
    for line in getbufline(bufnr, 1, "$")
        for word in split(line, AmbiCompletion__WORD_SPLITTER)
            if len(word) >= g:AmbiCompletion_minimalLength
                if !has_key(words, word)
                    let wordstemp: dict<number> = words
                    wordstemp[word] = bufnr
                    words = wordstemp
                endif
                "if !has_key(bwords, word)
                "    let bwords[word] = bufnr
                "endif
            endif
        endfor
    endfor
    "call setbufvar(bufnr, "Ambi_words", bwords)
enddef

def g:AmbiCompletion9(findstart: number, base: string): number
    Log('findstart')

    " Find a target word

    if findstart
        Log('findstart')
        " Get cursor word.
        let lineText = strpart(getline('.'), 0, col('.') - 1)
        "return match(lineText, '\V\w\+\$')

        " I want get a last word(maybe a multi-byte char)!!
        let lineWords = split(lineText, '\V\<')
        if len(lineWords) == 0
            return match(lineText, '\V\w\+\$')
        else
            let cursorWord = lineWords[-1]
            "echom 'cursorWord:' . cursorWord
            "echom 'result:' . strridx(lineText, cursorWord)
            return strridx(lineText, cursorWord)
        endif
    endif

    "if 0 && exists('b:Ambi_words')
    "    let bwords = getbufvar(getbufinfo('$')[0].bufnr, "Ambi_words", {})
    "    call Complete(findstart, base, keys(bwords))
    "endif
    call Complete(findstart, base)

    return 0
enddef

"function! Complete(findstart, base, words)
def Complete(findstart: number, base: string)
    " Complete
call PerfLog('=== start completion ===')

    " Care about a multi-byte word
    let baselen = strlen(substitute(base, '.', 'x', 'g'))
    let baseSelfScore = CalcScore(split(base, '\V\zs'), split(base, '\V\zs'), 0.0)
    call PerfLog('baseSelfScore=' .. string(baseSelfScore))
    "let baselen = strlen(base)

	if baselen == 0
		return []
	endif

    " geta
    let geta = 1.0
    if again || lastWord == base
        geta = 0.5
    else
        lastWord = base
call PerfLog('vvv updating cache vvv')
        " Updating may be skipped internally
        call ScanBufs()
call PerfLog('^^^ updated cache ^^^')
    endif

    " Candidates need contain at least one char in base
    let CONTAINDEDIN_REGEXP = '\V\[' .. tolower(join(uniq(sort(split(base, '\V\zs'))), '')) .. ']'

    let results = []

call PerfLog('vvv merging global candidates vvv')
    "let candidates = words
    let candidates = keys(words)
call PerfLog('^^^ merged global candidates ^^^')

call PerfLog('vvv pre-filtering candidates(' .. string(len(candidates)) .. ') vvv')
    call filter(candidates, { idx, val -> 
                \ baseSelfScore * (CalcScoreV_COEFFICIENT_THRESHOLD * geta - 0.1) <= ((strchars(val) - strchars(substitute(val, CONTAINDEDIN_REGEXP, '', 'g'))) * 2 - 1) * 0.75
                \ })
    call PerfLog('[1]' .. string(len(candidates)))
    call filter(candidates, { idx, val ->
                \ baseSelfScore * (CalcScoreV_COEFFICIENT_THRESHOLD * geta - 0.1) <= EstimateScore(substitute(tolower(val), CONTAINDEDIN_REGEXP, ' ', 'g'))
                \ })
    call PerfLog('[2]' .. string(len(candidates)))
call PerfLog('^^^ pre-filtered candidates(' .. string(len(candidates)) .. ') ^^^')

" call PerfLog('vvv sorting candidates vvv')
"     call sort(candidates, {w1, w2 -> strchars(w1) < strchars(w2)})
" call PerfLog('^^^ sorted candidates ^^^')

call PerfLog('vvv filtering candidates(' .. string(len(candidates)) .. ') vvv')
    let baselist = split(tolower(base), '\V\zs')

    let bestscore = baseSelfScore
    for word in candidates
        let score = CalcScore(baselist, split(tolower(word), '\V\zs'), bestscore * geta)
        "echom 'score: ' . word . ' ' . string(score)
        "call Log(word . ' ' . score)

        "call Log(word . ' ' . string(score))
        "call Log(word . ' ' . string(baseSelfScore * CalcScoreV_COEFFICIENT_THRESHOLD * geta))
        if 0 < score && baseSelfScore * CalcScoreV_COEFFICIENT_THRESHOLD * geta <= score
            "let bufnr = words[word]
            call add(results, [word, score])

            "if bestscore != 0
            "    let AmbiCompletion__DEBUG = 0
            "endif

            if bestscore < score
                bestscore = score
            endif
        endif
    endfor
call PerfLog('^^^ filtered candidates(' .. len(results) .. ') ^^^')

    if len(results) <= 1 && !again
        call Log("- - again!! - -")
        again = 1
        let C: func = Complete
        C(findstart, base)
        return 0
    endif

    call sort(results, function('CompareByScoreAndWord'))
call PerfLog('sorted results')

call PerfLog('=== end completion ===')
    "return map(results, '{''word'': v:val[0], ''menu'': v:val[1]}')
    for r in results
        call complete_add({'word': r[0], 'menu': r[1]})
    endfor

    again = 0

    return 0
enddef

def CalcScore(word1: list<string>, word2: list<string>, bestscore: float): number
    let w1 = word1
    let w2 = word2
    let len1 = len(w1) + 1
    let len2 = len(w2) + 1

    let prev = repeat([0], len2)
    let curr: list<number> = repeat([0], len2)

    let superstring = (join(word2, '') =~ join(word1, ''))

    "echom string(prev)
    let r1 = range(1, len1 - 1)
    let r2 = range(1, len2 - 1)
    for i in r1
        for j in r2
            let x = 0
            "echom 'w1['.(i-1).']:'.w1[i-1]
            "echom 'w2['.(j-1).']:'.w2[j-1]
            if w1[i - 1] == w2[j - 1]
                x = 1
                if i - 1 == 0 && j - 1 == 0 && g:AmbiCompletion_preferPrefixMatch != 0
                    x = x + 1
                endif
                if 0 <= i - 2 && 0 <= j - 2 && w1[i - 2] == w2[j - 2]
                    x = 2
                endif
            else
                x = 0
            endif
            let m = max([prev[j - 1] + x, prev[j], curr[j - 1] ])
            curr[j] = m

            "call LogHook(word2, "word_here", 'w1['.(i - 1).']:'.w1[i - 1])
            "call LogHook(word2, "word_here", 'w2['.(j - 1).']:'.w2[j - 1])
            "call LogHook(word2, "word_here", join(word2, '') . '[' . string(j) . '] score:' . string(curr[j]) . ' curr:[' . string(curr) . '] potential:' . string(2*(len2 - 1 - j)) . ' best:' . string(bestscore))
            "call LogHook(word2, "word_here", 'i(' . string(i) . ') == j('. string(j) . ') || len1 - 1(' . string(len1 - 1) . ') <= i(' . string(i) . ')')

            " speed tuning
            if (i == j || len1 - 1 <= i) && !superstring
                "call LogHook(word2, "deepest", 'curr[j]('. string(curr[j]) .') + 2*(len2 - 1 - j)(' . string(2*(len2 - 1 - j)) . ') < bestscore  -  1('.string(bestscore - 1).')')
                if curr[j] + 2 * (len2 - 1 - j) < bestscore * CalcScoreV_COEFFICIENT_THRESHOLD + 1
                    " no hope...
                    return 0
                endif
                "if curr[j] + 2*(len2 - 1 - j) < bestscore
                "    "call Log("  x")
                "    return curr[j]
                "endif
            endif
        endfor
        let temp = prev
        prev = curr
        curr = temp
        "echom string(prev)
    endfor
    "echom string(prev)
    return prev[len2 - 1]
enddef

def EstimateScore(str: string): number
    let score = 0
    let combo = 0
    for i in range(0, len(str))
        if strpart(str, i, 1) == ' '
            score = score + 1 + combo
            combo = 1
        else
            combo = 0
        endif
    endfor
    "PerfLog(str .. ' -> ' .. string(score))
    return score
enddef

def CompareByScoreAndWord(word1: list<any>, word2: list<any>): number
    "hoge
    if word1[1] > word2[1]
        return -1
    elseif word1[1] < word2[1]
        return 1
    elseif len(word1[0]) < len(word2[0])
        return -1
    elseif len(word1[0]) > len(word2[0])
        return 1
    elseif word1[0] < word2[0]
        return -1
    elseif word1[0] > word2[0]
        return 1
    endif
    return 0
enddef

let PerfLog_RELSTART: float = reltime()
def PerfLog(msg: string)
    if AmbiCompletion__DEBUG
        call Log(' ' .. reltimestr(reltime(PerfLog_RELSTART)) ..  ' ' .. msg)
        PerfLog_RELSTART = reltime()
    endif
enddef

def Log(msg: string)
    if AmbiCompletion__DEBUG
        echom strftime('%c') .. ' ' .. msg
    endif
enddef

def LogHook(word: string, trigger: string, msg: string)
    if AmbiCompletion__DEBUG
        let word = word
        if type(word) == 3 "List
            let word = join(word, '')
        endif
        if word == trigger
            echom strftime('%c') .. ' ' .. msg
        endif
    endif
enddef

def g:AmbiCompletion9TEST(w1: string, w2: string)
    echo "'" .. w1 .. "' VS '" .. w2 .. "' => " .. string(CalcScore(split(w1, '\V\zs'), split(w2, '\V\zs'), 0.0))
enddef
