#' Convert R Markdown to a PDF book
#'
#' Convert R Markdown files to PDF after resolving the special tokens of
#' \pkg{bookdown} (e.g., the tokens for references and labels) to native LaTeX
#' commands.
#'
#' This function is based on \code{rmarkdown::\link{pdf_document}} (by default)
#' with better default arguments. You can also change the default format to
#' other LaTeX/PDF format functions using the \code{base_format} argument.
#'
#' The global R option \code{bookdown.post.latex} can be set to a function to
#' post-process the LaTeX output. This function takes the character vector of
#' the LaTeX output as its input argument, and should return a character vector
#' to be written to the \file{.tex} output file. This gives you full power to
#' post-process the LaTeX output.
#' @param toc,number_sections,fig_caption,pandoc_args See
#'   \code{rmarkdown::\link{pdf_document}}, or the documentation of the
#'   \code{base_format} function.
#' @param ... Other arguments to be passed to \code{base_format}.
#' @param base_format An output format function to be used as the base format.
#' @param toc_unnumbered Whether to add unnumberred headers to the table of
#'   contents.
#' @param toc_appendix Whether to add the appendix to the table of contents.
#' @param toc_bib Whether to add the bibliography section to the table of
#'   contents.
#' @param quote_footer If a character vector of length 2 and the quote footer
#'   starts with three dashes (\samp{---}), \code{quote_footer[1]} will be
#'   prepended to the footer, and \code{quote_footer[2]} will be appended; if
#'   \code{NULL}, the quote footer will not be processed.
#' @param highlight_bw Whether to convert colors for syntax highlighting to
#'   black-and-white (grayscale).
#' @note This output format can only be used with \code{\link{render_book}()}.
#' @export
pdf_book = function(
  toc = TRUE, number_sections = TRUE, fig_caption = TRUE, pandoc_args = NULL, ...,
  base_format = rmarkdown::pdf_document, toc_unnumbered = TRUE,
  toc_appendix = FALSE, toc_bib = FALSE, quote_footer = NULL, highlight_bw = FALSE, new_theorems=list(), number_by = list()
) {
  config = get_base_format(base_format, list(
    toc = toc, number_sections = number_sections, fig_caption = fig_caption,
    pandoc_args = pandoc_args2(pandoc_args), ...
  ))
  config$pandoc$ext = '.tex'
  post = config$post_processor  # in case a post processor have been defined
  config$post_processor = function(metadata, input, output, clean, verbose) {
    if (is.function(post)) output = post(metadata, input, output, clean, verbose)
    f = with_ext(output, '.tex')
    new_theorem_abbr = c(theorem_abbr, new_theorems)
    new_label_names_math = c(label_names_math, setNames(names(new_theorems), unlist(new_theorems, use.names=FALSE)))
    new_label_names = c(list(fig = 'Figure ', tab = 'Table ', eq = 'Equation '), new_label_names_math)
    new_label_types = names(new_label_names)
    new_reg_label_types = paste(new_label_types, collapse = '|')
    new_reg_label_types = paste(new_reg_label_types, 'ex', sep = '|')
    x = resolve_new_theorems(read_utf8(f), global = !number_sections, new_theorems, number_by)
    #x = resolve_refs_latex(read_utf8(f), new_reg_label_types)
    x = resolve_refs_latex(x, new_reg_label_types)
    #x = resolve_ref_links_latex(x)
    x = restore_part_latex(x)
    x = restore_appendix_latex(x, toc_appendix)
    if (!toc_unnumbered) x = remove_toc_items(x)
    if (toc_bib) x = add_toc_bib(x)
    x = restore_block2(x, !number_sections, new_theorems, new_theorem_abbr, new_label_names, number_by)
    if (!is.null(quote_footer)) {
      if (length(quote_footer) != 2 || !is.character(quote_footer)) warning(
        "The 'quote_footer' argument should be a character vector of length 2"
      ) else x = process_quote_latex(x, quote_footer)
    }
    if (highlight_bw) x = highlight_grayscale_latex(x)
    post = getOption('bookdown.post.latex')
    if (is.function(post)) x = post(x)

    #The below has to happen after restore_block2 otherwise we don't have the packages we need
    xClear = revise_latex_alts(x, '12')
    xLarge = revise_latex_alts(x, '17')

    outputClear = paste(sans_ext(output), 'Clear.tex', sep='')
    file.copy(output, outputClear)
    fClear = with_ext(outputClear, '.tex')
    outputLarge = paste(sans_ext(output), 'Large.tex', sep='')
    file.copy(output, outputLarge)
    fLarge = with_ext(outputLarge, '.tex')

    write_utf8(x, f)
    write_utf8(xClear, fClear)
    write_utf8(xLarge, fLarge)
    tinytex::latexmk(
      f, config$pandoc$latex_engine,
      if ('--biblatex' %in% config$pandoc$args) 'biber' else 'bibtex'
    )
    tinytex::latexmk(
      fClear, config$pandoc$latex_engine,
      if ('--biblatex' %in% config$pandoc$args) 'biber' else 'bibtex'
    )
    tinytex::latexmk(
      fLarge, config$pandoc$latex_engine,
      if ('--biblatex' %in% config$pandoc$args) 'biber' else 'bibtex'
    )

    output = with_ext(output, '.pdf')
    outputClear = with_ext(paste(sans_ext(output), 'Clear', sep=''), '.pdf')
    outputLarge = with_ext(paste(sans_ext(output), 'Large', sep=''), '.pdf')
    
    o = opts$get('output_dir')
    keep_tex = isTRUE(config$pandoc$keep_tex)
    if (!keep_tex) {
       file.remove(f)
       file.remove(fClear)
       file.remove(fLarge)
    }
    if (is.null(o)) return(output)

    output2 = file.path(o, output)
    output2Clear = file.path(o, outputClear)
    output2Large = file.path(o, outputLarge)
    file.rename(output, output2)
    file.rename(outputClear, output2Clear)
    file.rename(outputLarge, output2Large)
    if (keep_tex) {
       file.rename(f, file.path(o, f))
       file.rename(fClear, file.path(o, fClear))
       file.rename(fLarge, file.path(o, fLarge))
    }
    output2
  }
  # always enable tables (use packages booktabs, longtable, ...)
  pre = config$pre_processor
  config$pre_processor = function(...) {
    c(
      if (is.function(pre)) pre(...), '--variable', 'tables=yes', '--standalone',
      if (rmarkdown::pandoc_available('2.7.1')) '-Mhas-frontmatter=false'
    )
  }
  config$bookdown_output_format = 'latex'
  config = set_opts_knit(config)
  config
}

