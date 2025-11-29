#!/bin/bash
set -xe
cd "$(dirname "$0")"

# --- CONFIGURATION ---
REPO_URL="https://github.com/gromacs/gromacs.git"
GMX_VERSION="v2026-beta" 
# Standardize on a local installation within the project folder
INSTALL_PREFIX="$(pwd)/install"
BUILD_DIR="build"

echo "--- [1/4] Preparing GROMACS Source (Submodule) ---"
git submodule update --init --recursive gromacs-src
cd gromacs-src
echo "Checking out version: $GMX_VERSION"
git fetch --tags
git checkout $GMX_VERSION
cd ..
echo "--- [2/4] Configuring Build (CMake) ---"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# CMake Flags:
# -DGMX_GPU=CUDA : Enable NVIDIA GPU acceleration
# -DGMX_BUILD_OWN_FFTW=OFF : Already installed as  system lib
# -DCMAKE_C_COMPILER & -DCMAKE_CXX_COMPILER : Force usage of GCC 12 for CUDA compatibility
cmake ../gromacs-src \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
    -DGMX_BUILD_OWN_FFTW=OFF \
    -DGMX_GPU=CUDA \
    -DCUDA_TOOLKIT_ROOT_DIR=/usr/lib/nvidia-cuda-toolkit \
    -DCMAKE_C_COMPILER=gcc-12 \
    -DCMAKE_CXX_COMPILER=g++-12

echo "--- [3/4] Compiling (This will take time) ---"
# Use all available cores
make -j$(nproc)

echo "--- [4/4] Installing to $INSTALL_PREFIX ---"
make install

echo "--- Installation Complete ---"
echo "To use GROMACS, run:"
echo "  source $INSTALL_PREFIX/bin/GMXRC"
