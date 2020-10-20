vim9script

# AmbiCompletion -- Ambiguous completion.
#
# Maintainer: Shuhei Kubota <kubota.shuhei+vim@gmail.com>
# Description:
#
#   This script provides an ambiguous completion functionality.
#
#   A long function name, tired to type, a vague memory of spelling, ...
#   Ambiguous completion supports you with similar words in your buffer.
#
#   Your type does not need to match the beginning of answer word.
#   "egining" -> "beginning"
#   
#   For those who are forgetful.
#
#   This is a fork of the first version of Word Fuzzy Completion.
#   (http://www.vim.org/scripts/script.php?script_id=3857)
#   adding architectural changes(mainly no need +python), middle-word-match, global candidates, speed tuning.
#
# Usage:
#
#   1. Set completefunc to g:AmbiCompletion9.
#
#       :set completefunc=g:AmbiCompletion9
#
#       "optional
#       :inoremap <C-U>  <C-X><C-U>
#
# Variables:
#
#   (A right hand side value is a default value.)
#
#   g:AmbiCompletion_cacheCheckpoint = 50
#
#       cache-updating interval.
#       The cache is updated when changedtick progresses by this value.
#
#   g:AmbiCompletion_minimalLength = 4
#
#       a minimal length of candidate words.
#       Each word with a length less than this value is omitted.
#
#   g:AmbiCompletion_preferPrefixMatch = 1
#
#       non-0: each candidate word gets +1 point if starts with the word under
#       the cursor
#       0: gets no extra point
#
#   g:AmbiCompletion_useMatchFuzzy = 0
#
#       non-0: use matchfuzzy() to filter candidates strictly. All candidates
#       must contain all characters you typed.
#       0: do not use matchfuzzy()
# 
# Commands:
#   
#   AmbiCompletionRefreshCache
#
#       clear the cache.
#
# Memo:
#
#   AmbiCompletion__DEBUG = 0
#   
#       outputs (does :echom) each completion logs.
#

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

if !exists('g:AmbiCompletion_useMatchFuzzy')
    g:AmbiCompletion_useMatchFuzzy = 0
endif


const AmbiCompletion__DEBUG = 0

const AmbiCompletion__WORD_SPLITTER = '\V\>\zs\ze\<\|\<\|\>\|\s'
const CalcScoreV_COEFFICIENT_THRESHOLD = 0.7

var lastWord = ""

var again = 0
var words: dict<number> = {}

# {bufnr: tick}
var bufs: dict<number> = {}

def ClearCache()
    lastWord = ""
    words = {}
    bufs = {}
enddef

def ScanBufs()
    PerfReset()
    for buf in getbufinfo()
        call ScanBufForWords(buf.bufnr)
    endfor
    Log('  cache remove: ' .. string(PerfGet('cache remove')) .. 'ms')
    Log('  cache collect: ' .. string(PerfGet('cache collect')) .. 'ms')
enddef

def ScanBufForWords(bufnr: number)
    var bi = getbufinfo(bufnr)
    var bi0 = bi[0]
    var v = bi0.variables
    var tick = v.changedtick

    var lasttick = -g:AmbiCompletion_cacheCheckpoint
    if has_key(bufs, bufnr)
        lasttick = bufs[bufnr]
    endif

    if tick - lasttick < g:AmbiCompletion_cacheCheckpoint
        return
    endif

    #call Log('  scan ' . getbufinfo(bufnr)[0].name . ' ' . lasttick . ' ' . tick)

    var bufstemp: dict<number> = bufs
    bufstemp[bufnr] = tick
    bufs = bufstemp

    # remove all words in the buffer
    PerfBegin("cache remove")
    for w in keys(words)
        if words[w] == bufnr
            call remove(words, w)
        endif
    endfor
    PerfEnd("cache remove")

    # collect words in the buffer
    #let bwords = getbufvar(bufnr, "Ambi_words", {})
    PerfBegin("cache collect")
    for line in getbufline(bufnr, 1, "$")
        for word in split(line, AmbiCompletion__WORD_SPLITTER)
        #for word in split(join(getbufline(bufnr, 1, "$")), AmbiCompletion__WORD_SPLITTER)
            if len(word) >= g:AmbiCompletion_minimalLength
                if !has_key(words, word)
                    #words[word] = bufnr
                    var wordstemp: dict<number> = words
                    wordstemp[word] = bufnr
                    words = wordstemp
                endif
            endif
        endfor
    endfor
    PerfEnd("cache collect")
    #call setbufvar(bufnr, "Ambi_words", bwords)
enddef

