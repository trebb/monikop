;;;; Make html files from .muse files in current dir, put them into ../html/

;; (color-theme-whateveryouwant)
(require 'muse-mode)
(require 'muse-html)
(require 'muse-project)
(setq muse-html-table-attributes " class=\"muse-table\" border=\"1\" cellpadding=\"5\"")
(setq muse-colors-inline-image-method  #'muse-colors-use-publishing-directory)
(muse-derive-style "xhtml-plainandsimple" "xhtml1.1"
		   :header "<?xml version=\"1.0\" encoding=\"<lisp>
  (muse-html-encoding)</lisp>\"?>
<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" \"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd\">
<html xmlns=\"http://www.w3.org/1999/xhtml\">
  <head>
    <title><lisp>(muse-publishing-directive \"title\")</lisp></title>
    <meta name=\"DC.Title\" content=\"<lisp>(muse-publishing-directive \"title\")</lisp>\" />
    <meta name=\"DC.Creator\" content=\"<lisp>(muse-publishing-directive \"author\")</lisp>\" />
    <meta name=\"author\" content=\"<lisp>(muse-publishing-directive \"author\")</lisp>\" />
    <meta name=\"generator\" content=\"muse.el\" />
    <meta http-equiv=\"<lisp>muse-html-meta-http-equiv</lisp>\" content=\"<lisp>muse-html-meta-content-type</lisp>\" />
    <lisp>
      (let ((maintainer (muse-style-element :maintainer)))
        (when maintainer
          (concat \"<link rev=\\\"made\\\" href=\\\"\" maintainer \"\\\" />\")))
    </lisp><lisp>
     (muse-style-element :style-sheet muse-publishing-current-style)
    </lisp>
  </head>
  <body>
    <div id=\"header\">
      <h1><lisp>(muse-publishing-directive \"title\")</lisp></h1>
      <h2><lisp>(muse-publishing-directive \"subtitle\")</lisp></h2>	
    </div><!-- end header -->
    <div id=\"sidebar\">
     <lisp>(muse-publishing-directive \"sidebar\")</lisp>
      <markup><include file=\"sidebar.muse\"></markup>
    </div><!-- end sidebar -->
    <div id=\"content\">
<!-- Page published by Emacs Muse begins here -->
"
		   :footer "<!-- Page published by Emacs Muse ends here -->
    </div><!-- end content -->
    <div id=\"footer\">
      <div id=\"footer-right\">
        <markup><include file=\"footer-right.muse\"></markup>
      </div>
      <markup><include file=\"footer.muse\"></markup>
    </div><!-- end footer -->
  </body>
</html>"
		   :style-sheet "<style type=\"text/css\">
    /** Style sheet derived from PLAINANDSIMPLE, a free template from         */
    /** http://www.freecsstemplates.org released under a Creative Commons     */
    /** Attribution 2.5 License (http://creativecommons.org/licenses/by/2.5/) */
 /** BASIC */
      body, pre, code, a {
      	margin: 0em;
      	padding: 0em;
      	font-family: \"Courier New\", Courier, monospace;
      }
      pre {
        border-width: thin;
        border-style: dotted;
        border-color: #CCCCCC;
      }
      code {
        border-bottom-width: thin;
        border-bottom-style: dotted;
        border-bottom-color: #CCCCCC;
      }
      h1, h2, h3, h4, h5, h6 {
        margin: 0em;
      	padding: 0em;
      	margin-top: 1em;
      }
      div > p, div > ol, div > ul, div > pre, td, th, dl {
      	font-size: .8em;
      }
      ul {
      	list-style-type: circle;
      }
      table {
        border-collapse: collapse;
      }
      a {
      	color: #000000;
      }
      a:hover {
      	text-decoration: none;
      	background-color: #000000;
      	color: #FFFFFF;
      }
 /** HEADER */
      #header {
      	margin: 0em; 
      	padding: 0em 1em;
      	background-color: #A8A8A8;
      }
      #header h1 {
      	margin: 0em;
      	padding: 0em;
      	color: #FFFFFF;
      }
      #header h2 {
      	margin: 0em;
      	padding: 0em;
      	font-size: 1em;
      	color: #FFFFFF;
      }
 /** SIDEBAR */
      #sidebar {
      	float: left;
      	width: 15%;
        margin: 1em 0em 0em 0em;
      	padding: 1em;
      }
      #sidebar > ul {
      	margin: 0em;
      	padding: 0em;
      	list-style: none;
      	text-align: center;
        font-weight: bold;
      }
      #sidebar * ul {
      	margin: .5em 0em 0em 0em;
      	padding: 0em;
        list-style: none;
        font-weight: normal;
      }
      #sidebar > ul > li {
        padding: 1em 0em;
      }
      #sidebar > ul > li li {
        padding: .3em 0em;
      }
 /** CONTENT */
      #content {
      	float: left;
      	width: 70%;
      }
 /** FOOTER */
      #footer {
      	clear: both;
      	padding: 0px 1em 1px 1em;
      	font-weight: bold;
      	color: #FFFFFF;
      	background-color: #A8A8A8;
      }
      #footer-right {
        float: right;
        font-weight: normal;
      }
      #footer p {
      	margin: 0em;
      	padding: 0em;
      }
      #footer a {
      	color: #FFFFFF;
      }
    </style>")

(setq muse-project-alist
      '(("Monikop and Pokinom"
         ("." :default "index")
         (:base
          "xhtml-plainandsimple"
          :path "../html"
          :exclude "\\(footer.muse\\)\\|\\(footer-right.muse\\)\\|\\(sidebar.muse\\)"))))

(muse-project-publish "Monikop and Pokinom" t)