#' @rdname html_document2
#' @export
pdf_document2 = function(...) {
  pdf_book(..., base_format = rmarkdown::pdf_document)
}

#' @rdname html_document2
#' @export
beamer_presentation2 = function(..., number_sections = FALSE) {
  pdf_book(..., base_format = rmarkdown::beamer_presentation)
}

#' @rdname html_document2
#' @export
tufte_handout2 = function(...) {
  pdf_book(..., base_format = tufte::tufte_handout)
}

#' @rdname html_document2
#' @export
tufte_book2 = function(...) {
  pdf_book(..., base_format = tufte::tufte_book)
}

resolve_refs_latex = function(x, new_reg_label_types) {
  # equation references \eqref{}
  x = gsub(
    '(?<!\\\\textbackslash{})@ref\\((eq:[-/:[:alnum:]]+)\\)', '\\\\eqref{\\1}', x,
    perl = TRUE
  )
  # normal references \ref{}
  x = gsub(
    '(?<!\\\\textbackslash{})@ref\\(([-/:[:alnum:]]+)\\)', '\\\\ref{\\1}', x,
    perl = TRUE
  )
  #print(new_reg_label_types)
  x = gsub(sprintf('\\(\\\\#((%s):[-/[:alnum:]]+)\\)', new_reg_label_types), '\\\\label{\\1}', x)
  x
}

