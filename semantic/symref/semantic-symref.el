;;; semantic-symref.el --- Symbol Reference API

;; Copyright (C) 2008 Eric M. Ludlam

;; Author: Eric M. Ludlam <eric@siege-engine.com>

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; Semantic Symbol Reference API.
;;
;; Semantic's native parsing tools do not handle symbol references.
;; Tracking such information is a task that requires a huge amount of
;; space and processing not apropriate for an Emacs Lisp program.
;;
;; Many desired tools used in refactoring, however, desire to have
;; such references available to them.  This API aims to provide a
;; range of functions that can be used to identify references.  The
;; API is backed by an OO system that is used to allow multiple
;; external tools to provide the information.
;;
;; To support a new external tool, sublcass `semantic-symref-tool-baseclass'
;; and implement the methods.  The baseclass provides support for
;; managing external processes that produce parsable output.
;;
;; Your tool should then create an instance of `semantic-symref-result'.

(require 'semantic-fw)
(require 'ede)
(eval-when-compile (require 'data-debug)
		   (require 'eieio-datadebug))

;;; Code:
(defvar semantic-symref-tool 'detect
  "*The active symbol reference tool name.
The tool symbol can be 'detect, or a symbol that is the name of
a tool that can be used for symbol referencing.")
(make-variable-buffer-local 'semantic-symref-tool)

(defun semantic-symref-detect-symref-tool ()
  "Detect the symref tool to use for the current buffer."
  (if (not (eq semantic-symref-tool 'detect))
      semantic-symref-tool
    ;; We are to perform a detection for the right tool to use.
    (let* ((rootproj (when (and (featurep 'ede) ede-minor-mode)
		       (ede-toplevel)))
	   (rootdir (if rootproj
			(ede-project-root-directory rootproj)
		      default-directory)))
      (setq semantic-symref-tool
	    (cond
	     ((file-exists-p (expand-file-name "GPATH" rootdir))
	      'global)
	     ;; ADD NEW ONES HERE...


	     ;; The default is grep.
	     (t
	      'grep)))
      )))

(defun semantic-symref-instantiate (&rest args)
  "Instantiate a new symref search object.
ARGS are the initialization arguments to pass to the created class."
  (let* ((srt (symbol-name (semantic-symref-detect-symref-tool)))
	 (class (intern-soft (concat "semantic-symref-tool-" srt)))
	 (inst nil)
	 )
    (when (not (class-p class))
      (error "Unknown symref tool %s" semantic-symref-tool))
    (setq inst (apply 'make-instance class args))
    inst))

(defvar semantic-symref-last-result nil
  "The last calculated symref result.")

(defun semantic-symref-data-debug-last-result ()
  "Run the last symref data result in Data Debug."
  (interactive)
  (if semantic-symref-last-result
      (let* ((ab (data-debug-new-buffer "*Symbol Reference ADEBUG*")))
	(data-debug-insert-object-slots semantic-symref-last-result "]"))
    (message "Empty results.")))

;;;###autoload
(defun semantic-symref-find-references-by-name (name &optional scope)
  "Find a list of references to NAME in the current project.
Optional SCOPE specifies which file set to search.  Defaults to 'project.
Refers to `semantic-symref-tool', to determine the reference tool to use
for the current buffer.
Returns an object of class `semantic-symref-result'."
  (interactive "sName: ")
  (let* ((inst (semantic-symref-instantiate
		:searchfor name
		:searchtype 'symbol
		:searchscope (or scope 'project)
		:resulttype 'line))
	 (result (semantic-symref-get-result inst)))
    (prog1
	(setq semantic-symref-last-result result)
      (when (interactive-p)
	(semantic-symref-data-debug-last-result))))
  )

;;;###autoload
(defun semantic-symref-find-file-references-by-name (name &optional scope)
  "Find a list of references to NAME in the current project.
Optional SCOPE specifies which file set to search.  Defaults to 'project.
Refers to `semantic-symref-tool', to determine the reference tool to use
for the current buffer.
Returns an object of class `semantic-symref-result'."
  (interactive "sName: ")
  (let* ((inst (semantic-symref-instantiate
		:searchfor name
		:searchtype 'regexp
		:searchscope (or scope 'project)
		:resulttype 'file))
	 (result (semantic-symref-get-result inst)))
    (prog1
	(setq semantic-symref-last-result result)
      (when (interactive-p)
	(semantic-symref-data-debug-last-result))))
  )

;;;###autoload
(defun semantic-symref-find-text (text &optional scope)
  "Find a list of occurances of TEXT in the current project.
TEXT is a regexp formatted for use with egrep.
Optional SCOPE specifies which file set to search.  Defaults to 'project.
Refers to `semantic-symref-tool', to determine the reference tool to use
for the current buffer.
Returns an object of class `semantic-symref-result'."
  (interactive "sEgrep style Regexp: ")
  (let* ((inst (semantic-symref-instantiate
		:searchfor text
		:searchtype 'regexp
		:searchscope (or scope 'project)
		:resulttype 'line))
	 (result (semantic-symref-get-result inst)))
    (prog1
	(setq semantic-symref-last-result result)
      (when (interactive-p)
	(semantic-symref-data-debug-last-result))))
  )

;;; RESULTS
;;
;; The results class and methods provide features for accessing hits.
(defclass semantic-symref-result ()
  ((created-by :initarg :created-by
	       :type semantic-symref-tool-baseclass
	       :documentation
	       "Back-pointer to the symref tool creating these results.")
   (hit-files :initarg :hit-files
	      :type list
	      :documentation
	      "The list of files hit.")
   (hit-lines :initarg :hit-lines
	      :type list
	      :documentation
	      "The list of line hits.
Each element is a cons cell of the form (LINE . FILENAME).")
   (hit-tags :initarg :hit-tags
	     :type list
	     :documentation
	     "The list of tags with hits in them.
Use the  `semantic-symref-hit-tags' method to get this list.")
   )
  "The results from a symbol reference search.")

(defmethod semantic-symref-result-get-files ((result semantic-symref-result))
  "Get the list of files from the symref result RESULT."
  (if (slot-boundp result :hit-files)
      (oref result hit-files)
    (let* ((lines  (oref result :hit-lines))
	   (files (mapcar (lambda (a) (cdr a)) lines))
	   (ans nil))
      (setq ans (list (car files))
	    files (cdr files))
      (dolist (F files)
	;; This algorithm for uniqing the file list depends on the
	;; tool in question providing all the hits in the same file
	;; grouped together.
	(when (not (string= F (car ans)))
	  (setq ans (cons F ans))))
      (oset result hit-files (nreverse ans))
      )
    ))

(defmethod semantic-symref-result-get-tags ((result semantic-symref-result))
  "Get the list of tags from the symref result RESULT.
Note: This can be quite slow if most of the hits are not in buffers
already."
  (if (and (slot-boundp result :hit-tags) (oref result hit-tags))
      (oref result hit-tags)
    ;; Calculate the tags.
    (let ((lines (oref result :hit-lines))
	  (last nil)
	  (ans nil)
	  (out nil)
	  (buffs-to-kill nil))
      (save-excursion
	(setq
	 ans
	 (mapcar
	  (lambda (hit)
	    (let* ((line (car hit))
		   (file (cdr hit))
		   (buff (get-file-buffer file))
		   (tag nil)
		   )
	      (cond
	       ;; We have a buffer already.  Check it out.
	       (buff
		(set-buffer buff)
		;; Too much baggage in goto-line
		;; (goto-line line)
		(goto-char (point-min))
		(forward-line (1- line))

		(setq tag (semantic-current-tag)))
	       ;; We have a table, but it needs a refresh.
	       ;; This means we should load in that buffer.
	       (t
		(let ((kbuff (semantic-find-file-noselect file t)))
		  (set-buffer kbuff)
		  (goto-line line)
		  (semantic-fetch-tags)
		  (setq tag (semantic-current-tag))
		  (setq buffs-to-kill (cons kbuff buffs-to-kill))
		  ))
	       )
	      ;; Copy the tag, which adds a :filename property.
	      (setq tag (semantic-tag-copy tag nil t))
	      ;; Ad this hit to the tag.
	      (semantic--tag-put-property tag :hit (list line))
	      tag))
	  lines)))
      ;; Kill off dead buffers.
      (mapc 'kill-buffer buffs-to-kill)
      ;; Strip out duplicates.
      (dolist (T ans)
	(if (and T (not (semantic-equivalent-tag-p (car out) T)))
	    (setq out (cons T out))
	  (when T
	    ;; Else, add this line into the existing list of lines.
	    (let ((lines (append (semantic--tag-get-property (car out) :hit)
				 (semantic--tag-get-property T :hit))))
	      (semantic--tag-put-property (car out) :hit lines)))
	  ))
      ;; Out is reversed... twice
      (oset result :hit-tags (nreverse out)))))

;;; SYMREF TOOLS
;;
;; The base symref tool provides something to hang new tools off of
;; for finding symbol references.
(defclass semantic-symref-tool-baseclass ()
  ((searchfor :initarg :searchfor
	      :type string
	      :documentation "The thing to search for.")
   (searchtype :initarg :searchtype
		:type symbol
		:documentation "The type of search to do.
Values could be `symbol, `regexp, or other.")
   (searchscope :initarg :searchscope
		:type symbol
		:documentation
		"@todo - NEEDS TO BE IMPLEMENTED.
The scope to search for.
Can be 'project, 'target, or 'file.")
   (resulttype :initarg :resulttype
	       :type symbol
	       :documentation
	       "The kind of search results desired.
Can be 'line, 'file, or 'tag.
The type of result can be converted from 'line to 'file, or 'line to 'tag,
but not from 'file to 'line or 'tag.")
   )
  "Baseclass for all symbol references tools.
A symbol reference tool supplies functionality to identify the locations of
where different symbols are used.

Subclasses should be named `semantic-symref-tool-NAME', where
NAME is the name of the tool used in the configuration variable
`semantic-symref-tool'"
  :abstract t)

(defmethod semantic-symref-get-result ((tool semantic-symref-tool-baseclass))
  "Calculate the results of a search based on TOOL.
The symref TOOL should already contain the search criteria."
  (let ((answer (semantic-symref-perform-search tool))
	)
    (when answer
      (let ((answersym (if (eq (oref tool :resulttype) 'file)
			   :hit-files :hit-lines)))
	(semantic-symref-result (oref tool searchfor)
				answersym
				answer
				:created-by tool))
      )
    ))

(defmethod semantic-symref-perform-search ((tool semantic-symref-tool-baseclass))
  "Base search for symref tools should throw an error."
  (error "Symref tool objects must implement `semantic-symref-perform-search'"))

(defmethod semantic-symref-parse-tool-output ((tool semantic-symref-tool-baseclass)
					      outputbuffer)
  "Parse the entire OUTPUTBUFFER of a symref tool.
Calls the method `semantic-symref-parse-tool-output-one-line' over and
over until it returns nil."
  (save-excursion
    (set-buffer outputbuffer)
    (goto-char (point-min))
    (let ((result nil)
	  (hit nil))
      (while (setq hit (semantic-symref-parse-tool-output-one-line tool))
	(setq result (cons hit result)))
      (nreverse result)))
  )

(defmethod semantic-symref-parse-tool-output-one-line ((tool semantic-symref-tool-baseclass))
  "Base tool output parser is not implemented."
  (error "Symref tool objects must implement `semantic-symref-parse-tool-output-one-line'"))

(provide 'semantic-symref)
;;; semantic-symref.el ends here
