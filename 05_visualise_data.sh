#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# 1. Interactive Input
echo -e "${CYAN}--- Data Visualization ---${NC}"
read -p "Enter experiment directory [default: test_lysozyme]: " PROJECT_DIR
PROJECT_DIR=${PROJECT_DIR:-test_lysozyme}

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Directory '$PROJECT_DIR' not found."
    exit 1
fi

# Check for GROMACS
if ! command -v gmx &> /dev/null; then
    # Try local install
    if [ -f "$(dirname "$0")/install/bin/GMXRC" ]; then
        source "$(dirname "$0")/install/bin/GMXRC"
    else
        echo "Error: GROMACS not found. Please source GMXRC first."
        exit 1
    fi
fi

cd "$PROJECT_DIR"

# 2. Extract Energy Data
echo -e "${CYAN}--- Extracting Potential Energy ---${NC}"
if [ ! -f "em.edr" ]; then
    echo "Error: 'em.edr' not found in $PROJECT_DIR. Did the simulation run?"
    exit 1
fi

# '10' is usually Potential Energy in GROMACS energy selection
# We pipe "10 0" to select Potential (10) and then exit (0)
echo "10 0" | gmx energy -f em.edr -o energy.xvg

# 3. Clean Data for Gnuplot
# Remove comment lines starting with # or @
grep -v "^[#@]" energy.xvg > clean_energy.dat

# 4. Generate Plot
echo -e "${CYAN}--- Generating Graph (Gnuplot) ---${NC}"
gnuplot <<- EOF
    set terminal pngcairo size 800,600 enhanced font 'Verdana,10'
    set output 'energy_minimization.png'
    set title "Potential Energy Minimization ($PROJECT_DIR)"
    set xlabel "Time (ps)"
    set ylabel "Energy (kJ/mol)"
    set grid
    set style line 1 lc rgb '#0060ad' lt 1 lw 2 pt 7 ps 1.5   # Blue
    plot "clean_energy.dat" using 1:2 with lines ls 1 title 'Potential Energy'
EOF

echo -e "${GREEN}--- Success! ---${NC}"
echo "Graph saved to: $(pwd)/energy_minimization.png"

# Optional: Try to open it if on a desktop environment
if command -v xdg-open &> /dev/null; then
    xdg-open energy_minimization.png
fi
