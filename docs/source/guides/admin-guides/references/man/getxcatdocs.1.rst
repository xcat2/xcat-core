
#############
getxcatdocs.1
#############

.. highlight:: perl


****
NAME
****


\ **getxcatdocs**\  - downloads the xCAT documentation and converts to HTML and PDF


********
SYNOPSIS
********


\ **getxcatdocs**\  [\ **-?**\  | \ **-h**\  | \ **--help**\ ]
\ **getxcatdocs**\  [\ **-v**\  | \ **--verbose**\ ] [\ *destination-dir*\ ]
\ **getxcatdocs**\  [\ **-v**\  | \ **--verbose**\ ] [\ **-c**\  | \ **--continue**\ ] [\ **-d**\  | \ **--doc**\  \ *single_doc*\ ] [\ *destination-dir*\ ]


***********
DESCRIPTION
***********


The \ **getxcatdocs**\  command downloads the xCAT documentation from the wiki and converts it to both HTML and PDF.
This enables reading the documentation when you do not have internet access.  Note that this command does not
download/convert the entire xCAT wiki - only the "official" xCAT documentation linked from http://sourceforge.net/p/xcat/wiki/XCAT_Documentation.

If \ *destination-dir*\  is specified, \ **getxcatdocs**\  will put the converted documentation in that directory, in 3 sub-directories: html, pdf, images.
Otherwise, it will put it in the current directory (in the same three sub-directories).

If \ **--doc**\  \ *single_doc*\  is specified, only that one wiki page will be downloaded and converted.

\ **getxcatdocs**\  uses curl to run the Allura wiki API to download the document markdown text, and Pandoc with LaTex them to PDF.  You must have all of these functions installed to run \ **getxcatdocs**\ .  See:
http://sourceforge.net/p/xcat/wiki/Editing_and_Downloading_xCAT_Documentation/#converting-wiki-pages-to-html-and-pdfs

Limitations:
============



\*
 
 This command does not run on AIX or Windows.
 




*******
OPTIONS
*******



\ **-?|-h|--help**\ 
 
 Display usage message.
 


\ **-v|--verbose**\ 
 
 Run the command in verbose mode.
 


\ **-c|--continue**\ 
 
 If a previous run of this command failed (which often happens if you lose your network connection), continue processing using files already downloaded to your markdown directory.
 


\ **-d|--doc**\  \ *single_doc*\ 
 
 Run this command for a single document only.  If you get errors about Official-xcat-doc.png not found, either download this image directly from http://sourceforge.net/p/xcat/wiki/XCAT_Documentation/attachment/Official-xcat-doc.png or run \ **getxcatdocs -d XCAT_Documentation**\  first.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1.
 
 To download/convert the documentation and put it in ~/tmp:
 
 
 .. code-block:: perl
 
   getxcatdocs ~/tmp
 
 



*****
FILES
*****


/opt/xcat/bin/getxcatdocs