resolve_ref_links_latex = function(x) {
  res = parse_ref_links(x, '^%s (.+)$')
  if (is.null(res)) return(x)
  x = res$content; txts = res$txts; i = res$matches
  # text for a tag may be wrapped into multiple lines; collect them until the
  # empty line
  for (j in seq_along(i)) {
    k = 1
    while (x[i[j] + k] != '') {
      txts[j] = paste(txts[j], x[i[j] + k], sep = '\n')
      x[i[j] + k] = ''
      k = k + 1
    }
  }
  restore_ref_links(x, '(?<!\\\\texttt{)%s', res$tags, txts, FALSE)
}

restore_part_latex = function(x) {
  r = '^\\\\(chapter|section)\\*\\{\\(PART(\\*)?\\)( |$)'
  i = grep(r, x)
  if (length(i) == 0) return(x)
  x[i] = gsub(r, '\\\\part\\2{', x[i])
  # remove (PART*) from the TOC lines for unnumbered parts
  r = '^(\\\\addcontentsline\\{toc\\}\\{)(chapter|section)(\\}\\{)\\(PART\\*\\)( |$)'
  x = gsub(r, '\\1part\\3', x)
  # for numbered parts, remove the line \addcontentsline since it is not really
  # a chapter title and should not be added to TOC
  j = grep('^\\\\addcontentsline\\{toc\\}\\{(chapter|section)\\}\\{\\(PART\\)( |$)', x)
  k = j; n = length(x)
  for (i in seq_along(j)) {
    # figure out how many lines \addcontentsline{toc} spans over (search until
    # it finds an empty line)
    l = 1
    while (j[i] + l <= n && x[j[i] + l] != '') {
      k = c(k, j[i] + l)
      l = l + 1
    }
  }
  if (length(k)) x = x[-k]
  x
}

restore_appendix_latex = function(x, toc = FALSE) {
  r = '^\\\\(chapter|section)\\*\\{\\(APPENDIX\\) .*'
  i = find_appendix_line(r, x)
  if (length(i) == 0) return(x)
  level = gsub(r, '\\1', x[i])
  brace = grepl('}}$', x[i])
  x[i] = '\\appendix'
  if (toc) x[i] = paste(
    x[i], sprintf('\\addcontentsline{toc}{%s}{\\appendixname}', level)
  )
  if (brace) x[i] = paste0(x[i], '}')  # pandoc 2.0
  if (grepl('^\\\\addcontentsline', x[i + 1])) x[i + 1] = ''
  x
}

find_appendix_line = function(r, x) {
  i = grep(r, x)
  if (length(i) > 1) stop('You must not have more than one appendix title')
  i
}

revise_latex_alts = function(x,pointsize) {
  clearfile = bookdown_file('templates','Clear.tex')
  clearstring = paste(read_utf8(clearfile), collapse = "\n")
  clearstring = gsub('\\\\', '\\\\\\\\', clearstring)
  x = gsub('\\{article\\}','\\{extarticle\\}', x)
  x = gsub('\\{report\\}','\\{extreport\\}', x)
  x = gsub('\\\\begin\\{document\\}', sprintf('\n\n%s\n\n\\\\begin\\{document\\}', clearstring), x)
  x = gsub('\\\\documentclass\\[\\d+pt',sprintf('\\\\documentclass\\[%spt',pointsize),x)
  x
}

remove_toc_items = function(x) {
  r = '^\\\\addcontentsline\\{toc\\}\\{(part|chapter|section|subsection|subsubsection)\\}\\{.+\\}$'
  x[grep(r, x)] = ''
  x
}

add_toc_bib = function(x) {
  r = '^\\\\bibliography\\{.+\\}$'
  i = grep(r, x)
  if (length(i) == 0) return(x)
  i = i[1]
  level = if (length(grep('^\\\\chapter\\*?\\{', x))) 'chapter' else 'section'
  x[i] = sprintf('%s\n\\addcontentsline{toc}{%s}{\\bibname}', x[i], level)
  x
}

