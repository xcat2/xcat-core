Verify CUDA Installation
========================

The following verification steps only apply to the ``cuda`` (full) installations and require nodes with physical NVIDIA GPU hardware.

#. Verify driver version by looking at: ``/proc/driver/nvidia/version``: ::

    cat /proc/driver/nvidia/version

#. Verify the CUDA Toolkit version ::

    nvcc -V

#. Verify that the CUDA runtime can detect the installed GPUs by compiling and
   executing NVIDIA's ``deviceQuery`` sample.

   CUDA Samples 12.8 and later require CMake 3.20 or later. Select a
   `CUDA Samples release <https://github.com/NVIDIA/cuda-samples/releases>`_
   that is compatible with the Toolkit version reported by ``nvcc -V``.
   Replace ``<samples-tag>`` below with that release tag (for example,
   ``v13.3`` for CUDA 13.3).

   The sample's top-level directory has changed between releases. The
   ``git ls-files`` command below locates it without hard-coding that directory.

   * Clone the selected release and build only ``deviceQuery``: ::

        git clone --branch <samples-tag> --depth 1 \
          https://github.com/NVIDIA/cuda-samples.git
        cd cuda-samples
        sample_dir=$(dirname "$(git ls-files '*/1_Utilities/deviceQuery/CMakeLists.txt')")
        cmake -S "$sample_dir" -B build \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$PWD/build" \
          -DCMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE="$PWD/build"
        cmake --build build --target deviceQuery --config Release --parallel

   * Run the ``deviceQuery`` sample: ::

        ./build/deviceQuery

     Confirm that the output lists each expected GPU and ends with
     ``Result = PASS``.

.. note::

   CUDA Samples releases before 12.8 use release-specific Makefiles. Follow
   the build instructions in the README shipped with the selected tag instead
   of the CMake commands above.

.. note::

   NVIDIA removed ``bandwidthTest`` from CUDA Samples 12.9 because it did not
   produce accurate results. Use
   `NVBandwidth <https://github.com/NVIDIA/nvbandwidth>`_ when bandwidth
   measurements are required.
