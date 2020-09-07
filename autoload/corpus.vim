" Copyright 2015-present Greg Hurrell. All rights reserved.
" Licensed under the terms of the MIT license.

let s:chooser_buffer=v:null
let s:chooser_selected_index=v:null
let s:chooser_window=v:null

let s:preview_buffer=v:null
let s:preview_window=v:null

" When opening a new file in a Corpus-managed location, pre-populate it
" with metadata of the form:
"
"   ---
"   title: Title based on file name
"   tags: wiki
"   ---
"
" or:
"
"   ---
"   title: Title based on file name
"   ---
"
function! corpus#buf_new_file() abort
  let l:file=luaeval('corpus.normalize("<afile>")')
  call corpus#update_metadata(l:file)
  let b:corpus_new_file=1
endfunction

function! corpus#buf_write_post() abort
  let l:file=luaeval('corpus.normalize("<afile>")')
  if has_key(b:, 'corpus_new_file')
    unlet b:corpus_new_file
    let l:operation='create'
  else
    let l:operation='update'
  endif
  call luaeval('corpus.commit(_A[1], _A[2])', [l:file, l:operation])
endfunction

function! corpus#buf_write_pre() abort
  let l:file=luaeval('corpus.normalize("<afile>")')
  call corpus#update_references(l:file)
  call corpus#update_metadata(l:file)
endfunction

" Minimal subset of:
"
" https://spec.commonmark.org/0.29/#link-reference-definition
function! corpus#extract_link_reference_definition(line) abort
  let l:match=matchlist(a:line, '\v^ {0,3}\[(\s*\S.*)\]:\s*(.+)')
  if len(l:match)
    " TODO: validate innards
    return [l:match[1], l:match[2]]
  else
    return []
  endif
endfunction

" Loose parsing of reference links. Of the three types, we only look for
" shortcut reference links:
"
" - Full reference link [text][id]
" - Collapsed reference link [id][]
" - Shortcut reference link [id]
"
" See: https://spec.commonmark.org/0.29/#reference-link
function! corpus#extract_reference_links(line) abort
  let l:start=0
  let l:max=len(a:line)

  let l:reference_links=[]

  while l:start < l:max
    " Negative lookbehind (@<!): any [ or ` not preceded by a backslash.
    let l:index=match(a:line, '\v\\@<!(`|[)', l:start)
    if a:line[l:index] == '['
      " May be a link.
      let l:end=match(a:line, '\v\\@<!]', l:index)

      if l:end == -1
        " No end marker found; we're done.
        break
      else
        let l:id = strpart(a:line, l:index + 1, l:end - l:index - 2)
        " Exclude stuff that we know can't be in a file name.
        " eg. [this ~is~ *obviously* `not` a file name]
        if match(l:id, '\v^[ A-Za-z0-9-]+$') == 0
          " Look ahead to be sure this isn't a normal link.
          let l:next=a:line[l:end + 1]
          if l:next != '[' && l:next != '('
            call add(l:reference_links, strpart(a:line, l:index + 1, l:end - l:index - 1))
          endif
        endif

        " (Hopefully rare) gotcha here, if we skip over a normal link
        " that contains something like "[foo]" in its link target we
        " will get a false positive.
        let l:start=l:end + 1
      endif
    elseif a:line[l:index] == '`'
      " May be a code span: https://spec.commonmark.org/0.29/#code-spans
      let l:backticks=matchstr(a:line, '\v`+', l:index)

      " Again, negative lookbehind to find matching run of backticks not preceded
      " by a slash.
      let l:end=match(a:line, '\v\\@<!`{' . len(l:backticks) . '}', l:index + 1)

      if l:end == -1
        " No end marker found; not a code span.
        let l:start=l:index + len(l:backticks)
      else
        " Skip past end marker.
        let l:start=l:end + len(l:backticks)
      endif
    else
      " No unescaped [ or ` found.
      break
    endif
  endwhile

  return l:reference_links
endfunction

let s:metadata_key_value_pattern='\v^\s*(\w+)\s*:\s*(\S.{-})\s*$'

" Returns raw metadata as a list of strings; eg:
"
"   ['tags: wiki', 'title: foo']
"
" If there is no valid metadata, an empty list is returned.
"
" If there are blank lines in the metadata, they are included in the list.
function! corpus#get_metadata_raw() abort
  if match(getline(1), '\v^---\s*$') != -1
    let l:metadata=[]
    for l:i in range(2, line('$'))
      let l:line=getline(l:i)
      if match(l:line, '\v^\s*$') != -1
        call add(l:metadata, '')
        continue
      elseif match(l:line, '\v^---\s*$') != -1
        return l:metadata
      endif
      let l:match=matchlist(l:line, s:metadata_key_value_pattern)
      if len(l:match) == 0
        return []
      endif
      call add(l:metadata, (l:match[0]))
    endfor
  endif
  return []