def g:AmbiCompletion9(findstart: number, base: string): number
    # Find a target word
    if findstart
        # Get cursor word.
        var lineText = strpart(getline('.'), 0, col('.') - 1)
        #return match(lineText, '\V\w\+\$')

        # I want get a last word(maybe a multi-byte char)!!
        var lineWords = split(lineText, '\V\<')
        if len(lineWords) == 0
            return match(lineText, '\V\w\+\$')
        else
            var cursorWord = lineWords[-1]
            #echom 'cursorWord:' . cursorWord
            #echom 'result:' . strridx(lineText, cursorWord)
            return strridx(lineText, cursorWord)
        endif
    endif

    #if 0 && exists('b:Ambi_words')
    #    var bwords = getbufvar(getbufinfo('$')[0].bufnr, "Ambi_words", {})
    #    call Complete(findstart, base, keys(bwords))
    #endif
    call Complete(findstart, base)

    return 0
enddef

#function! Complete(findstart, base, words)
def Complete(findstart: number, base: string): any
    # Complete
call PerfReset()
call PerfLog('=== start completion ===')

    # Care about a multi-byte word
    var baselen = strchars(base)
    var baseSelfScore = CalcScore(str2list(base), str2list(base))
    call PerfLog('baseSelfScore=' .. string(baseSelfScore))
    #let baselen = strlen(base)

	if baselen == 0
		return []
	endif

    # geta
    var geta = 1.0
    if again || lastWord == base
        geta = 0.5
    else
        lastWord = base
call PerfLog('vvv updating cache vvv')
        # Updating may be skipped internally
        call ScanBufs()
call PerfLog('^^^ updated cache ^^^')
    endif

    var results = []

call PerfLog('vvv merging global candidates vvv')
    #let candidates = words
    var candidates = keys(words)
call PerfLog('^^^ merged global candidates ^^^')

call PerfLog('vvv pre-filtering candidates(' .. string(len(candidates)) .. ') vvv')
    if g:AmbiCompletion_useMatchFuzzy
        candidates = matchfuzzy(candidates, base)
    else
        # Candidates need contain at least one char in base
        var CONTAINDEDIN_REGEXP = '\V\[' .. tolower(join(uniq(sort(split(base, '\V\zs'))), '')) .. ']'

        call filter(candidates, { idx, val ->
                    \ baseSelfScore * (CalcScoreV_COEFFICIENT_THRESHOLD * geta - 0.1) <= EstimateScore(substitute(tolower(val), CONTAINDEDIN_REGEXP, ' ', 'g'))
                    \ })
    endif
call PerfLog('^^^ pre-filtered candidates(' .. string(len(candidates)) .. ') ^^^')

# call PerfLog('vvv sorting candidates vvv')
#     call sort(candidates, {w1, w2 -> strchars(w1) < strchars(w2)})
# call PerfLog('^^^ sorted candidates ^^^')

call PerfLog('vvv filtering candidates(' .. string(len(candidates)) .. ') vvv')
    PerfBegin('entire')
    PerfBegin('outside')
    var baselist = str2list(tolower(base))

    var bestscore = baseSelfScore
    const th = baseSelfScore * CalcScoreV_COEFFICIENT_THRESHOLD * geta
    PerfBegin('iter')
    #for word in candidates
    for word in candidates
        PerfEnd('iter')
        PerfEnd('outside')
        PerfBegin('CalcScore')
        var score = CalcScore(baselist, str2list(tolower(word)))
        PerfEnd('CalcScore')

        PerfBegin('outside')
        #echom 'score: ' . word . ' ' . string(score)
        #call Log(word . ' ' . score)

        #call Log(word . ' ' . string(score))
        #call Log(word . ' ' . string(th))
        PerfBegin('score refresh')
        if 0 < score && th <= score
            #let bufnr = words[word]
            call add(results, [word, score])

            if bestscore < score
                bestscore = score
            endif
        endif
        PerfEnd('score refresh')
        PerfEnd('outside')
        PerfBegin('iter')
    endfor
    PerfEnd('iter')
    PerfEnd('entire')

    Log('  entire: ' .. string(PerfGet('entire')) .. 'ms')
    Log('    CalcScore: ' .. string(PerfGet('CalcScore')) .. 'ms')
    Log('      firstj: ' .. string(PerfGet('firstj')) .. 'ms')
    Log('      naka: ' .. string(PerfGet('naka')) .. 'ms')
    Log('      swap: ' .. string(PerfGet('swap')) .. 'ms')
    Log('    outside: ' .. string(PerfGet('outside')) .. 'ms')
    Log('      score refresh: ' .. string(PerfGet('score refresh')) .. 'ms')
    Log('    iter: ' .. string(PerfGet('iter')) .. 'ms')
call PerfLog('^^^ filtered candidates(' .. len(results) .. ') ^^^')

    if len(results) <= 1 && !again
        call Log("- - again!! - -")
        again = 1
        var C: func = Complete
        C(findstart, base)
        return 0
    endif

    call sort(results, function('CompareByScoreAndWord'))
call PerfLog('sorted results')

