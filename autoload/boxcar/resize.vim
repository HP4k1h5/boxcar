""
" @public
" Resize the box the cursor is in by {y} rows and {x} columns. If {live} is
" true, the line under edit will not be padded out, to accomodate the newly
" inserted char. The y and x values are added from the cursor's current
" position. currently only works with positive numbers.
function! boxcar#resize(y, x, live)

  if l:y < 0 || l:X < 0 || a:live < 0 || a:live > 1
    throw 'bad arguments supplied please see docs'
  endif

  let l:cp = getcurpos()
  let l:cp = [l:cp[1], l:cp[4]]
  try
    let [l:start, l:end, l:block] = boxcar#block#get(l:cp[0], '```')
  catch
    echohl join(v:exception, '::')
    return 1
  endtry

  let l:corners = s:get_corners(l:block)
  if ! len(l:corners)
    echohl 'no top-left corners'
    return 1
  endif

  let l:cur_box_ind = s:in_box(l:corners, [l:cp[0]-l:start+1, l:cp[1]-a:live])
  if l:cur_box_ind == -1
    echohl 'cursor y'.l:cp[0].':x'.l:cp[1].'not in box'
    return 1
  endif
  let l:cur_box = l:corners[l:cur_box_ind]

  " get potentially affected boxes and premove required lines
  call s:fix_lines(l:corners, l:start, 
        \ [l:cur_box[0][0]+l:start, l:cp[1]],
        \ (l:cur_box[2][0] - l:cur_box[0][0] + 1), l:X)

  call s:increment(l:block, l:start, l:end, l:cp, l:cur_box, l:y, l:X, a:live)
endfunction


" add empty rows {y} and columns {x} to a {box} beginning at cursor
" location {cp}. If {live} is true, skip line extension for cp[1].
function s:increment(block, start, end, cp, box, y, x, live)

  " set box elements
  let l:border_x = repeat('━', l:X)
  let l:blank_x = repeat(' ', l:X)

  " set constants
  let l:box_start_y = a:start + a:box[0][0] 
  let l:box_end_y = a:start + a:box[2][0]
  let l:box_end_x = a:box[1][1]

  " extend top border
  call setline(l:box_start_y,
        \ join(extend( 
        \ split(a:block[a:box[0][0]], '\zs'), 
        \ split(l:border_x, '\zs'), 
        \ l:box_end_x), ''))

  " extend content area, off-by is from array-to-page mapping. Skip extension
  " when typing live, as character input will extend line by itself 
  let l:i = l:box_start_y + 1
  for l in a:block[a:box[0][0]+1: a:box[2][0]]
    call setline(l:i, join(extend( 
        \ split(l, '\zs'), 
        \ l:i == a:cp[0] && a:live ? [''] : split(l:blank_x, '\zs'), 
        \ l:box_end_x), ''))
    " next line
    let l:i += 1
  endfor

  " set bottom border
  call setline(l:box_end_y,
        \ join(extend( 
        \ split(a:block[a:box[2][0]], '\zs'), 
        \ split(l:border_x, '\zs'), 
        \ l:box_end_x), ''))

  " reevaluate block and boxes after extending right
  let [l:start, l:end, l:block] = boxcar#block#get(a:cp[0], '```')
  let l:corners = s:get_corners(l:block)
  let l:cur_box_ind = s:in_box(l:corners, [a:cp[0]-a:start+1, a:cp[1]-a:live])
  let l:box = l:corners[l:cur_box_ind]

  " add y values 
  let l:i = a:cp[0]
  let l:end = a:end
  let l:stop = l:i + l:y
  while l:i < l:stop
    " add newlines if at block end
    if l:i == l:end
      call append(l:i - 1, repeat(' ', l:box[0][1] + 1))
      let l:end += 1
    endif
    let l:rep_start = l:box[0][1] > 0
          \ ? join(split(l:block[l:i - a:start], '\zs')[:l:box[0][1]], '')
          \ : '' 
    let l:rep_end = join(split(l:block[l:i - a:start], '\zs')[l:box[1][1] + 1:], '')
    call append(l:i-1, 
          \ l:rep_start.'┃'
          \ .repeat(' ', l:box[1][1] - l:box[0][1] - 1)
          \ .'┃'.l:rep_end)

    let l:i += 1
  endwhile
