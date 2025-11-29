# Protein Folding Workspace

This project contains the setup and maintenance scripts for a high-performance, CUDA-accelerated protein folding environment using GROMACS and NCBI tools.

## Prerequisites
- Ubuntu (25.10 recommended)
- NVIDIA GPU (RTX/CUDA capable)
- NVIDIA Drivers (580+)

## Quick Start

### 1. Install Dependencies
Installs `nvidia-cuda-toolkit`, `ncbi-entrez-direct`, `gnuplot`, and build tools.
```bash
chmod +x 01_setup_dependencies.sh
./01_setup_dependencies.sh
```

### 2. Install GROMACS (Source Compile)
Clones the official repository, configures for CUDA, and installs locally to `./install`.
```bash
chmod +x 02_install_gromacs.sh
./02_install_gromacs.sh
```

### 3. Activate Environment
Add this to your `.bashrc` or run before working:
```bash
source ./install/bin/GMXRC
```

### 4. Test the Pipeline
Run the automated test script to fold Lysozyme (1AKI) and verify CUDA acceleration.
```bash
chmod +x 04_test_folding_pipeline.sh
./04_test_folding_pipeline.sh
```

## Maintenance
Run the maintenance script to verify your driver, CUDA, and GROMACS versions are correctly detected.
```bash
chmod +x 03_maintenance.sh
./03_maintenance.sh
```