call PerfLog('=== end completion ===')
    #return map(results, '{''word'': v:val[0], ''menu'': v:val[1]}')
    for r in results
        call complete_add({'word': r[0], 'menu': r[1]})
    endfor

    again = 0

    return 0
enddef

def CalcScore(word1: list<number>, word2: list<number>): number
    var w1 = word1
    var w2 = word2
    var len1 = len(w1) + 1
    var len2 = len(w2) + 1

    var prev: list<number> = repeat([0], len2)
    var curr: list<number> = repeat([0], len2)

    var superstring = (join(word2, '') =~ join(word1, ''))

    #echom string(prev)
    var r1 = range(1, len1 - 1)
    var r2 = range(1, len2 - 1)
    for i in r1
        ###
        PerfBegin('firstj')
        var firstj: number = 1
        for k in r2
            curr[k] = prev[k]
            firstj = k
            if w1[i - 1] == w2[k - 1]
                break
            endif
        endfor
        PerfEnd('firstj')
        # Log('firstj=' .. string(firstj))
        ###

        #for j in r2
        PerfBegin('naka')
        for j in range(firstj, len2 - 1)
            var x = 0
            #echom 'w1['.(i-1).']:'.w1[i-1]
            #echom 'w2['.(j-1).']:'.w2[j-1]
            if w1[i - 1] == w2[j - 1]
                x = 1
                if i - 1 == 0 && j - 1 == 0 && g:AmbiCompletion_preferPrefixMatch != 0
                    x = x + 1
                    #Log('firstmatch ' .. string(x))
                endif
                if 0 <= i - 2 && 0 <= j - 2 && w1[i - 2] == w2[j - 2]
                    x = 2
                endif
            else
                x = 0
            endif
            var m = max([prev[j - 1] + x, prev[j], curr[j - 1] ])
            curr[j] = m
        endfor
        PerfEnd('naka')
        PerfBegin('swap')
        var temp = prev
        prev = curr
        curr = temp
        PerfEnd('swap')
        # Log(string(prev))

    endfor
    #echom string(prev)
    return prev[len2 - 1]
enddef

def EstimateScore(str: string): number
    var score = 0
    var combo = 0

    const SPACENR = char2nr(" ")
    for n in str2list(str)
        if n == SPACENR
            score = score + 1 + combo
            combo = 1
        else
            combo = 0
        endif
    endfor
    #PerfLog(str .. ' -> ' .. string(score))
    return score
enddef

def CompareByScoreAndWord(word1: list<any>, word2: list<any>): number
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

def SplitChars(str: string): list<string>
    var result: list<string>

    for i in range(0, strchars(str) - 1)
        add(result, strcharpart(str, i, 1))
    endfor

    return result
enddef

###### DEBUGGING ######

var PerfLog_RELSTART: list<any> = reltime()
def PerfLog(msg: string)
    if AmbiCompletion__DEBUG
        call Log(' ' .. reltimestr(reltime(PerfLog_RELSTART)) ..  ' ' .. msg)
        PerfLog_RELSTART = reltime()
    endif
enddef

var PerfEntryMap: dict<list<any>> = {"": []}
call remove(PerfEntryMap, "")

var PerfDurMap: dict<float> = {"": 0.0}
call remove(PerfDurMap, "")

def PerfReset()
    PerfEntryMap = {"": []}
    call remove(PerfEntryMap, "")

    PerfDurMap = {"": 0.0}
    call remove(PerfDurMap, "")
enddef

def PerfBegin(entry: string)
    if AmbiCompletion__DEBUG
        PerfEntryMap[entry] = reltime()
        if !has_key(PerfDurMap, entry)
            PerfDurMap[entry] = 0.0
        endif
    endif
enddef

def PerfEnd(entry: string)
    if AmbiCompletion__DEBUG
        if !has_key(PerfEntryMap, entry)
            PerfBegin(entry)
        endif
        PerfDurMap[entry] = PerfDurMap[entry] + reltimefloat(reltime(PerfEntryMap[entry])) * 1000
        PerfEntryMap[entry] = reltime()
    endif
enddef

def PerfGet(entry: string): float
    if has_key(PerfEntryMap, entry)
        return PerfDurMap[entry]
    else
        return 0.0
    endif
enddef

def Log(msg: string)
    if AmbiCompletion__DEBUG
        echom strftime('%c') .. ' ' .. msg
        #call confirm(strftime('%c') .. ' ' .. msg)
    endif
enddef

def LogHook(word: string, trigger: string, msg: string)
    if AmbiCompletion__DEBUG
        var word = word
        if type(word) == 3 "List
            var word = join(word, '')
        endif
        if word == trigger
            echom strftime('%c') .. ' ' .. msg
        endif
    endif
enddef

def g:AmbiCompletion9TEST(w1: string, w2: string)
    echo "'" .. w1 .. "' VS '" .. w2 .. "' => " .. string(CalcScore(str2list(tolower(w1)), str2list(tolower(w2))))
enddef
