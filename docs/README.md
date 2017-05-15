# Welcome to the xCAT documentation

The latest docs are here: http://xcat-docs.readthedocs.io/en/latest/

The documentation project is written in restructured text (.rst) using Sphinx and hosted on ReadTheDocs.

## Building Documentation

* Clone the project

* Using pip, install or update sphinx (See: http://pip.readthedocs.org/)
   ```
    pip install sphinx  
   ```
   or
   ```
    pip install sphinx --upgrade 
   ```

* Using pip, install ReadTheDocs theme
   ```
   pip install sphinx_rtd_theme
   ```

* Build the Docs
   ```
    cd xcat-core/docs
    make html
   ```

* View the docs by opening index.html from a web browser under xcat-core/docs/build/html/index.html
