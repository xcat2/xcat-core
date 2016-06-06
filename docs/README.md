# Welcome to the xCAT documentation

The latest docs are here: http://xcat-docs.readthedocs.io/en/latest/

Status:   
[![Documentation Status](http://readthedocs.org/projects/xcat-docs/badge/?version=latest)](http://xcat-docs.readthedocs.io/en/latest/?badge=latest)
[![Documentation Status](http://readthedocs.org/projects/xcat-docs/badge/?version=2.11)](http://xcat-docs.readthedocs.io/en/2.11/?badge=2.11)


The documentation project is written in restructured text (.rst) using Sphinx and hosted on ReadTheDocs.

## Building Documentation

* Clone the project

* Using pip, install sphinx (See: http://pip.readthedocs.org/)
   ```
    pip install sphinx  
   ```

* Build the Docs
   ```
    cd xcat-core/docs
    make html
   ```

* View the docs by opening index.html from a web browser under xcat-core/docs/build/html/index.html