endfunction

" Returns metadata as a dictionary; eg:
"
"   {'tags': 'wiki', 'title': 'foo'}
"
" If there is no valid metadata, an empty dictionary is returned.
function! corpus#get_metadata() abort
  let l:raw=corpus#get_metadata_raw()
  if len(l:raw)
    let l:metadata={}
    for l:line in l:raw
      let l:match=matchlist(l:line, s:metadata_key_value_pattern)
      if len(l:match)
        let l:metadata[l:match[1]]=l:match[2]
      endif
    endfor
    return l:metadata
  else
    return {}
  endif
endfunction

function! corpus#goto(mode) abort
  if a:mode == 'v'
    " Visual mode.
    let l:start=getpos("'<")
    let l:end=getpos("'>")
    if l:start[1] != l:end[1]
      " We don't support multiline selections.
      return
    endif

    if l:end[2] == 2147483647
      " This is a visual line selection.
      return
    endif

    let l:line=getline(l:start[1])
    let l:len=len(l:line)
    let l:start=l:start[2] -1
    let l:end=l:end[2] - 1

    if l:end - l:start == 0
      " Edge case: empty selection.
      return
    endif

    let l:words=strpart(l:line, l:start, l:end - l:start + 1)
    let l:prefix=strpart(l:line, 0, l:start)
    let l:suffix=strpart(l:line, l:end + 1, l:len - l:end)
    let l:linkified=l:prefix . '[' . l:words . ']' . l:suffix
    call setline(line('.'), l:linkified)
    call cursor(0, l:end + 3)
    return
  endif

  " Normal mode.
  let l:pos=getpos('.')
  " Note that `l:col` is 1-based, so we tweak it to be 0-based.
  let l:col=l:pos[2] - 1
  let l:line=getline(l:pos[1])
  let l:len=len(l:line)

  " Find preceding [.
  if l:line[l:col] == '['
    " Already on [.
    let l:start=l:col + 1
  else
    let l:start=l:col - 1
    while l:start >= 0
      if l:line[l:start] == ']'
        " Hit a prior link: bail.
        let l:start=-1
        break
      elseif l:line[l:start] == '['
        let l:start=l:start + 1
        break
      endif
      let l:start=l:start - 1
    endwhile
  endif

  " Find following ].
  if l:line[l:col] == ']'
    " Already on ].
    let l:end=l:col - 1
  else
    let l:end=l:col + 1
    while l:end <= l:len
      if l:line[l:end] == '['
        " Hit a following link: bail.
        let l:end=l:len + 1
        break
      elseif l:line[l:end] == ']'
        let l:end=l:end - 1
        break
      endif
      let l:end=l:end + 1
    endwhile
  endif

  " Special case: do nothing if cursor on empty link ([]).
  if l:end - l:start < 0
    return
  endif

  let l:config=luaeval('corpus.config_for_file(_A[1])', [expand('%:p')])
  let l:transform=get(l:config, 'transform', 'local')
  if l:start > 0 && l:end < l:len
    let l:name=strpart(l:line, l:start, l:end - l:start + 1)
    if l:transform == 'web'
      let l:name=substitute(l:name, '_', ' ', 'g')
    endif
    let l:target=l:config.location . '/' . l:name . '.md'

    " Check for case differences of first letter, so that we can coerce if
    " necessary.
    let l:matches=glob(
          \   l:config.location .
          \   '/[' .
          \   tolower(l:name[0]) .
          \   toupper(l:name[0]) .
          \   ']' .
          \   strpart(l:name, 1, len(l:name) - 1) .
          \   '.md'
          \   ,
          \   0,
          \   1
          \ )

    if index(matches, l:target) != -1
      " Perfect match, leave it as-is.
    elseif len(matches) == 1
      " Found near match, differing only by case: use that.
      let l:target=matches[0]
    else
      " File doesn't exist yet: will let Vim create it as-is.
    endif

    execute 'edit ' . fnameescape(l:target)
  else
    " No link target found. Assume current word should be made into a link.
    if l:line[l:col] == ' '
      " Edge case: if cursor is between two words, do nothing.
    else
      let l:start=match(strpart(l:line, 0, l:col), '\v\w*$')
      let l:end=match(l:line, '\v>', l:col)
      let l:word=strpart(l:line, l:start, l:end - l:start)
      let l:prefix=strpart(l:line, 0, l:start)
      let l:suffix=strpart(l:line, l:end, l:len - l:end - 1)
      let l:linkified=l:prefix . '[' . l:word . ']' . l:suffix
      call setline(line('.'), l:linkified)
      call cursor(0, l:col + 2)
    endif
  endif
