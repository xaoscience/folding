#!/usr/bin/env bash
set -xe

# --- CONFIGURATION ---
PROJECT_DIR="test_lysozyme"

# Standardized local install path
GMX_BIN="$(dirname "$0")/install/bin/GMXRC"

if [ ! -f "$GMX_BIN" ]; then
    echo "Error: GMXRC not found at $GMX_BIN."
    echo "Please run ./02_install_gromacs.sh to build and install locally."
    exit 1
fi

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}--- [1/6] Initializing Environment ---${NC}"
echo "Sourcing GROMACS from: $GMX_BIN"
source "$GMX_BIN"

# Create a clean workspace
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

echo -e "${CYAN}--- [2/6] Fetching Data (Lysozyme 1AKI) ---${NC}"
# We use wget to pull the PDB structure directly from the Protein Data Bank
wget -q https://files.rcsb.org/download/1AKI.pdb

echo -e "${CYAN}--- [3/6] Generating Topology ---${NC}"
# pdb2gmx converts the coordinate file to a topology
# -ff oplsaa: OPLS-AA Forcefield (All Atom)
# -water spce: SPC/E water model
gmx pdb2gmx -f 1AKI.pdb -o processed.gro -water spce -ff oplsaa

echo -e "${CYAN}--- [4/6] Defining Box & Solvating ---${NC}"
# 1. Define a cubic box with 1.0nm distance from protein to edge
gmx editconf -f processed.gro -o newbox.gro -c -d 1.0 -bt cubic

# 2. Fill the box with water
gmx solvate -cp newbox.gro -cs spc216.gro -o solvated.gro -p topol.top

echo -e "${CYAN}--- [5/6] Neutralizing Ions ---${NC}"
# Generate a .mdp file on the fly for the ion generation step
cat << EOF > ions.mdp
; Ions.mdp - used as input into grompp to generate ions.tpr
integrator  = steep     ; Algorithm (steepest descent minimization)
emtol       = 1000.0    ; Stop minimization when the maximum force < 1000.0 kJ/mol/nm
emstep      = 0.01      ; Minimization step size
nsteps      = 50000     ; Maximum number of (minimization) steps to perform
EOF

# Assemble the binary input
gmx grompp -f ions.mdp -c solvated.gro -p topol.top -o ions.tpr

# Replace solvent (SOL) with ions to reach neutrality
# We pipe "SOL" into the command because it's interactive
echo "SOL" | gmx genion -s ions.tpr -o solvated_ions.gro -p topol.top -pname NA -nname CL -neutral

echo -e "${CYAN}--- [6/6] Running CUDA-Accelerated Minimization ---${NC}"
# Generate the minimization parameter file
cat << EOF > minim.mdp
integrator  = steep
emtol       = 1000.0
emstep      = 0.01
nsteps      = 5000      ; Short run for testing
nstlist     = 1
cutoff-scheme = Verlet
ns_type     = grid
coulombtype = PME
rcoulomb    = 1.0
rvdw        = 1.0
pbc         = xyz
EOF

# Prepare the run
gmx grompp -f minim.mdp -c solvated_ions.gro -p topol.top -o em.tpr

echo -e "${GREEN}>>> STARTING GPU ENGINE <<<${NC}"
# -nb gpu: Offload non-bonded interactions to GPU
# -ntmpi 1: Use 1 MPI thread (efficient for single GPU)
gmx mdrun -v -deffnm em -nb gpu -ntmpi 1

echo -e "${GREEN}--- Test Complete ---${NC}"
echo "If you saw 'Using 1 GPU' in the output above, your build is successful."
echo "Results are in: $(pwd)"