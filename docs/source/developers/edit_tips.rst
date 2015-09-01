The Tips to Edit this Document
==============================


Add Links
---------

Add links to refer other web page  is a very common way in writting document, it's very helpful to reduce the doc duplication and make doc to be easy to understand. Following are several ways to add a link in the xCAT documentation.

* Add an Internal Link to ``Customized Link Target``

 ``Customized Link Target`` means a user defined **Link Target**.

Define a **Link Target** named ``my_link_target``:

-------------------

.. _my_link_target:

  **Customized Link Target**

  This part of content is a link target which can be linked by other content.

-------------------

  Link to the customized link target ``my_link_target``: my_link_target_.

 ``Usage:`` This method is used to add a **Link Target** in any page that can be referred by any other pages.

* Add an Internal Link to Current Page

  Link to an internal section in current page: `The Tips to Edit this Document`_.
  
  ``Usage:`` Every title of a section is an auto-generated 'link target', so you can use it directly. But it's only available inside the current page.

* Add an Internal Link to Other Page via File Path

  Link to page ``http://server/overview/suport_list.html`` with absolute file path `support list </overview/support_list.html>`_.

  Link to page ``http://server/overview/suport_list.html`` with relative file path `support list <../overview/support_list.html>`_.

  ``Usage:`` When you want to link to another whole page but don't want to make a ``Customized Link Target`` in that source page, you can use the file path to link it directly. 

* Add an External Link

  Link to an external web page: `google <http://www.goole.com>`_.

  ``Usage:`` When you want to link to a page which does not belong to xCAT documentation.

  ``Note:``  The ``https://`` keyword must be added before the web page URL.

* Add a Link with explicit URL displayed

  Link to http://www.google.com

  ``Usage:`` Make a link and display the URL.

Add OS or ARCH Specific Branches
-----------------------------------------------

When writing a common xCAT doc, we always encounter the case that certain small part of content needs to be OS or ARCH specific. In this case, please use the following format to add specific branches.

* **[RH7]**

  This part of description is for [rh7] specific.

* **[SLES]**

  This part of description is for [sles] specific.

* **[PPC64LE]**

  This part of description is for [ppc64le] specific.



