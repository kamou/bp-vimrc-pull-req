" Yet another plugin for text snippets
"     Version:    3.0 2007.08.04
"     Author:     Valyaeff Valentin <hhyperr AT gmail DOT com>
"     License:    GPL
"
" Copyright 2007 Valyaeff Valentin
"
" This program is free software: you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation, either version 3 of the License, or
" (at your option) any later version.
"
" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU General Public License for more details.
"
" You should have received a copy of the GNU General Public License
" along with this program.  If not, see <http://www.gnu.org/licenses/>.


" <<<1 yasnippets#FreezeIndent() and yasnippets#UnfreezeIndent() - not change indent
function! yasnippets#FreezeIndent()
    let b:yasnippets_indent_backup = &indentexpr
    setlocal indentexpr=indent(line('.')-1)
    return ''
endfunction
function! yasnippets#UnfreezeIndent()
    execute "setlocal indentexpr=" . b:yasnippets_indent_backup
    return ''
endfunction

" <<<1 Init code.
"
ruby <<END

# <<<2 Skeleton class
    class Skeleton
        attr_reader :filename

        def initialize(filename, filetype)
            @filename = filename
        end

        def get_binding
            binding
        end

        def ask(prompt)
            return yield if @yes_to_all
            answer = VIM::evaluate("input('#{prompt} [y/n/a] ')").strip.downcase
            if answer =~ /(yes|y|all|a)/
                @yes_to_all = true if answer =~ /(all|a)/
                yield
            end
        end
    end

# <<<2 Include shared.rb
    VIM::evaluate("&runtimepath").
        split(",").
        collect {|directory| Dir.glob("#{directory}/skeletons/shared.rb")}.
        flatten.
        each {|file| load file}

# <<<2 Load a skeleton shared.rb
    def load_skeleton(skeleton, filename, filetype)
        skeleton_lines = IO.readlines(skeleton)
        skeleton_lines.pop if skeleton_lines.last =~ /\Wdelete_line\W/
        begin
            require 'erb'
        rescue LoadError
            VIM::command("echoerr 'ERB library not found'")
        else
            begin
                result = ERB.new(skeleton_lines.join, nil, '-').result(Skeleton.new(filename, filetype).get_binding)
            rescue Exception
                VIM::command("echoerr 'Error in skeleton: #{skeleton}'")
            else
                comments = VIM::evaluate('&comments').split(':')
                buf = VIM::Buffer.current
                pre = buf.line if comments.find { |str| str =~ /^\s*#{Regexp.escape(str)}/ }
                pres = pre.sub(/\s*$/, '') if pre
                result.gsub!('<+', VIM::evaluate("IMAP_GetPlaceHolderStart()"))
                result.gsub!('+>', VIM::evaluate("IMAP_GetPlaceHolderEnd()"))
                lines = result.split("\n")
                lines.each_with_index do |line, number|
                    if pre
                      if line.empty?
                        line = pres
                      else
                        line = pre + line
                      end
                    end
                    if number == 0
                        buf[buf.line_number] = line
                    else
                        buf.append(buf.line_number + number - 1, line)
                    end
                end
                VIM::command("normal #{buf.line_number + lines.size}G")
                VIM::command("set nomodified")
                VIM::command("execute \"normal i\\<c-r>=IMAP_Jumpfunc('', 0)\\<CR>\"")
            end
        end

    end

END

" <<<1 yasnippets#LoadSkeletonByFileType(filetype) - load skeleton file by filetype
function! yasnippets#LoadSkeletonByFileType(filetype)
  if '' == a:filetype
    return
  endif
ruby <<END
    filename = VIM::evaluate("expand('%:p')")
    filetype = VIM::evaluate("a:filetype")

# <<<2 Find skeletons
    skeletons = VIM::evaluate("&runtimepath").
        split(",").
        collect {|directory| ["#{filetype}", "#{filetype}-*", "all-*"].
            collect {|name| Dir.glob("#{directory}/skeletons/templates/#{name}")}}.
        flatten.
        sort_by {|name| [(File.basename(name).
            sub(/^([^-]+).*$/, '\1') == filetype ? 1 : 0), File.basename(name)]}.
        reverse.
        select {|name| ((IO.readlines(name).last =~
            /filematch:\s*\{\{(\/.*\/)\}\}/ and filename !~ eval($1)) ? false : true)}

    if skeletons.length > 1
        answer = VIM::evaluate("inputlist(['There is more than one skeleton:', " +
            skeletons.
            zip((1..skeletons.length).to_a).
            collect {|name, number| "'#{number}. #{File.basename(name).sub(/^[^-]+-/, "").capitalize}'"}.
            join(", ") +
            "])").to_i
    else
        answer = skeletons.length
    end

# <<<2 Load skeletons
    if answer > 0 and answer <= skeletons.length
      load_skeleton(skeletons[answer - 1], filename, filetype)
    end
END
endfunction

function! yasnippets#CompleteSkeleton(findstart, base)

  if a:findstart

    let line = getline('.')
    let start = col('.') - 1

    while start > 0 && line[start - 1] != '=' && line[start - 1] =~ '\f'
      let start -= 1
    endwhile

    return start

  endif

  let cwd = getcwd()
  let matches = []

  silent exe 'chdir '.g:yasnippets_skeletons

  for pattern in [&filetype.'/*', 'general/*']
    call add(matches, glob(pattern))
  endfor

  silent exe 'chdir '.cwd

  let smatches = join(matches, "\n")
  let lmatches = split(smatches, "\n")
  let rmatches = []

  for m in lmatches
    if m =~ '^'.a:base
      call add(rmatches, m)
    endif
  endfor

  return rmatches

endfunction

function! yasnippets#SelectSkeleton(ArgLead, CmdLine, CursorPos)

    let cwd = getcwd()
    let matches = []

    silent exe 'chdir '.g:yasnippets_skeletons

    for pattern in [&filetype.'/*', 'general/*', 'templates/'.&filetype, 'templates/'.&filetype.'-*']
      call add(matches, glob(pattern))
    endfor

    silent exe 'chdir '.cwd

    let smatches = join(matches, "\n")

    return smatches

endfunction

function! yasnippets#LoadSkeletonByName(filename)

  if filereadable(a:filename)
    let skeleton = a:filename
  else
    let skeleton = g:yasnippets_skeletons.'/'.a:filename
  end

  ruby <<END

    skeleton = VIM::evaluate('skeleton')
    filename = VIM::evaluate("expand('%:p')")
    filetype = VIM::evaluate('&filetype')

    load_skeleton(skeleton, filename, filetype)
END

endfunction

" vim:fdm=marker fmr=<<<,>>>
