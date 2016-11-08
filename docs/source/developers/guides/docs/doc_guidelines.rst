Guidelines for xCAT Documentation
=================================
The following guidelines should be followed when making changes to the xCAT documentation to help create consistency in the documentation.

Document Structure
------------------

Section Structure
`````````````````

xCAT doc page may have 4 levels of title at most: ::

    The First Title
    ===============
    
    The Second Title
    ----------------
    
    The Third Title
    ```````````````
    
    The Forth Title
    '''''''''''''''

List Structure
``````````````

Bullet Lists
''''''''''''

* Bullet one

  The Content.
* Bullet Two

  The Content.

::

    * Bullet one
      The Content.
    * Bullet Two
      The Content.

Enumerated List
'''''''''''''''

1. Item 1

  a) item a
  b) item b

2. Item 2

  a) item a

::

    1. Item 1
      a) item a
      b) item b
    2. Item 2
      a) item a

Include another file
--------------------

To add contents of a document file inside another file, use ``.. include::``. This is usefull when a common information needs to be displayed in multiple files, whithout the use of a hyperlink.
::

 .. include:: config_common.rst


``Note:`` Do not put customized link targets, such as ``.. _my_link_taget:`` inside the file to be included. If you do, a warning for a duplicate label will be displayed during the documentation build process.

Index file
----------

Index.rst files contain the ``.. toctree::`` tag. Files listed under that tag will have links to them displayed in the left side navigation area. If a documentation file does not wish to be accessbile from the navigation area, do not list it under the ``.. toctree::``.

``Note:`` If a file is not listed under the ``.. toctree::`` it might generate a warning during the documentation build ``WARNING: document isn't included in any toctree``. To eliminate such warning, add the file to the ``exclude_patterns`` list in the ``docs/source/conf.py`` file. However, do not add a file to the ``exclude_patterns`` list if it contains a customized link target, such as ``.. _my_link_taget:``. This link target will not be visible to other files and a ``WARNING: undefined label:`` will be displayed during the documentation build.

Hyperlinks -> Internal Links -> External Links
----------------------------------------------

Add links to refer other web page  is a very common way in writting document, it's very helpful to reduce the doc duplication and make docs easy to understand. Following are several ways to add a link in the xCAT documentation.

* **Add an Internal Link to ``Customized Link Target``**

 ``Customized Link Target`` means a user defined **Link Target**.

.. _my_link_target:

 Define a **Link Target** named ``my_link_target``: ::

    .. _my_link_target:

    **Customized Link Target**

    This part of content is a link target which can be linked by other content.

..

 Link to the customized link target ``my_link_target`` :ref:`my link <my_link_target>`: ::

    :ref:`my link <my_link_target>`

..

 ``Usage:`` This method is used to add a **Link Target** in any page that can be referred by any other pages.

* **Add an Internal Link to Current Page**

  Link to an internal section in current page: `Guidelines for xCAT Documentation`_: ::

    `Guidelines for xCAT Documentation`_

..

  ``Usage:`` Every title of a section is an auto-generated 'link target', so you can use it directly. But it's only available inside the current page.

* **Add an Internal Link to Other Page via File Path**

  Link to page `http://server/overview/suport_list.html` with **absolute file path** ::

    :doc:`support list </overview/support_list>`

..

  Link to page `http://server/overview/suport_list.html` with **relative file path** ::

    :doc:`support list <../overview/support_list>`

.. 

  ``Usage:`` When you want to link to another whole page but don't want to make a ``Customized Link Target`` in that source page, you can use the file path to link it directly. 

* **Add an External Link**

  Link to an external web page: `google <http://www.goole.com>`_: ::

    `google <http://www.goole.com>`_

..

  ``Usage:`` When you want to link to a page which does not belong to xCAT documentation.

  ``Note:``  The ``https://`` keyword must be added before the web page URL.

* **Add a Link with Explicit URL Displayed**

  Link to http://www.google.com: ::

    http://www.google.com

..

  ``Usage:`` Make a link and display the URL.


Add OS or ARCH Specific Contents
--------------------------------

When writing a common xCAT doc, we always encounter the case that certain small part of content needs to be OS or ARCH specific. In this case, use the following format to add specific branches.

The keyword in the **[]** can be an OS name or ARCH name, or any name which can distinguish the content from other part.

The valid keyword includes: **RHEL**, **SLES**, **UBUNTU**, **CENTOS**, **X86_64**, **PPC64**, **PPC64LE**. If the keyword is an OS, it can be postfixed with an OS version e.g. RHEL7.

* **[RHEL7]**

  This part of description is for [rh7] specific.

* **[SLES]**

  This part of description is for [sles] specific.

* **[PPC64LE]**

  This part of description is for [ppc64le] specific.

::

    * **[RHEL7]**

      This part of description is for [rh7] specific.


Miscellaneous
-------------

Add a Comment
`````````````

.. Try the comment

The sentence started with ``..`` will be a comment that won't be displayed in the doc. ::

    .. This is a comment

Add Literal Block
`````````````````

If you want to add a paragraph of code or something that don't want to be interpreted by browser: ::

    If you want to add a paragraph of code or something that don't want to be interpreted by browser: ::
        #lsdef node1
        #tabdump

Decorate Word
`````````````

If you want to display one or several words to be ``Literal Word``: ::

    If you want to display one or several words to be ``Literal Word``

If you want to make a **strong emphasis** of the word: ::

    If you want to make a **strong emphasis** of the word:

Add a Table
```````````

Add a table in the doc:

+------------+------------+-----------+ 
| Header 1   | Header 2   | Header 3  | 
+============+============+===========+ 
| body row 1 | column 2   | column 3  | 
+------------+------------+-----------+ 
| body row 2 | Cells may span columns.| 
+------------+------------+-----------+ 
| body row 3 | Cells may  | - Cells   | 
+------------+ span rows. | - contain | 
| body row 4 |            | - blocks. | 
+------------+------------+-----------+

::

    +------------+------------+-----------+
    | Header 1   | Header 2   | Header 3  |
    +============+============+===========+
    | body row 1 | column 2   | column 3  |
    +------------+------------+-----------+
    | body row 2 | Cells may span columns.|
    +------------+------------+-----------+
    | body row 3 | Cells may  | - Cells   |
    +------------+ span rows. | - contain |
    | body row 4 |            | - blocks. |
    +------------+------------+-----------+

Add Footnotes
`````````````

This is the first example of footnotes [1]_.

This is the second example of footnotes [2]_.

::

    This is the first example of footnotes [1]_.
    This is the second example of footnotes [2]_.

    .. [1] First footnote
    .. [2] Second footnote

------------------------

.. [1] First footnote
.. [2] Second footnote