endfunction

function! corpus#set_metadata(metadata) abort
  " Remove old metadata, if present.
  let l:raw=corpus#get_metadata_raw()
  if (len(l:raw))
    " +2 lines for the '---' delimiters.
    call deletebufline('', 1, len(l:raw) + 2)
  endif

  " Format new metadata.
  let l:lines=['---']
  let l:keys=keys(a:metadata)
  for l:key in l:keys
    call add(l:lines, l:key . ': ' . a:metadata[l:key])
  endfor
  call add(l:lines, '---')

  " Prepend new metadata.
  call append(0, l:lines)

  " Make sure there is at least one blank line after metadata.
  " +2 lines for the '---' delimiters.
  " +1 more to see next line.
  let l:next=len(l:keys) + 2 + 1
  if match(getline(l:next), '\v^\s*$') == -1
    call append(l:next - 1, '')
  endif
endfunction

function! corpus#test() abort
  let v:errors=[]

  " Find all the functions in corpus/test.vim and call them.
  for l:candidate in split(&rtp, ',')
    let l:source=join([l:candidate, 'autoload', 'corpus', 'test.vim'], '/')
    if filereadable(l:source)
      let l:lines=readfile(l:source)
      for l:line in l:lines
        let l:match=matchlist(l:line, '\v^function! (corpus#test#[a-z_]+)\(\)')
        if len(l:match)
          execute 'call ' . match[1] . '()'
        endif
      endfor
      break
    endif
  endfor

  if len(v:errors)
    echoerr 'Errors: ' . len(v:errors) . '; please see v:errors'
  endif
endfunction

function! corpus#update_references(file) abort
  let l:config=luaeval('corpus.config_for_file(_A[1])', [a:file])
  if !get(l:config, 'autoreference', 0)
    return
  endif

  " Skip over metadata.
  let l:raw=corpus#get_metadata_raw()
  if len(l:raw)
    let l:start=len(l:raw) + 2 + 1
  else
    let l:start=1
  endif

  " Look for link reference definitions and reference links.
  let l:labels={}
  let l:references={}

  " We don't look for link reference definitions or reference links
  " inside of fenced code blocks.
  "
  " https://spec.commonmark.org/0.29/#fenced-code-blocks
  let l:fence=v:null

  for l:i in range(l:start, line('$'))
    let l:line=getline(l:i)

    if type(l:fence) == type(v:null)
      " Line starting with 3 (or more) backticks or 3 (or more) tildes.
      let l:match=matchlist(l:line, '\v^ {0,3}(`{3,}|~{3,})[^`]*$')
      if len(l:match)
        let l:fence='\v^ {0,3}' . l:match[1][0] . '{' . len(l:match[1]) . ',}\s*$'
        continue
      endif
    else
      if match(l:line, l:fence) != -1
        let l:fence=v:null
      endif
      continue
    endif

    " Indented code block.
    " https://spec.commonmark.org/0.29/#indented-code-block
    if match(l:line, '\v^ {4}') != -1
      continue
    endif

    let l:match=corpus#extract_link_reference_definition(l:line)
    if len(l:match)
      let l:labels[tolower(l:match[0])]=l:match[1]
      continue
    endif

    for l:reference in corpus#extract_reference_links(l:line)
      let l:references[l:reference]=1
    endfor
  endfor

  " If there are existing labels, we assume they are at the bottom.
  let l:has_labels=!!len(l:labels)

  for l:reference in sort(keys(l:references))
    let l:key=tolower(l:reference)
    if !has_key(l:labels, l:key)
      " Have to add l:reference
      let l:labels[l:key]=l:reference

      if !l:has_labels
        " Add a blank separator line if there is not one there already.
        let l:has_labels=1
        if match(getline(line('$')), '\v^\s*$') == -1
          call append(line('$'), '')
        endif
      endif

      let l:base=get(l:config, 'base', '')
      let l:transform=get(l:config, 'transform', 'local')
      if l:transform == 'local'
        let l:target='<' . l:base . l:reference . '.md>'
      elseif l:transform == 'web'
        let l:target=substitute(l:base . l:reference, ' ', '_', 'g')
      else
        let l:target=l:base . l:reference
      endif
      call append(line('$'), '[' . l:reference . ']: ' . l:target)
    endif
  endfor