restore_block2 = function(x, global = FALSE, new_theorems, new_theorem_abbr, new_label_names, number_by) {
  new_number_by = setNames(unlist(new_theorems, use.name=FALSE), unlist(new_theorems, use.names=FALSE))
  #Recall: number_by at this point is from the user and defines counter shares, it is prepended so that the entry 'overrides' the default
  number_by = c(number_by,list('thm'='thm','lem'='lem','cor'='cor','prp'='prp','cnj'='cnj','def' = 'def','exm'='exm','exr'='exr'),new_number_by)

  new_label_prefix = function(type, dict = new_label_names) i18n('label', type, dict)

  i = grep('^\\\\begin\\{document\\}', x)[1]
  if (is.na(i)) return(x)
  if (length(grep('\\\\(Begin|End)KnitrBlock', tail(x, -i))))
    x = append(x, '\\let\\BeginKnitrBlock\\begin \\let\\EndKnitrBlock\\end', i - 1)
  if (length(grep(sprintf('^\\\\BeginKnitrBlock\\{(%s)\\}', paste(all_math_env, collapse = '|')), x)) &&
      length(grep('^\\s*\\\\newtheorem\\{theorem\\}', head(x, i))) == 0) {
      #This array aligns to theorem_abbr but has those sharing a counter replaced by the env they share the counter with
      #You can't use aligned_abbr = theorem_abbr[match(number_by[match(theorem_abbr,number_by)],theorem_abbr)] when there are matches in the counter shares
      aligned_abbr = new_theorem_abbr[match(unlist(number_by[match(unlist(new_theorem_abbr,use.names = FALSE),names(number_by))],use.names = FALSE),new_theorem_abbr)]
      #These are the locations of the envs which share a counter
      duplicated_abbrLoc = which(duplicated(names(aligned_abbr)))
      #These are the locations of the envs which have their counter being shared
      counters_abbrLoc = unique(match(names(aligned_abbr[duplicated_abbrLoc]),names(aligned_abbr)))
      #These are the locations of all the envs which share counters and those which they share
      allcounted_abbrLoc = c(counters_abbrLoc,duplicated_abbrLoc)
      #These are the locations of all the envs that don't share a counter
      noncounters_abbrLoc = match(names(aligned_abbr[-allcounted_abbrLoc]),names(aligned_abbr))

      #The envs which are going to share their counter
      theorem_counters_defs = sprintf(
        '%s\\newtheorem{%s}{%s}%s', theorem_style(names(aligned_abbr[counters_abbrLoc])), names(aligned_abbr[counters_abbrLoc]),
      	str_trim(vapply(aligned_abbr[counters_abbrLoc], new_label_prefix, character(1), USE.NAMES = FALSE)),
      	if (global) '' else {
           if (length(grep('^\\\\chapter[*]?', x))) '[chapter]' else '[section]'
      	}
      )

      #The envs which share a counter, these pick up their names from the original theorem_abbr using the aligned locations
      theorem_counted_defs = sprintf(
        '%s\\newtheorem{%s}[%s]{%s}', theorem_style(names(aligned_abbr[duplicated_abbrLoc])), names(new_theorem_abbr[duplicated_abbrLoc]), names(aligned_abbr[duplicated_abbrLoc]),
      	str_trim(vapply(new_theorem_abbr[duplicated_abbrLoc], new_label_prefix, character(1), USE.NAMES = FALSE))
      )

      #The envs which use their own counter and do not share it
      theorem_rest_defs = sprintf(
        '%s\\newtheorem{%s}{%s}%s', theorem_style(names(aligned_abbr[noncounters_abbrLoc])), names(aligned_abbr[noncounters_abbrLoc]),
      	str_trim(vapply(aligned_abbr[noncounters_abbrLoc], new_label_prefix, character(1), USE.NAMES = FALSE)),
	if (global) '' else {
	   if (length(grep('^\\\\chapter[*]?', x))) '[chapter]' else '[section]'
	}
      )

      # the proof environment has already been defined by amsthm
      proof_envs = setdiff(names(label_names_math2), 'proof')
      proof_defs = sprintf(
        '%s\\newtheorem*{%s}{%s}', theorem_style(proof_envs), proof_envs,
      	gsub('^\\s+|[.]\\s*$', '', vapply(proof_envs, new_label_prefix, character(1), label_names_math2))
    	)
    	x = append(x, c('\\usepackage{amsthm}', theorem_counters_defs, theorem_counted_defs, theorem_rest_defs, proof_defs), i - 1)
  }
  # remove the empty lines around the block2 environments
  i3 = if (length(i1 <- grep('^\\\\BeginKnitrBlock\\{', x))) (i1 + 1)[x[i1 + 1] == '']
  i3 = c(i3, if (length(i2 <- grep('^\\\\EndKnitrBlock\\{', x))) (i2 - 1)[x[i2 - 1] == ''])
  if (length(i3)) x = x[-i3]

  r = '^(.*\\\\BeginKnitrBlock\\{[^}]+\\})(\\\\iffalse\\{-)([-0-9]+)(-\\}\\\\fi\\{\\})(.*)$'
  if (length(i <- grep(r, x)) == 0) return(x)
  opts = sapply(strsplit(gsub(r, '\\3', x[i]), '-'), function(z) {
    intToUtf8(as.integer(z))
  }, USE.NAMES = FALSE)
  x[i] = paste0(gsub(r, '\\1', x[i]), opts, gsub(r, '\\5', x[i]))
  x
}

