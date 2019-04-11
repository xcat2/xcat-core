# Welcome to the xCAT documentation

The xCAT docs are hosted here: https://xcat-docs.readthedocs.io/ and are written in reStructuredText (`.rst`). 

## Building Docs

* Clone this project 

* Install or update sphinx (See: https://pip.readthedocs.io/)
   ```
   pip install sphinx
   ```
   or
   ```
   pip install sphinx --upgrade
   ```

* Install ReadTheDocs theme
   ```
   pip install sphinx_rtd_theme
   ```

* Build the Docs
   ```
   cd xcat-core/docs
   make html
   ```

* View the documentation by pointing a browser to: `xcat-core/docs/build/html/index.html`
