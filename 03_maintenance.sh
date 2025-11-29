#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "--- System Health Check ---"

# 1. Check NVIDIA Driver
echo -n "NVIDIA Driver: "
if command -v nvidia-smi &> /dev/null; then
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader)
    echo -e "${GREEN}OK ($DRIVER_VER)${NC}"
else
    echo -e "${RED}NOT FOUND${NC}"
fi

# 2. Check CUDA Compiler
echo -n "NVCC (CUDA):   "
if command -v nvcc &> /dev/null; then
    CUDA_VER=$(nvcc --version | grep release | awk '{print $6}' | cut -c2-)
    echo -e "${GREEN}OK ($CUDA_VER)${NC}"
else
    echo -e "${RED}NOT FOUND${NC}"
fi

# 3. Check GROMACS
echo -n "GROMACS:       "
# Check if GMX is in path, if not try to source it temporarily to check
if ! command -v gmx &> /dev/null; then
    if [ -f "/usr/local/gromacs/bin/GMXRC" ]; then
        source /usr/local/gromacs/bin/GMXRC
    fi
fi

if command -v gmx &> /dev/null; then
    GMX_VER=$(gmx --version | grep "GROMACS version" | awk '{print $3}')
    echo -e "${GREEN}OK ($GMX_VER)${NC}"
else
    echo -e "${RED}NOT FOUND (Did you source GMXRC?)${NC}"
fi

# 4. Check NCBI Tools
echo -n "NCBI EDirect:  "
if command -v esearch &> /dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}NOT FOUND${NC}"
fi

echo "--- Check Complete ---"