endfunction

function! corpus#update_metadata(file) abort
  let l:config=luaeval('corpus.config_for_file(_A[1])', [a:file])
  if !get(l:config, 'autotitle', 0) && !has_key(l:config, 'tags')
    return
  endif

  let l:metadata=corpus#get_metadata()

  if get(l:config, 'autotitle', 0)
    let l:title=luaeval('corpus.title_for_file(_A[1])', [a:file])
    let l:metadata.title=l:title
  endif

  if has_key(l:config, 'tags')
    let l:tags=split(get(l:metadata, 'tags', ''))
    for l:tag in l:config.tags
      if index(l:tags, l:tag) == -1
        call add(l:tags, l:tag)
      endif
    endfor
    let l:metadata.tags=join(l:tags)
  endif
  call corpus#set_metadata(l:metadata)
endfunction

function! corpus#complete(arglead, cmdline, cursor_pos) abort
  if luaeval('corpus.in_directory()')
    " TODO expand to current completion?
  else
    let l:directories=luaeval('corpus.directories()')
    return l:directories
  endif
endfunction

function! corpus#choose(selection) abort
  if type(s:chooser_selected_index) != type(v:null)
    let l:line=nvim_buf_get_lines(s:chooser_buffer, s:chooser_selected_index, s:chooser_selected_index + 1, v:false)[0]
    let l:file=strpart(l:line, 2, len(l:line) - 2) . '.md'
    execute 'edit ' . fnameescape(l:file)
  else
    let l:file=''
    if match(a:selection, '\v^\s*$') == -1
      let l:directory=a:selection
      if !isdirectory(l:directory)
        let l:file=l:directory
        let l:directory=luaeval('corpus.directory()')
      endif
    else
      let l:directory=luaeval('corpus.directory()')
    endif
    execute 'cd ' . fnameescape(l:directory)
    echomsg 'Changed to: ' . l:directory
    if !empty(l:file)
      if l:file !~? '\v\.md$'
        let l:file=l:file . '.md'
      endif
      execute 'edit '. fnameescape(l:file)
    endif
  endif
endfunction

" TODO: listen to VimResized events to refresh dimensions

let s:mappings={
      \   '<C-j>': '<Cmd>call corpus#preview_next()<CR>',
      \   '<C-k>': '<Cmd>call corpus#preview_previous()<CR>',
      \   '<Down>': '<Cmd>call corpus#preview_next()<CR>',
      \   '<Up>': '<Cmd>call corpus#preview_previous()<CR>'
      \ }

" TODO: detect pre-existing mappings, save them, and restore them if needed
function! corpus#set_up_mappings() abort
  for l:key in keys(s:mappings)
    execute 'cnoremap <silent> ' . l:key . ' ' . s:mappings[l:key]
  endfor
endfunction

function! corpus#tear_down_mappings() abort
  for l:key in keys(s:mappings)
    if maparg(l:key, 'c') == s:mappings[l:key]
      execute 'silent! cunmap ' . l:key
    endif
  endfor
endfunction

function! corpus#cmdline_changed(char) abort
  if a:char == ':'
    let l:line=getcmdline()
    let l:match=matchlist(l:line, '\v^\s*Corpus>\s*(.{-})\s*$')

    if len(l:match)
      if luaeval('corpus.in_directory()')
        call corpus#set_up_mappings()
        " TODO: add neovim guards
        " Create unlisted scratch buffer.
        if type(s:chooser_window) == type(v:null)
          let s:chooser_buffer=nvim_create_buf(v:false, v:true)
          let s:chooser_window=nvim_open_win(s:chooser_buffer, v:false, {
                \   'col': 0,
                \   'row': 0,
                \   'focusable': 0,
                \   'relative': 'editor',
                \   'style': 'minimal',
                \   'width': &columns / 2,
                \   'height': &lines - 2
                \ })
          call nvim_win_set_option(s:chooser_window, 'wrap', v:false)
        endif

        let l:terms=l:match[1]
        if len(l:terms)
          let l:results=luaeval('corpus.search(_A[1])', [l:terms])
        else
          let l:results=luaeval('corpus.list()')
        endif

        " Update results list and preview.
        if len(l:results)
          let s:chooser_selected_index=0

          " +1 because cursor indexing is 1-based.
          call nvim_win_set_cursor(s:chooser_window, [1, 0])
          let l:list=map(l:results, {i, val -> (i == s:chooser_selected_index ? '> ' : '  ') . fnamemodify(val, ':r')})
          call corpus#debounced_preview()
        else
          let l:list=[]
          let s:chooser_selected_index=v:null
        endif

        call nvim_buf_set_lines(s:chooser_buffer, 0, -1, v:false, l:list)

        " Reserve two lines for statusline and command line.
        call nvim_win_set_height(s:chooser_window, &lines - 2)
        redraw
      else
        " Not in a directory.
        call corpus#tear_down_mappings()
      endif
    else
      call corpus#tear_down_mappings()
    endif
  endif