#We need a plain theorem style to be defined so that we can reset when outputting shared counter setups
style_plain = c('theorem', 'lemma', 'corollary', 'proposition', 'conjecture')
style_definition = c('definition', 'example', 'exercise')
style_remark = c('remark')
# which styles of theorem environments to use
theorem_style = function(env) {
  styles = character(length(env))
  styles[env %in% style_plain] = '\\theoremstyle{plain}\n'
  styles[env %in% style_definition] = '\\theoremstyle{definition}\n'
  styles[env %in% style_remark] = '\\theoremstyle{remark}\n'
  styles
}

process_quote_latex = function(x, commands) {
  for (i in grep('^\\\\end\\{quote\\}$', x)) {
    i1 = NULL; i2 = i - 1
    k = 1
    while (k < i) {
      xk = x[i - k]
      if (grepl('^---.+', xk)) {
        i1 = i - k
        break
      }
      if (xk == '' || grepl('^\\\\begin', xk)) break
      k = k + 1
    }
    if (is.null(i1)) next
    x[i1] = paste0(commands[1], x[i1])
    x[i2] = paste0(x[i2], commands[2])
  }
  x
}

# \newenvironment{Shaded}{\begin{snugshade}}{\end{snugshade}}
# \newcommand{\KeywordTok}[1]{\textcolor[rgb]{x.xx,x.xx,x.xx}{\textbf{{#1}}}}
# \newcommand{\DataTypeTok}[1]{\textcolor[rgb]{x.xx,x.xx,x.xx}{{#1}}}
# ...
highlight_grayscale_latex = function(x) {
  i1 = grep('^\\\\newenvironment\\{Shaded\\}', x)
  if (length(i1) == 0) return(x)
  i1 = i1[1]
  r1 = '^\\\\newcommand\\{\\\\[a-zA-Z]+\\}\\[1]\\{.*\\{#1\\}.*\\}$'
  r2 = '^(.*?)([.0-9]+,[.0-9]+,[.0-9]+)(.*)$'
  i = i1 + 1
  while (grepl('^\\\\newcommand\\{.+\\}$', x[i])) {
    if (grepl(r1, x[i]) && grepl(r2, x[i])) {
      col = as.numeric(strsplit(gsub(r2, '\\2', x[i]), ',')[[1]])
      x[i] = gsub(
        r2, paste0('\\1', paste(round(rgb2gray(col), 2), collapse = ','), '\\3'),
        x[i]
      )
    }
    i = i + 1
  }
  x
}

# https://en.wikipedia.org/wiki/Grayscale
rgb2gray = function(x, maxColorValue = 1) {
  rep(sum(c(.2126, .7152, .0722) * x/maxColorValue), 3)
}