endfunction


" remove rows {y} and columns {x} from {box}
function! s:decrement(box, y, x)
endfunction


" Returns a list of box corners inside {block}. Each returned box has 4
" corners in the following order [tl, tr, bl, br]. Each corner is a list of
" [y, x] zero-indexed pairs, relative to the {block}, not the page.
function s:get_corners(block)
  let l:corners = []
  let l:i = 0

  let l:tls = s:get_tls(a:block)
  if ! len(l:tls)
    return l:tls
  endif

  " iterate over corners and check each for full box
  for tl in l:tls
    let l:maybe_box = []
    " let unibox = ['━','┃','┏','┓','┗','┛']
  
    " find connected top-right or throw
    let l:ci = tl[1] + 1
    " iterate over chars in line from tl corner
    for c in split(a:block[tl[0]], '\zs')[l:ci:]
      if c ==# '┓'
        " add top-left and top-right to maybe_box
        call extend(l:maybe_box, [tl, [tl[0], l:ci]])
        break
      elseif c !=# '━'
        throw 'disconnected top right: '.c.' .. x-index: '.l:ci
      endif
      " next char
      let l:ci += 1
    endfor

    " find connected bottom-left or throw
    let l:blyi = tl[0] + 1
    for l in a:block[l:blyi:]
      let l:c = split(l, '\zs')[tl[1]]
      if l:c ==# '┗'
        " add bottom-leftto maybe_box
        call add(l:maybe_box, [l:blyi, tl[1]])
        break
      elseif l:c !=# '┃'
        throw 'disconnected bottom left: '.l:c.' .. y-index: '.l:blyi
      endif

      " next line
      let l:blyi += 1
    endfor

    " find connected bottom-right or throw
    let l:ci = tl[1] + 1
    for c in split(a:block[l:blyi], '\zs')[l:ci:]
      if c ==# '┛' 
        call add(l:maybe_box, [l:blyi, l:ci])
        break
      elseif c !=# '━'
        throw 'disconnected bottom right'
      endif

      " next char
      let l:ci += 1
    endfor

    " todo check tr -br connection
    " add box to corners
    call add(l:corners, l:maybe_box)
  endfor

  return l:corners
endfunction


" Returns a list of [y, x] coordinate pairs of all top-left corners in {block}
function s:get_tls(block)
  let l:tls = []
  let l:li = 0
  for l in a:block
    let l:ci = 0
    " split each string on char
    for c in split(l, '\zs')
      if c ==# '┏'
        call add(l:tls, [l:li, l:ci])
      endif
      let l:ci += 1
    endfor
    let l:li += 1
  endfor
  return l:tls
endfunction


" Corrects lines in {boxes} that intersect with horizontal lines on the x axis
" between 
function s:fix_lines(boxes, start, cp, y, x)

  let l:lines_to_fix = {}
  " get set of lines affected by operation, mapped to block
  let l:b_set = range(a:cp[0] - a:start, a:cp[0] + a:y  - a:start-1)

  for b in a:boxes

    " skip left boxes and down boxes
    if b[0][1] < a:cp[1] - 1 ||
          \ b[0][0] > a:cp[0] - a:start + a:y
      continue
    endif

    " get set of lines a box touches
    let l:a_set = range(b[0][0], b[2][0])
    " find boxes that touch
    for a in l:a_set
      if match(l:b_set, a) > -1
        " find lines that don't
        for aa in l:a_set
          if match(l:b_set, aa) == -1
            let l:lines_to_fix[a:start + aa] = 1
          endif
        endfor
        " next box
        break
      endif
    endfor
  endfor

  " fix lines that not otherwise moved by operation
  for k in keys(l:lines_to_fix)
    call setline(k, join(extend(
          \ split(getline(k), '\zs'),
          \ repeat([' '], a:x), a:cp[1]-1), ''))
  endfor
endfunction

" function s:fix_cols(boxes, start, fix_start, fix_end, line, n)
"   let l:cols_to_fix
" endfunction
