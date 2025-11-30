#!/bin/bash
set -xe
cd "$(dirname "$0")"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}--- [07] High-Throughput Variant Screening ---${NC}"

# 1. Configuration
EXPERIMENTS_ROOT="experiments"
LEGACY_MODE=false

if [ -n "$1" ]; then
    EXP_DIR="${1%/}"
else
    # Try to find latest experiment (recursively in experiments/PROTEIN/TIMESTAMP_MODE)
    # We look for directories containing 'variants' subdir
    LATEST_EXP=$(find "$EXPERIMENTS_ROOT" -maxdepth 2 -name "variants" -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n 1 | awk '{print $2}')
    
    if [ -n "$LATEST_EXP" ]; then
        # LATEST_EXP is .../variants, we want the parent
        EXP_DIR=$(dirname "$LATEST_EXP")
        echo -e "${YELLOW}No experiment specified. Defaulting to latest: $EXP_DIR${NC}"
    elif [ -d "candidates" ]; then
        echo -e "${YELLOW}No experiment specified. Using legacy 'candidates' directory.${NC}"
        EXP_DIR="."
        CANDIDATES_DIR="candidates"
        RESULTS_DIR="screening_runs"
        REPORT_FILE="ranking_report.csv"
        LEGACY_MODE=true
    else
        echo -e "${RED}Usage: $0 <experiment_directory>${NC}"
        echo "Example: $0 experiments/20251130_1200_1AKI_fragments"
        exit 1
    fi
fi

if [ "$LEGACY_MODE" != "true" ]; then
    CANDIDATES_DIR="$EXP_DIR/variants"
    RESULTS_DIR="$EXP_DIR/screening"
    REPORT_FILE="$EXP_DIR/ranking_report.csv"
fi

GMX_RC="$(pwd)/install/bin/GMXRC"

# Check GROMACS
if [ -f "$GMX_RC" ]; then
    source "$GMX_RC"
else
    if ! command -v gmx &> /dev/null; then
        echo -e "${RED}Error: GROMACS not found. Run ./02_install_gromacs.sh first.${NC}"
        exit 1
    fi
fi

# Check Input
if [ ! -d "$CANDIDATES_DIR" ] || [ -z "$(ls -A $CANDIDATES_DIR/*.pdb 2>/dev/null)" ]; then
    echo -e "${RED}Error: No PDB files found in '$CANDIDATES_DIR/'.${NC}"
    echo "Please create the directory and add .pdb files (or wait for Step 06)."
    mkdir -p "$CANDIDATES_DIR"
    exit 1
fi

mkdir -p "$RESULTS_DIR"
echo "Variant,Potential_Energy_kJ_mol" > "$REPORT_FILE"

# 2. Helper: Create MDP files
create_mdp_files() {
    local dir=$1
    
    # Ions parameters
    cat > "$dir/ions.mdp" <<EOF
; ions.mdp - used as input into grompp to generate ions.tpr
integrator  = steep     ; Algorithm (steep = steepest descent minimization)
emtol       = 1000.0    ; Stop minimization when the maximum force < 1000.0 kJ/mol/nm
emstep      = 0.01      ; Minimization step size
nsteps      = 50000     ; Maximum number of (minimization) steps to perform
nstlist     = 1         ; Frequency to update the neighbor list and long range forces
cutoff-scheme = Verlet  ; Buffered neighbor searching
ns_type     = grid      ; Method to determine neighbor list (simple, grid)
coulombtype = PME       ; Treatment of long range electrostatic interactions
rcoulomb    = 1.0       ; Short-range electrostatic cut-off
rvdw        = 1.0       ; Short-range Van der Waals cut-off
pbc         = xyz       ; Periodic Boundary Conditions
EOF

    # Minimization parameters
    cat > "$dir/minim.mdp" <<EOF
; minim.mdp - used as input into grompp to generate em.tpr
integrator  = steep     ; Algorithm (steep = steepest descent minimization)
emtol       = 1000.0    ; Stop minimization when the maximum force < 1000.0 kJ/mol/nm
emstep      = 0.01      ; Minimization step size
nsteps      = 50000     ; Maximum number of (minimization) steps to perform
nstlist     = 1         ; Frequency to update the neighbor list and long range forces
cutoff-scheme = Verlet  ; Buffered neighbor searching
ns_type     = grid      ; Method to determine neighbor list (simple, grid)
coulombtype = PME       ; Treatment of long range electrostatic interactions
rcoulomb    = 1.0       ; Short-range electrostatic cut-off
rvdw        = 1.0       ; Short-range Van der Waals cut-off
pbc         = xyz       ; Periodic Boundary Conditions
EOF
}