endfunction

function! corpus#cmdline_enter(char) abort
  let s:chooser_selected_index=v:null
endfunction

function! corpus#cmdline_leave() abort
  if type(s:chooser_window) != type(v:null)
    call nvim_win_close(s:chooser_window, v:true)
    let s:chooser_window=v:null
  endif
  if type(s:preview_window) != type(v:null)
    call nvim_win_close(s:preview_window, v:true)
    let s:preview_window=v:null
  endif
  call corpus#tear_down_mappings()
endfunction

let s:preview_timer=v:null

function! corpus#debounced_preview() abort
  if type(s:preview_timer) != type(v:null)
    call timer_stop(s:preview_timer)
  endif
  let l:time=get(g:, 'CorpusDebounce', 250)
  let s:preview_timer=timer_start(l:time, 'corpus#preview')
endfunction

" TODO Make this a private function; don't want anybody  else calling it
function! corpus#preview(handle) abort
  if s:preview_timer == a:handle
    let s:preview_timer=v:null
  endif

  if type(s:chooser_selected_index) != type(v:null)
    let l:line=nvim_buf_get_lines(s:chooser_buffer, s:chooser_selected_index, s:chooser_selected_index + 1, v:false)[0]
    let l:file=strpart(l:line, 2, len(l:line) - 2) . '.md'

    if type(s:preview_buffer) == type(v:null)
      let s:preview_buffer=nvim_create_buf(v:false, v:true)
    endif
    if type(s:preview_window) == type(v:null)
      let s:preview_window=nvim_open_win(s:preview_buffer, v:false, {
            \   'col': &columns / 2,
            \   'row': 0,
            \   'focusable': 0,
            \   'relative': 'editor',
            \   'style': 'minimal',
            \   'width': &columns / 2,
            \   'height': &lines - 2
            \ })
    endif
    let l:contents=readfile(l:file, '', &lines)
    call nvim_buf_set_lines(s:preview_buffer, 0, -1, v:false, l:contents)
  endif
  redraw
endfunction

function! corpus#preview_next() abort
  if type(s:chooser_selected_index) != type(v:null)
    let l:lines=nvim_buf_get_lines(s:chooser_buffer, s:chooser_selected_index, s:chooser_selected_index + 2, v:false)
    if len(l:lines) == 2
      let l:updated_lines=[
            \   substitute(l:lines[0], '..', '  ', ''),
            \   substitute(l:lines[1], '..', '> ', '')
            \ ]
      let l:file=strpart(l:lines[1], 2, len(l:lines[1]) - 2) . '.md'
      call nvim_buf_set_lines(s:chooser_buffer, s:chooser_selected_index, s:chooser_selected_index + 2, v:false, l:updated_lines)
      let s:chooser_selected_index=s:chooser_selected_index + 1

      " +1 because cursor indexing is 1-based.
      call nvim_win_set_cursor(s:chooser_window, [s:chooser_selected_index + 1, 0])
      redraw
      call corpus#debounced_preview()
    endif
  endif
endfunction

function! corpus#preview_previous() abort
  if type(s:chooser_selected_index) != type(v:null)
    let l:lines=nvim_buf_get_lines(s:chooser_buffer, s:chooser_selected_index - 1, s:chooser_selected_index + 1, v:false)
    if len(l:lines) == 2
      let l:updated_lines=[
            \   substitute(l:lines[0], '..', '> ', ''),
            \   substitute(l:lines[1], '..', '  ', '')
            \ ]
      " TODO: might want to debounce this
      let l:file=strpart(l:lines[0], 2, len(l:lines[0]) - 2) . '.md'
      call nvim_buf_set_lines(s:chooser_buffer, s:chooser_selected_index - 1, s:chooser_selected_index + 1, v:false, l:updated_lines)
      let s:chooser_selected_index=s:chooser_selected_index - 1

      " +1 because cursor indexing is 1-based.
      call nvim_win_set_cursor(s:chooser_window, [s:chooser_selected_index + 1, 0])
      redraw
      call corpus#debounced_preview()
    endif
  endif
endfunction

" List all documents in the corpus.
function! corpus#list() abort
  return luaeval('corpus.list()')
endfunction
