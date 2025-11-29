#!/bin/bash
set -e

echo "--- [1/2] Updating Apt Repositories ---"
sudo apt update

echo "--- [2/2] Installing System Dependencies ---"
sudo apt install -y \
    nvidia-cuda-toolkit \
    ncbi-entrez-direct \
    gnuplot \
    cmake \
    build-essential \
    gcc-12 \
    g++-12 \
    libfftw3-dev \
    git

echo "--- Dependency Setup Complete ---"