# 3. Main Loop
count=0
total=$(ls $CANDIDATES_DIR/*.pdb | wc -l)

for pdb_file in "$CANDIDATES_DIR"/*.pdb; do
    variant_name=$(basename "$pdb_file" .pdb)
    run_dir="$RESULTS_DIR/$variant_name"
    count=$((count + 1))
    
    echo -e "${CYAN}[$count/$total] Processing variant: $variant_name${NC}"
    
    # Setup directory
    if [ -d "$run_dir" ]; then rm -rf "$run_dir"; fi
    mkdir -p "$run_dir"
    cp "$pdb_file" "$run_dir/protein.pdb"
    create_mdp_files "$run_dir"
    
    pushd "$run_dir" > /dev/null
    
    # --- Pipeline ---
    
    # A. Topology (pdb2gmx)
    # Using OPLS-AA force field and TIP3P water model
    echo "  > Generating topology..."
    if ! gmx pdb2gmx -f protein.pdb -o processed.gro -water tip3p -ff oplsaa &> gmx_topology.log; then
        echo -e "${RED}  > Topology generation failed! Check gmx_topology.log${NC}"
        popd > /dev/null
        echo "$variant_name,FAILED" >> "$REPORT_FILE"
        continue
    fi
    
    # B. Define Box
    echo "  > Defining simulation box..."
    gmx editconf -f processed.gro -o newbox.gro -c -d 1.0 -bt cubic &> gmx_box.log
    
    # C. Solvate
    echo "  > Solvating..."
    gmx solvate -cp newbox.gro -cs spc216.gro -o solvated.gro -p topol.top &> gmx_solvate.log
    
    # D. Add Ions
    echo "  > Adding ions..."
    if ! gmx grompp -f ions.mdp -c solvated.gro -p topol.top -o ions.tpr -maxwarn 1 &> gmx_ions_prep.log; then
        echo -e "${RED}  > Ion preparation failed! Check gmx_ions_prep.log${NC}"
        popd > /dev/null
        echo "$variant_name,FAILED_IONS" >> "$REPORT_FILE"
        continue
    fi
    # Select group 13 (SOL) automatically for replacing solvent with ions
    if ! echo "SOL" | gmx genion -s ions.tpr -o solvated_ions.gro -p topol.top -pname NA -nname CL -neutral &> gmx_genion.log; then
        echo -e "${RED}  > Ion generation failed! Check gmx_genion.log${NC}"
        popd > /dev/null
        echo "$variant_name,FAILED_GENION" >> "$REPORT_FILE"
        continue
    fi
    
    # E. Energy Minimization
    echo "  > Running energy minimization (GPU)..."
    if ! gmx grompp -f minim.mdp -c solvated_ions.gro -p topol.top -o em.tpr &> gmx_minim_prep.log; then
        echo -e "${RED}  > Minimization prep failed! Check gmx_minim_prep.log${NC}"
        popd > /dev/null
        echo "$variant_name,FAILED_MINIM_PREP" >> "$REPORT_FILE"
        continue
    fi
    if ! gmx mdrun -v -deffnm em -nb gpu &> gmx_minim_run.log; then
        echo -e "${RED}  > Minimization run failed! Check gmx_minim_run.log${NC}"
        popd > /dev/null
        echo "$variant_name,FAILED_MINIM_RUN" >> "$REPORT_FILE"
        continue
    fi
    
    # F. Extract Energy
    echo "  > Extracting potential energy..."
    # 10 is Potential, 0 is exit
    echo "10 0" | gmx energy -f em.edr -o energy.xvg &> gmx_energy.log
    
    # Parse the final potential energy from the output
    energy_val=$(grep -v "^[#@]" energy.xvg | tail -n 1 | awk '{print $2}')
    
    echo "  > Result: $energy_val kJ/mol"
    
    popd > /dev/null
    
    # Append to report
    echo "$variant_name,$energy_val" >> "$REPORT_FILE"
done

# 4. Sort and Display Results
echo -e "${GREEN}--- Screening Complete ---${NC}"
echo -e "${CYAN}Top Variants (Lowest Energy = Most Stable):${NC}"

# Sort by 2nd column (energy), numerical sort. 
# Note: Energy is negative, so "lowest" (most negative) is most stable.
if [ -s "$REPORT_FILE" ]; then
    # Skip header, sort, then add header back for display
    (head -n 1 "$REPORT_FILE" && tail -n +2 "$REPORT_FILE" | sort -t, -k2g) | column -s, -t
else
    echo "No results found."
fi

echo -e "\nFull report saved to: ${GREEN}$REPORT_FILE${NC}"
